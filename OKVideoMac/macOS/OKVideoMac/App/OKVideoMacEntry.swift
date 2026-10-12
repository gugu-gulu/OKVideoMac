import Darwin
import Foundation

@main
enum OKVideoMacEntry {
    @MainActor
    static func main() {
        // Reserved internal worker dispatch must precede all application setup.
        if CommandLine.arguments.dropFirst().first == "--diagnostics-upload-worker" {
            exit(64) // Upload is introduced only after the local-capture gate passes.
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
