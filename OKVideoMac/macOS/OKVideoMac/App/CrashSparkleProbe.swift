#if OKVIDEO_CRASH_ACCEPTANCE
import AppKit
import Foundation

@MainActor
enum CrashSparkleProbe {
    private static var started = false
    private static let driver = CrashSparkleDriver()
    static func runIfRequested(_ state: AppState) async {
        guard !started, CrashAcceptance.authorizedWorkspace,
              Bundle.main.object(forInfoDictionaryKey: "OKCrashSparkleFixture") as? Bool == true else { return }
        started = true
        do {
            if CrashSparkleLog.version == "2" {
                let history = try await state.crashAcceptanceHistory()
                CrashAcceptance.trace("updated-history", ["historyCount": history.count, "savedPosition": history.first?.position ?? 0])
                MainRunLoopAppTerminationRequestScheduler().schedule { NSApp.terminate(nil) }
                return
            }
            try await state.crashAcceptancePreparePlayback()
            driver.beforeInstall = { AppRestartGate.shared.claim(.update) }
            driver.didCancelOrFail = { AppRestartGate.shared.release(.update) }
            driver.start()
        } catch { CrashAcceptance.trace("fixture-failed", ["error": String(describing: error)]) }
    }
}
#endif
