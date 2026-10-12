#if OKVIDEO_CRASH_ACCEPTANCE
import Foundation
import OKCrashDiagnostics

/// Test-only driver for the same adapter/coordinator used by the UI. Never uses real Sentry config.
@MainActor enum CrashUploadProbe {
    static func runModel(session: AppLaunchSession, args: [String]) {
        let model = session.diagnostics
        model.start()
        if args.contains("--diagnostic-grant") { model.setConsent(true) }
        if args.contains("--diagnostic-revoke") { model.setConsent(false) }
        while model.sending || model.revoking { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        let object: [String: Any] = ["consent": model.consent, "pending": model.pendingReports,
            "status": String(describing: model.status), "cacheExists": session.crashManager.map { FileManager.default.fileExists(atPath: $0.store.cache.path) } ?? false,
            "businessInitialized": false, "captureAvailable": session.crashManager != nil]
        print(String(decoding: try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self))
    }
    static func run(store: ReportStore, args: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i+1 < args.count else { return nil }; return args[i+1]
        }
        let fault = value("--worker-fault").flatMap(UploadWorkerFault.init(rawValue:)) ?? .none
        let dsn = value("--test-dsn") ?? "http://test@127.0.0.1:1/1"
        let start = ProcessInfo.processInfo.systemUptime
        var last = start, maxGap = 0.0, ticks = 0, callbacks = 0, outcomes = [String](), fdCounts = [Int]()
        func fds() -> Int { (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1 }
        let heartbeat = Timer(timeInterval: 0.01, repeats: true) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            maxGap = max(maxGap, now - last); last = now; ticks += 1
        }
        RunLoop.main.add(heartbeat, forMode: .common)
        defer { heartbeat.invalidate() }
        do {
            try store.setConsent(true)
            if args.contains("--rapid-regrant") {
                let model = CrashUploadController(store: store, configuration: CrashUploadConfiguration(dsn: dsn, allowLoopback: true, fault: fault)); model.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    model.setConsent(false); model.setConsent(true)
                }
                while model.sending || model.revoking { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                outcomes.append(model.consent ? "regranted" : "closed")
            } else {
                let adapter = SentryAdapter(store: store, faultForTests: fault)
                let count = min(30, max(1, Int(value("--attempts") ?? "1") ?? 1))
                guard let record = try store.records().first else { throw CrashDiagnosticError.invalidReport }
                for index in 0..<count {
                  autoreleasepool {
                    var done = false
                    do {
                        try adapter.send(record, dsn: dsn, allowLoopback: true) { outcome in
                            callbacks += 1; outcomes.append(outcome.result)
                            if !outcome.handlersUnchanged { outcomes.append("HANDLERS_CHANGED") }
                            done = true
                        }
                        if let delay = value("--revoke-after").flatMap(Double.init) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { adapter.revoke() }
                        }
                        while !done { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
                    } catch { outcomes.append("rejected") }
                    if index == 0 || index == count-1 { fdCounts.append(fds()) }
                  }
                }
            }
            let snapshot: [String:Any] = ["outcomes":outcomes,"callbacks":callbacks,"ticks":ticks,"maxMainGap":maxGap,
                "seconds":ProcessInfo.processInfo.systemUptime-start,"pending":try store.records().count,
                "consent":store.consent,"fds":fdCounts,"cacheExists":FileManager.default.fileExists(atPath:store.cache.path)]
            print(String(decoding:try JSONSerialization.data(withJSONObject:snapshot,options:.sortedKeys),as:UTF8.self))
        } catch { print("{\"probe\":\"failed\"}"); exit(2) }
    }
}

#endif
