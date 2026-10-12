#if OKVIDEO_CRASH_ACCEPTANCE
import AppKit
import Foundation
import Sparkle

// Test-only driver: supplies scripted user choices while using the unmodified
// Sparkle download, signature verification, installer and relaunch machinery.
@MainActor
enum CrashSparkleLog {
    static var root: URL {
        guard let workspace = try? AppEnvironment.acceptanceWorkspace() else {
            fatalError("The Sparkle fixture requires an isolated acceptance workspace")
        }
        return workspace.root
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String }
    static var scenario: String { Bundle.main.object(forInfoDictionaryKey: "OKUpdateProbeScenario") as? String ?? "normal" }
    static func record(_ event: String, _ fields: [String: Any] = [:]) {
        var row = fields
        row["event"] = event
        row["pid"] = ProcessInfo.processInfo.processIdentifier
        row["version"] = version
        row["uptime"] = ProcessInfo.processInfo.systemUptime
        let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data([10])
        let fd = open(root.appendingPathComponent("events.jsonl").path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        precondition(fd >= 0)
        data.withUnsafeBytes { bytes in precondition(write(fd, bytes.baseAddress, bytes.count) == bytes.count) }
        fsync(fd)
        close(fd)
    }
}

@MainActor
final class CrashSparkleDriver: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    var updater: SPUUpdater!
    var beforeInstall: (() -> Bool)?
    var didCancelOrFail: (() -> Void)?
    func start() {
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try updater.start()
            CrashSparkleLog.record("updater_started")
            updater.checkForUpdates()
        } catch { CrashSparkleLog.record("updater_start_failed", ["error": String(describing: error)]) }
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        CrashSparkleLog.record("permission_request")
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, automaticUpdateDownloading: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { CrashSparkleLog.record("check_started") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        CrashSparkleLog.record("update_found", ["target": appcastItem.versionString])
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { CrashSparkleLog.record("release_notes_received") }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { CrashSparkleLog.record("release_notes_failed", ["error": String(describing: error)]) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        CrashSparkleLog.record("update_not_found", ["error": String(describing: error)])
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        CrashSparkleLog.record("update_error", ["error": String(describing: error)])
        didCancelOrFail?()
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        CrashSparkleLog.record("download_started")
        if CrashSparkleLog.scenario == "cancel-download" {
            cancellation()
            didCancelOrFail?()
            CrashSparkleLog.record("download_cancelled")
        }
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { CrashSparkleLog.record("extracting") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        CrashSparkleLog.record("ready_to_install")
        if CrashSparkleLog.scenario == "cancel-install" || beforeInstall?() == false {
            reply(.skip) // Dismiss can still install on quit. Skip cancels this staged installation.
            didCancelOrFail?()
            CrashSparkleLog.record("install_cancelled")
        } else {
            CrashSparkleLog.record("install_confirmed")
            reply(.install)
        }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        CrashSparkleLog.record("installing", ["applicationTerminated": applicationTerminated])
        if CrashSparkleLog.scenario == "cancel-termination-once", !applicationTerminated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                CrashSparkleLog.record("retry_termination")
                retryTerminatingApplication()
            }
        }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        CrashSparkleLog.record("installed", ["relaunched": relaunched]); acknowledgement()
    }
    func dismissUpdateInstallation() { CrashSparkleLog.record("dismissed") }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        AppUpdateCoordinator.shared.updater(updater, willInstallUpdate: item)
        AppLaunchSession.current?.diagnostics.retry()
        CrashAcceptance.trace("install-upload-active", ["sending": AppLaunchSession.current?.diagnostics.sending ?? false])
        CrashSparkleLog.record("will_install")
    }
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { CrashSparkleLog.record("will_relaunch") }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        CrashSparkleLog.record("update_aborted", ["error": String(describing: error)])
        didCancelOrFail?()
    }
}

#endif
