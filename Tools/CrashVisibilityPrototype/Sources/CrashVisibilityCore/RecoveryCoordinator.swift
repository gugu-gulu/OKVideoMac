import Foundation
import Combine

@MainActor public final class RecoveryCoordinator: ObservableObject {
    public var captureAvailable: Bool { store != nil }
    let store: ReportStore?
    private let startup: () -> Void
    let adapter: SentryAdapter?
    let dsn: String?
    private let allowLoopbackForTests: Bool
    private let newlyRecovered: Bool
    @Published public private(set) var consent: Bool
    @Published public private(set) var waitingForDecision: Bool
    @Published public private(set) var status: String
    @Published public private(set) var sending = false
    @Published public private(set) var revoking = false
    private var grantAfterRevocation = false
    @Published public private(set) var pendingCount: Int

    public init(store: ReportStore?, dsn: String?, newlyRecovered: Bool = false, allowLoopbackForTests: Bool = false, faultForTests: UploadWorkerFault = .none, startup: @escaping () -> Void) {
        self.store = store; self.dsn = dsn; self.startup = startup
        self.newlyRecovered = newlyRecovered; self.allowLoopbackForTests = allowLoopbackForTests
        adapter = store.map { SentryAdapter(store: $0, faultForTests: faultForTests) }
        consent = store?.consent ?? false
        let count = (try? store?.records().count) ?? 0
        pendingCount = count
        waitingForDecision = (try? store?.needsRecoveryPrompt()) ?? false
        status = store == nil ? "本地捕获不可用；原型仍可继续启动。" : "本地捕获已安装。"
        if !waitingForDecision { startup() }
        if consent { sendPending() }
    }
    public var recoveryTitle: String {
        newlyRecovered ? "检测到上次运行留下的崩溃报告" : "检测到之前保留的崩溃报告"
    }
    public var recoveryExplanation: String {
        if pendingCount == 0 { return "本地已无待处理报告。发送或清理结果见下方状态；可以继续启动。" }
        if sending { return "正在按你已开启的授权发送过滤后的崩溃报告；你仍可关闭授权或继续启动。" }
        if consent && dsn != nil { return "尚未确认送达的报告保留在本机，最多 3 份、7 天；可以稍后重试或关闭授权。" }
        return "报告仅保存在本机，最多保留 3 份、7 天。开启后会发送待处理报告；也可以保持关闭并继续启动。"
    }
    public func setConsent(_ enabled: Bool) {
        guard let store, let adapter else { return }
        if revoking { grantAfterRevocation = enabled; return }
        if !enabled {
            consent = false; revoking = true; grantAfterRevocation = false
            status = "授权已关闭，正在停止发送并清理本地队列。"
            adapter.revoke { [weak self] error in
                guard let self else { return }
                self.revoking = false; self.sending = false
                self.pendingCount = (try? store.records().count) ?? self.pendingCount
                self.status = error == nil ? "授权已关闭，待发报告与发送缓存已清除。" : "无法完整保存或清理诊断设置；请勿将本次操作视为已完成。"
                let grant = self.grantAfterRevocation; self.grantAfterRevocation = false
                if grant && error == nil { self.setConsent(true) }
            }
            return
        }
        do {
            try store.setConsent(true); consent = true
            status = "授权已开启；当前无待发报告。"
            sendPending()
        }
        catch {
            consent = store.consent
            status = "无法保存诊断授权；本次未开始发送。"
        }
    }
    public func continueStartup() {
        guard waitingForDecision else { return }
        do { try store?.acknowledgeRecoveryPrompt() }
        catch { status = "无法保存提示确认状态；本次仍继续启动。" }
        waitingForDecision = false
        startup()
    }
    public func sendPending() {
        guard !sending, !revoking, consent, let store, let adapter else { return }
        guard let dsn else { status = "未配置 Sentry：报告只保存在本机，不会上传。"; return }
        do {
            guard let record = try store.records().first else { return }
            sending = true
            try adapter.send(record, dsn: dsn, allowLoopback: allowLoopbackForTests) { [weak self] outcome in
                guard let self else { return }
                guard !self.revoking else { return }
                self.sending = false
                self.pendingCount = (try? store.records().count) ?? 0
                self.status = outcome.result == "http-accepted" ? "接收端已确认收到；后台符号化需另行验证。" : "本次未确认送达，报告保留待重试。"
                if outcome.result == "http-accepted" { self.sendPending() }
            }
        } catch { sending = false; status = "发送配置不可用；报告仍保存在本机。" }
    }
}
