import Foundation
import CrashVisibilityCore
import Darwin
import AppKit

@main enum PrototypeEntry {
    @MainActor static func main() {
        umask(0o077)
        let args = CommandLine.arguments
        if args.count >= 2, args[1] == "--upload-worker" {
            SentryUploadWorker.main(faultForTests: args.count == 3 ? UploadWorkerFault(rawValue: args[2]) ?? .none : .none)
        }
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }; return args[i + 1]
        }
        let root = URL(fileURLWithPath: value("--state-root") ?? NSHomeDirectory() + "/Library/Application Support/com.okvideomac.CrashVisibilityPrototype")
        let imageMap = Bundle.main.url(forResource: "ImageVMAddresses", withExtension: "json").flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: UInt64].self, from: $0) }
        let metadata = RunMetadata(version: value("--test-version") ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"), build: value("--test-build") ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"), imageVMAddresses: imageMap)
        if args.contains("--startup-rehearsal") { StartupRehearsal.run(root: root, args: args, metadata: metadata); return }
        var manager: OKCrashManager?
        do { manager = try OKCrashManager(root: root, metadata: metadata) }
        catch {
            if args.count > 1 && !args.contains("--ui") { mockBootstrap(); print("{\"capture\":\"unavailable\",\"businessBootstrap\":\"continued\"}"); return }
        }
        if args.count == 1 || args.contains("--ui") {
            PrototypeApp.model = RecoveryCoordinator(store: manager?.store, dsn: try? PrivateConfiguration.dsn(at: value("--config")), newlyRecovered: manager?.recovered ?? false, startup: mockBootstrap)
            NSApplication.shared.setActivationPolicy(.regular)
            PrototypeApp.main()
            return
        }
        guard let manager else { return }
        if args.contains("--worker-probe") { UploadProbe.run(store: manager.store, args: args); return }
        if args.contains("--recovery-probe") {
            var starts = 0
            let model = RecoveryCoordinator(store: manager.store,
                dsn: value("--test-dsn") ?? (try? PrivateConfiguration.dsn(at: value("--config"))),
                newlyRecovered: manager.recovered, allowLoopbackForTests: value("--test-dsn") != nil,
                startup: { starts += 1; mockBootstrap() })
            if args.contains("--grant") { model.setConsent(true) }
            if args.contains("--revoke") { model.setConsent(false) }
            if args.contains("--continue-recovery") { model.continueStartup(); model.continueStartup() }
            if args.contains("--send") { model.sendPending() }
            if let delay = value("--revoke-after").flatMap(Double.init) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { model.setConsent(false) }
            }
            while model.sending || model.revoking { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
            if let count = value("--retry-count").flatMap(Int.init), (1...30).contains(count) {
                for _ in 0..<count {
                    model.sendPending()
                    while model.sending || model.revoking { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
                }
            }
            let snapshot: [String: Any] = ["pending": model.pendingCount, "consent": model.consent,
                "waitingForDecision": model.waitingForDecision, "bootstrapCount": starts,
                "status": model.status, "explanation": model.recoveryExplanation,
                "recovered": manager.recovered]
            print(String(decoding: try! JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]), as: UTF8.self))
            return
        }
        if let crash = value("--crash") {
            if crash.hasSuffix("post") { mockBootstrap() }
            if crash.hasPrefix("swift") { swiftCrashFixture() }
            else { cCrashFixture(path: value("--fixture")) }
        }
        do {
            if args.contains("--grant") { try manager.store.setConsent(true) }
            let adapter = SentryAdapter(store: manager.store)
            if args.contains("--revoke") { adapter.revoke() }
            if args.contains("--export") {
                let data = try JSONEncoder().encode(manager.store.records()); print(String(decoding: data, as: UTF8.self)); return
            }
            if args.contains("--send"), manager.store.consent, let dsn = try (value("--test-dsn") ?? PrivateConfiguration.dsn(at: value("--config"))), let record = try manager.store.records().first {
                var done = false
                try adapter.send(record, dsn: dsn, allowLoopback: value("--test-dsn") != nil, contaminateScopeForTest: args.contains("--contaminate")) { result in
                    print(String(decoding: try! JSONEncoder().encode(result), as: UTF8.self)); fflush(stdout); done = true
                }
                if args.contains("--crash-while-sdk-active") { cCrashFixture(path: value("--fixture")) }
                if let delay = value("--revoke-after").flatMap(Double.init) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { adapter.revoke() }
                }
                while !done { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
                if args.contains("--crash-after-sdk-close") { cCrashFixture(path: value("--fixture")) }
            } else {
                let count = try manager.store.records().count
                print("{\"pending\":\(count),\"consent\":\(manager.store.consent),\"recovered\":\(manager.recovered),\"recoveryFailed\":\(manager.recoveryFailed),\"sdkStarted\":false}")
            }
        } catch { print("{\"diagnostics\":\"unavailable\"}"); exit(2) }
        withExtendedLifetime(manager) {}
    }
    @inline(never) static func cCrashFixture(path: String?) {
        let fixture = path ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libCVPCrashFixture.dylib").path
        guard let library = dlopen(fixture, RTLD_NOW), let symbol = dlsym(library, "cvp_crash_fixture") else { if let error = dlerror() { fputs(error, stderr) }; print("{\"fixture\":\"unavailable\"}"); return }
        unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)()
    }
    @inline(never) static func mockBootstrap() { print("mock-bootstrap-complete"); fflush(stdout) }
    @inline(never) static func swiftCrashFixture() { fatalError("DO_NOT_SEND synthetic Swift failure: private title https://example.invalid/?token=secret") }
}
