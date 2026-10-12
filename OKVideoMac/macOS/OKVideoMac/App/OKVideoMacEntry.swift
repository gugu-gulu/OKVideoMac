import Darwin
import Foundation
import OKCrashDiagnostics

@main
enum OKVideoMacEntry {
    @MainActor
    static func main() {
        // Reserved internal worker dispatch must precede all application setup.
        if CommandLine.arguments.dropFirst().first == "--diagnostics-upload-worker" {
#if OKVIDEO_CRASH_ACCEPTANCE
            let fault = CommandLine.arguments.count == 3
                ? UploadWorkerFault(rawValue: CommandLine.arguments[2]) ?? .none : .none
            SentryUploadWorker.main(faultForTests: fault)
#else
            SentryUploadWorker.main()
#endif
        }
        let session = AppLaunchSession.prepare()
        AppLaunchSession.current = session
#if OKVIDEO_CRASH_ACCEPTANCE
        if CrashAcceptance.runEntryIfRequested(session: session) { return }
#endif
        OKVideoMacApp.main()
        withExtendedLifetime(session) {}
    }
}
