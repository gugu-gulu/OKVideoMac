#if OKVIDEO_CRASH_ACCEPTANCE
import Darwin
import Foundation
import OKCrashDiagnostics
import OKVideoCore

/// This entire test interface is absent from ordinary Release builds.
@MainActor
enum CrashAcceptance {
    static func value(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var authorizedWorkspace: Bool {
        Bundle.main.bundleIdentifier == "com.okvideomac.OKVideoMac.acceptance8b3b"
            && (try? AppEnvironment.acceptanceWorkspace()) != nil
    }

    static func establishFixtureEnvironmentIfRequested() {
        let probe: [String: Any] = ["bundleIdentifier": Bundle.main.bundleIdentifier ?? "nil",
            "bundlePath": Bundle.main.bundleURL.path,
            "fixtureRoot": Bundle.main.object(forInfoDictionaryKey: "OKCrashAcceptanceRoot") as? String ?? "nil",
            "inheritedRoot": ProcessInfo.processInfo.environment["OKVIDEOMAC_8B3B_ROOT"] ?? "nil",
            "launchIdentifier": ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "nil",
            "uid": getuid()]
        if let bytes = try? JSONSerialization.data(withJSONObject: probe, options: .sortedKeys) {
            let url = URL(fileURLWithPath: "/private/tmp/OKVideoMac-CrashIntegration/fixture-entry.json")
            try? bytes.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        guard Bundle.main.bundleIdentifier == "com.okvideomac.OKVideoMac.acceptance8b3b",
              let canonical = realpath(Bundle.main.bundleURL.path, nil) else { return }
        defer { free(canonical) }
        guard String(cString: canonical).hasPrefix("/private/tmp/OKVideoMac-CrashIntegration/"),
              let path = Bundle.main.object(forInfoDictionaryKey: "OKCrashAcceptanceRoot") as? String,
              (try? ImportedAcceptanceWorkspace(root: URL(fileURLWithPath: path))) != nil else { return }
        setenv("OKVIDEOMAC_8B3B_ROOT", path, 1)
    }

    static func trace(_ event: String, _ fields: [String: Any] = [:]) {
        guard authorizedWorkspace, let workspace = try? AppEnvironment.acceptanceWorkspace() else { return }
        var row = fields
        row["event"] = event; row["pid"] = getpid(); row["uptime"] = ProcessInfo.processInfo.systemUptime
        row["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: .sortedKeys) else { return }
        let descriptor = open(workspace.root.appendingPathComponent("crash-lifecycle.jsonl").path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard descriptor >= 0 else { return }
        var framed = data; framed.append(10)
        framed.withUnsafeBytes { bytes in _ = write(descriptor, bytes.baseAddress, bytes.count) }
        close(descriptor)
    }

    static func delayBootstrapIfRequested() async {
        guard authorizedWorkspace, let seconds = value("--diagnostic-delay-bootstrap").flatMap(Double.init), seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(min(15, seconds) * 1_000_000_000))
    }

    static func delayShutdownIfRequested() async {
        guard authorizedWorkspace else { return }
        let seconds = value("--diagnostic-delay-shutdown").flatMap(Double.init)
            ?? (Bundle.main.object(forInfoDictionaryKey: "OKCrashAcceptanceShutdownDelay") as? Double) ?? 0
        if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(min(15, seconds) * 1_000_000_000)) }
    }

    static func uploadConfiguration() -> CrashUploadConfiguration? {
        guard authorizedWorkspace, let dsn = value("--diagnostic-test-dsn")
                ?? Bundle.main.object(forInfoDictionaryKey: "OKCrashAcceptanceUploadDSN") as? String,
              (try? SentryAdapter.validateDSN(dsn, allowLoopback: true)) != nil else { return nil }
        return CrashUploadConfiguration(dsn: dsn, allowLoopback: true,
            fault: value("--diagnostic-worker-fault").flatMap(UploadWorkerFault.init(rawValue:)) ?? .none)
    }

    static func metadata(_ metadata: RunMetadata) -> RunMetadata {
        guard authorizedWorkspace else { return metadata }
        return RunMetadata(version: value("--diagnostic-test-version") ?? metadata.version,
            build: value("--diagnostic-test-build") ?? metadata.build,
            imageVMAddresses: metadata.imageVMAddresses)
    }

    @inline(never)
    static func faultIfRequested(_ stage: String) {
        guard value("--diagnostic-crash-stage") == stage else { return }
        guard authorizedWorkspace else { exit(64) }
        if value("--diagnostic-crash-kind") == "c" {
            let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libCrashAcceptanceFixture.dylib").path
            guard let library = dlopen(path, RTLD_NOW), let symbol = dlsym(library, "ok_crash_acceptance_fault") else { exit(65) }
            unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)()
        } else {
            fatalError("DO_NOT_SEND synthetic Swift failure https://example.invalid/?token=secret")
        }
    }

    static func nativeFaultIfRequested() {
        guard value("--diagnostic-crash-stage") == "native-thread", authorizedWorkspace else { return }
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks/libCrashAcceptanceFixture.dylib").path
        DispatchQueue.global(qos: .userInitiated).async {
            guard let library = dlopen(path, RTLD_NOW), let symbol = dlsym(library, "ok_crash_acceptance_fault") else { exit(65) }
            unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)()
        }
    }

    static func runEntryIfRequested(session: AppLaunchSession) -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--diagnostic-upload-probe") || args.contains("--diagnostic-upload-model") || args.contains("--diagnostic-export") || value("--diagnostic-crash-stage") == "entry" else { return false }
        guard authorizedWorkspace else { exit(64) }
        if args.contains("--diagnostic-upload-probe"), let store = session.crashManager?.store {
            CrashUploadProbe.run(store: store, args: args); return true
        }
        if args.contains("--diagnostic-upload-model") {
            CrashUploadProbe.runModel(session: session, args: args); return true
        }
        faultIfRequested("entry")
        if args.contains("--diagnostic-export") {
            let records = (try? session.crashManager?.store.records()) ?? []
            let recordData = (try? JSONEncoder().encode(records)) ?? Data("[]".utf8)
            let object: [String: Any] = [
                "captureAvailable": session.crashManager != nil,
                "recovered": session.crashManager?.recovered ?? false,
                "recoveryFailed": session.crashManager?.recoveryFailed ?? false,
                "consent": session.crashManager?.store.consent ?? false,
                "reports": (try? JSONSerialization.jsonObject(with: recordData)) ?? [],
                "businessInitialized": {
                    if case .success(let context) = session.startup { return context.hasStartedBusinessBootstrap }
                    return false
                }()
            ]
            let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return true
        }
        return false
    }
}
#endif
