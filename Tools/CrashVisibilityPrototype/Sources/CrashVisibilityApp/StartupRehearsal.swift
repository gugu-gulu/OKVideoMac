import AppKit
import SwiftUI
import CrashVisibilityCore

/// Isolated startup experiment: no production AppState, database, player, SDK or user data.
@MainActor final class StartupRehearsal {
    static var current: StartupRehearsal!
    let root: URL
    let args: [String]
    let lease: ApplicationInstanceLease
    var manager: OKCrashManager?
    private let traceURL: URL
    private init(root: URL, args: [String], lease: ApplicationInstanceLease, traceURL: URL) {
        self.root = root; self.args = args; self.lease = lease; self.traceURL = traceURL
    }
    func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i+1 < args.count else { return nil }; return args[i+1]
    }
    func trace(_ event: String) {
        guard let file = try? FileHandle(forWritingTo: traceURL) else { exit(4) }
        defer { try? file.close() }; _ = try? file.seekToEnd()
        try? file.write(contentsOf: Data((event + "\n").utf8)); try? file.synchronize()
    }
    func fault(_ point: String) {
        if value("--fault") == point { trace("fault:"+point); fatalError("Synthetic startup rehearsal failure") }
    }
    static func run(root: URL, args: [String], metadata: RunMetadata) {
        let traceURL = root.appendingPathComponent("startup-\(getpid()).trace")
        do {
            try ReportStore.privateDirectory(root)
            try Data("entry\n".utf8).write(to: traceURL)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:traceURL.path)
            let lease: ApplicationInstanceLease
            do { lease = try ApplicationInstanceLease(lockURL: root.appendingPathComponent(".instance.lock")) }
            catch {
                let file = try FileHandle(forWritingTo: traceURL); try file.seekToEnd()
                try file.write(contentsOf:Data("lease-rejected\n".utf8)); try file.close(); exit(3)
            }
            let context = StartupRehearsal(root:root,args:args,lease:lease,traceURL:traceURL)
            current = context; context.trace("lease-acquired")
            do {
                context.manager = try OKCrashManager(root:root.appendingPathComponent("crash"),metadata:metadata)
                context.trace("capture-installed")
            } catch { context.trace("capture-unavailable") }
            if !args.contains("--recovery-shell-ui"), let store = context.manager?.store, (try? store.needsRecoveryPrompt()) == true {
                context.trace("recovery-gate-required")
                // Inject a decision for ordering tests. This is not a UI click or modal-window test.
                if context.value("--gate") != "continue" {
                    if context.value("--gate") == "hold" {
                        context.trace("recovery-gate-held")
                        let deadline = Date().addingTimeInterval(12)
                        while !FileManager.default.fileExists(atPath:root.appendingPathComponent("continue.signal").path), Date() < deadline {
                            RunLoop.current.run(until:Date().addingTimeInterval(0.02))
                        }
                        guard Date() < deadline else { context.trace("gate-timeout"); return }
                    } else { context.trace("recovery-gate-deferred"); return }
                }
                context.trace("recovery-decision-injected")
                do { try store.acknowledgeRecoveryPrompt() }
                catch { context.trace("recovery-ack-unavailable") }
            }
            context.fault("before-app-main")
            context.trace("swiftui-main-enter")
            if args.contains("--recovery-shell-ui") {
                NSApplication.shared.setActivationPolicy(.regular)
                RecoveryShellApp.main()
            } else {
                NSApplication.shared.setActivationPolicy(.accessory)
                StartupRehearsalApp.main()
            }
            withExtendedLifetime(context) {}
        } catch { exit(4) }
    }
}

@MainActor final class RehearsalState: ObservableObject {
    let lease: ApplicationInstanceLease
    let label = "独立启动顺序演练（无正式数据）"
    init(lease:ApplicationInstanceLease) { self.lease=lease; StartupRehearsal.current.trace("state-created") }
    static func bootstrap() -> RehearsalState {
        let c=StartupRehearsal.current!
        c.trace("bootstrap-enter"); c.fault("bootstrap-before")
        // Carry the preflight lease into the mock environment instead of acquiring it twice.
        let state=RehearsalState(lease:c.lease)
        guard state.lease === c.lease else { fatalError("lease identity changed") }
        c.trace("same-lease-transferred")
        c.trace("mock-database-open")
        c.trace("mock-player-created")
        c.fault("bootstrap-after"); c.trace("bootstrap-return")
        return state
    }
}
@MainActor final class RehearsalAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification:Notification) { StartupRehearsal.current.trace("delegate-will-finish-launching") }
    func applicationDidFinishLaunching(_ notification:Notification) { StartupRehearsal.current.trace("delegate-did-finish-launching") }
    func applicationWillTerminate(_ notification:Notification) { StartupRehearsal.current.trace("delegate-will-terminate") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
    override init() {
        super.init()
        StartupRehearsal.current.trace("delegate-init")
        StartupRehearsal.current.fault("delegate-init")
    }
}
private struct StartupRehearsalApp: App {
    @NSApplicationDelegateAdaptor(RehearsalAppDelegate.self) private var appDelegate
    @StateObject private var state:RehearsalState
    init() {
        let c=StartupRehearsal.current!
        c.trace("app-init-enter"); c.fault("app-init")
        _state=StateObject(wrappedValue:RehearsalState.bootstrap())
        c.trace("app-init-return")
    }
    var body:some Scene {
        WindowGroup("Crash Startup Rehearsal") {
            Text(state.label).padding().task {
                let c=StartupRehearsal.current!
                c.trace("swiftui-task")
                c.trace("normal-exit")
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
