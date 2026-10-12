import Foundation
import OKCrashDiagnostics

@MainActor
final class AppLaunchSession {
    static var current: AppLaunchSession?
    let startup: Result<AppStartupContext, Error>
    let crashManager: OKCrashManager?
    weak var controller: AppStartupController?

    init(startup: Result<AppStartupContext, Error>, crashManager: OKCrashManager?) {
        self.startup = startup
        self.crashManager = crashManager
    }

    static func prepare() -> AppLaunchSession {
        do {
            let context = try AppStartupContext.prepare()
            var manager: OKCrashManager?
            // Hosted unit tests must not install a process-wide fatal handler.
            if !AppEnvironment.isXCTestHost(environment: ProcessInfo.processInfo.environment) {
                let bundle = Bundle.main
                let map = bundle.url(forResource: "CrashImageVMAddresses", withExtension: "json")
                    .flatMap { try? Data(contentsOf: $0) }
                    .flatMap { try? JSONDecoder().decode([String: UInt64].self, from: $0) }
                var metadata = RunMetadata(
                    version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                    build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
                    imageVMAddresses: map
                )
#if OKVIDEO_CRASH_ACCEPTANCE
                metadata = CrashAcceptance.metadata(metadata)
#endif
                manager = try? OKCrashManager(
                    root: context.directories.diagnostics.appendingPathComponent("CrashReports"),
                    metadata: metadata
                )
            }
            return AppLaunchSession(startup: .success(context), crashManager: manager)
        } catch {
            return AppLaunchSession(startup: .failure(error), crashManager: nil)
        }
    }

    func bootstrapBusiness() -> AppState {
        switch startup {
        case .success(let context): return AppState.bootstrap(startupContext: context)
        case .failure(let error): return AppState.initializationFailure(error)
        }
    }
}
