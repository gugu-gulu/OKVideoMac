import SwiftUI
import AppKit
import CrashVisibilityCore

/// One SwiftUI application and window for both phases. The reporter and lease already exist;
/// creating this UI shell does not create the mock database/player or run business bootstrap.
@MainActor final class RecoveryShellState: ObservableObject {
    let context: StartupRehearsal
    var recovery: RecoveryCoordinator!
    @Published private(set) var business: RehearsalState?
    private var started = false
    init(context: StartupRehearsal) {
        self.context=context
        context.trace("shell-state-created-without-business")
        recovery=RecoveryCoordinator(store:context.manager?.store,
            dsn:context.value("--test-dsn") ?? (try? PrivateConfiguration.dsn(at:context.value("--config"))),
            newlyRecovered:context.manager?.recovered ?? false,
            allowLoopbackForTests:context.value("--test-dsn") != nil,
            startup:{ [weak self] in self?.startBusiness() })
        context.trace(recovery.waitingForDecision ? "shell-recovery-required" : "shell-recovery-not-required")
    }
    private func startBusiness() {
        guard !started else { return };started=true
        context.trace("shell-business-start")
        business=RehearsalState.bootstrap()
        context.trace("shell-business-ready")
    }
    func continueStartup() {
        context.trace("shell-continue-action")
        recovery.continueStartup()
    }
    /// Model-level injection for automated ordering checks; explicitly not a UI interaction.
    func testDecision() {
        guard let action=context.value("--shell-test-action") else { return }
        context.trace("shell-model-decision-injected:"+action)
        if action == "continue" || action == "continue-twice" {
            continueStartup()
            if action == "continue-twice" { continueStartup() }
        }
        if action == "revoke-continue" { recovery.setConsent(false);continueStartup() }
    }
}

struct RecoveryShellApp: App {
    @NSApplicationDelegateAdaptor(RehearsalAppDelegate.self) private var appDelegate
    @StateObject private var shell: RecoveryShellState
    init() {
        let context=StartupRehearsal.current!
        context.trace("app-init-enter");context.fault("app-init")
        _shell=StateObject(wrappedValue:RecoveryShellState(context:context))
        context.trace("app-init-return")
    }
    var body:some Scene {
        WindowGroup("Crash Recovery Shell") {
            RecoveryShellView(shell:shell,recovery:shell.recovery)
        }.commands { CommandGroup(replacing:.newItem) {} }
    }
}
private struct RecoveryShellView: View {
    @ObservedObject var shell: RecoveryShellState
    @ObservedObject var recovery: RecoveryCoordinator
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text(recovery.waitingForDecision ? recovery.recoveryTitle : "已进入原型测试界面").font(.title2).bold()
            Text("独立原型 · 同一个 SwiftUI 窗口 · 不读取正式 App 数据").foregroundColor(.secondary)
            if recovery.waitingForDecision {
                Text(recovery.recoveryExplanation)
                Text("模拟业务尚未初始化。保持关闭也可以继续。")
            } else {
                Text("模拟业务已初始化一次。恢复提示已在同一个窗口内切换，没有创建第二个主窗口。")
            }
            Toggle("自动发送崩溃报告，帮助改进 OKVideoMac",isOn:Binding(get:{ recovery.consent },set:{
                shell.context.trace($0 ? "shell-consent-on" : "shell-consent-off")
                recovery.setConsent($0)
            })).disabled(!recovery.captureAvailable || recovery.revoking)
            Text("只发送版本、系统与架构、线程调用地址、模块 UUID 和错误代码。不发送播放内容、配置、日志或原始报告。")
                .font(.callout).foregroundColor(.secondary)
            Text(recovery.status)
            Text("本地待处理：\(recovery.pendingCount)")
            HStack {
                Button("退出原型") { NSApplication.shared.terminate(nil) }
                if recovery.waitingForDecision {
                    Button("继续打开原型") { shell.continueStartup() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("制造测试崩溃") { PrototypeEntry.swiftCrashFixture() }
                    Button("重试发送") { recovery.sendPending() }.disabled(!recovery.consent || recovery.sending || recovery.revoking)
                }
            }
        }.padding(28).frame(width:640,height:440,alignment:.topLeading)
        .task {
            shell.context.trace("shell-ui-ready")
            shell.testDecision()
            if shell.context.value("--shell-test-action") != nil {
                shell.context.trace("normal-exit");NSApplication.shared.terminate(nil)
            }
        }
    }
}
