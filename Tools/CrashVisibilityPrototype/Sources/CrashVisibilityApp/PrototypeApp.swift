import SwiftUI
import AppKit
import CrashVisibilityCore

struct PrototypeApp: App {
    @MainActor static var model: RecoveryCoordinator!
    @ObservedObject private var model = PrototypeApp.model!
    var body: some Scene {
        WindowGroup("Crash Visibility Prototype") {
            VStack(alignment: .leading, spacing: 18) {
                Text(model.waitingForDecision ? model.recoveryTitle : "Crash Visibility Prototype").font(.title2).bold()
                Text("独立原型 · 与 OKVideoMac 正式 App 的数据和播放器隔离").foregroundColor(.secondary)
                if model.waitingForDecision {
                    Text(model.recoveryExplanation)
                }
                Toggle("自动发送崩溃报告，帮助改进 OKVideoMac", isOn: Binding(get: { model.consent }, set: { model.setConsent($0) }))
                    .disabled(!model.captureAvailable || model.revoking)
                Text("只发送版本、系统与架构、线程调用地址、模块 UUID 和错误代码。不会发送播放内容、配置、日志或原始报告。")
                    .font(.callout).foregroundColor(.secondary)
                Text(model.status).font(.callout)
                Text("本地待处理：\(model.pendingCount)")
                if model.waitingForDecision {
                    Button("继续打开原型") { model.continueStartup() }.keyboardShortcut(.defaultAction)
                } else {
                    HStack {
                        Button("测试 Swift 崩溃") { PrototypeEntry.swiftCrashFixture() }
                        Button("测试 C 崩溃") { PrototypeEntry.cCrashFixture(path: nil) }
                        Button("重试发送") { model.sendPending() }.disabled(!model.consent || model.sending || model.pendingCount == 0)
                    }
                    Text("测试按钮只会使这个原型退出；重新打开即可检查恢复提示。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }.padding(28).frame(width: 600).fixedSize(horizontal: true, vertical: true)
        }
    }
}
