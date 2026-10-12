import SwiftUI

struct CrashDiagnosticsControls: View {
    @ObservedObject var diagnostics: CrashUploadController
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(L10n.string("crash.recovery.consent", fallback: "Send crash reports to help improve OKVideoMac"),
                   isOn: Binding(get: { diagnostics.consent }, set: { diagnostics.setConsent($0) }))
                .disabled(!diagnostics.captureAvailable || diagnostics.stopping)
                .accessibilityIdentifier("crash-upload-consent")
            Text(statusText).font(.callout).foregroundColor(.secondary)
                .accessibilityIdentifier("crash-upload-status")
            Text(L10n.string("crash.recovery.privacy", fallback: "Reports contain the app version, system, architecture, error codes and thread addresses. They exclude playback content, configuration, credentials, logs and raw reports."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.string("crash.upload.withdrawal", fallback: "Turning this off stops uploads and clears pending reports and upload caches. Reports already sent cannot be withdrawn from this Mac."))
                .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if diagnostics.canRetry {
                Button(L10n.string("crash.upload.retry", fallback: "Retry Sending")) { diagnostics.retry() }
                    .accessibilityIdentifier("crash-upload-retry")
            }
        }
    }

    private var statusText: String {
        switch diagnostics.status {
        case .localOnly:
            return L10n.string("crash.upload.local", fallback: "%d filtered reports saved on this Mac; uploads are off.", diagnostics.pendingReports)
        case .enabled: return L10n.string("crash.upload.enabled", fallback: "Uploads are on. There are no pending reports.")
        case .unavailable: return L10n.string("crash.upload.unavailable", fallback: "Local crash capture is unavailable. You can still use the app.")
        case .unconfigured: return L10n.string("crash.upload.unconfigured", fallback: "Uploading is not configured in this build. Reports stay on this Mac.")
        case .sending: return L10n.string("crash.upload.sending", fallback: "Sending a filtered report. You can continue using the app.")
        case .delivered: return L10n.string("crash.upload.delivered", fallback: "The receiving service confirmed delivery.")
        case .pending: return L10n.string("crash.upload.pending", fallback: "Delivery was not confirmed. The report stays on this Mac for a later retry.")
        case .revoking: return L10n.string("crash.upload.revoking", fallback: "Uploads are off. Stopping the upload and clearing pending reports…")
        case .revoked: return L10n.string("crash.upload.revoked", fallback: "Uploads are off. Pending reports and upload caches have been cleared.")
        case .storageFailed: return L10n.string("crash.upload.storage-failed", fallback: "The diagnostic preference or cleanup could not be saved completely.")
        }
    }
}
