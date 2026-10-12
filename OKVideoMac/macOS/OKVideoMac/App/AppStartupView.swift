import AppKit
import SwiftUI

struct AppStartupView: View {
    @ObservedObject var startup: AppStartupController
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if startup.phase == .failed {
                Text(L10n.string("app.initialization.failed", fallback: "Unable to Initialize App"))
                    .font(.title2).bold()
                Text(startup.failureMessage ?? "")
                Button(L10n.string("crash.recovery.quit", fallback: "Quit")) { NSApp.terminate(nil) }
            } else if startup.phase == .recovery {
                Text(L10n.string("crash.recovery.title", fallback: "OKVideoMac closed unexpectedly"))
                    .font(.title2).bold()
                Text(L10n.string("crash.recovery.local", fallback: "A filtered crash report is saved on this Mac for up to 7 days, with at most 3 reports kept. You can continue opening the app."))
                CrashDiagnosticsControls(diagnostics: startup.diagnostics)
                HStack {
                    Button(L10n.string("crash.recovery.quit", fallback: "Quit")) { NSApp.terminate(nil) }
                    Button(L10n.string("crash.recovery.continue", fallback: "Continue Opening")) { startup.continueStartup() }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("crash-recovery-continue")
                }
            } else {
                ProgressView()
                Text(L10n.string("crash.recovery.opening", fallback: "Opening OKVideoMac…"))
            }
        }
        .padding(28).frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { startup.beginIfReady() }
    }
}
