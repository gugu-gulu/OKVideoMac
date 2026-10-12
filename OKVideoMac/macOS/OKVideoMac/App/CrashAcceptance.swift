#if OKVIDEO_CRASH_ACCEPTANCE
import Darwin
import Foundation
import OKCrashDiagnostics

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

    static func uploadConfiguration() -> CrashUploadConfiguration? {
        guard authorizedWorkspace, let dsn = value("--diagnostic-test-dsn"),
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
