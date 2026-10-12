import Combine
import Foundation
import OKCrashDiagnostics

struct CrashUploadConfiguration {
    let dsn: String
    var allowLoopback = false
    var fault: UploadWorkerFault = .none

    @MainActor static func current() -> CrashUploadConfiguration? {
#if OKVIDEO_CRASH_ACCEPTANCE
        if let configuration = CrashAcceptance.uploadConfiguration() { return configuration }
#endif
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "OKCrashReportDSN") as? String,
              !dsn.isEmpty, (try? SentryAdapter.validateDSN(dsn, allowLoopback: false)) != nil else { return nil }
        return CrashUploadConfiguration(dsn: dsn)
    }
}

@MainActor
protocol CrashReportSending: AnyObject {
    var active: Bool { get }
    func send(_ record: CrashRecord, dsn: String, allowLoopback: Bool,
              contaminateScopeForTest: Bool, completion: @escaping (SentryAdapter.Outcome) -> Void) throws
    func revoke(completion: @escaping (Error?) -> Void)
    func cancel(completion: @escaping () -> Void)
}
extension SentryAdapter: CrashReportSending {}

/// Shared by recovery and settings. Consent persistence always precedes transport.
@MainActor
final class CrashUploadController: ObservableObject {
    enum Status: Equatable { case localOnly, enabled, unavailable, unconfigured, sending, delivered, pending, revoking, revoked, storageFailed }
    let store: ReportStore?
    let configuration: CrashUploadConfiguration?
    private let adapter: CrashReportSending?
    @Published private(set) var consent: Bool
    @Published private(set) var pendingReports: Int
    @Published private(set) var status: Status
    @Published private(set) var sending = false
    @Published private(set) var revoking = false
    private var grantAfterRevocation = false
    private var started = false
    private(set) var stopping = false
    private var stopped = false
    private var stopCallbacks: [() -> Void] = []
    var captureAvailable: Bool { store != nil }
    var canRetry: Bool { consent && configuration != nil && pendingReports > 0 && !sending && !revoking && !stopping }

    init(store: ReportStore?, configuration: CrashUploadConfiguration?, adapter: CrashReportSending? = nil) {
        self.store = store
        self.configuration = configuration
        self.adapter = adapter ?? store.map { SentryAdapter(store: $0, faultForTests: configuration?.fault ?? .none) }
        let initialConsent = store?.consent ?? false
        consent = initialConsent
        pendingReports = (try? store?.records().count) ?? 0
        status = store == nil ? .unavailable : configuration == nil && initialConsent ? .unconfigured : .localOnly
    }

    func start() {
        guard !started, !stopping else { return }
        started = true
        if consent { retry() }
    }

    func setConsent(_ enabled: Bool) {
        guard !stopping, let store, let adapter else { return }
        if revoking { grantAfterRevocation = enabled; return }
        if !enabled {
            consent = false
            revoking = true
            grantAfterRevocation = false
            status = .revoking
            adapter.revoke { [weak self] error in
                guard let self else { return }
                self.revoking = false
                self.sending = false
                self.pendingReports = (try? store.records().count) ?? self.pendingReports
                self.status = error == nil ? .revoked : .storageFailed
                let grant = self.grantAfterRevocation
                self.grantAfterRevocation = false
                if grant, error == nil, !self.stopping { self.setConsent(true) }
            }
            return
        }
        do {
            try store.setConsent(true)
            consent = true
            status = .localOnly
            retry()
        } catch {
            consent = store.consent
            status = .storageFailed
        }
    }

    func retry() {
        guard !stopping, !sending, !revoking, consent, let store, let adapter else { return }
        guard let configuration else { status = .unconfigured; return }
        do {
            pendingReports = try store.records().count
            guard let record = try store.records().first else { if status != .delivered { status = .enabled }; return }
            sending = true
            status = .sending
            try adapter.send(record, dsn: configuration.dsn, allowLoopback: configuration.allowLoopback,
                             contaminateScopeForTest: false) { [weak self] outcome in
                guard let self, !self.revoking, self.consent || self.stopping else { return }
                self.sending = false
                self.pendingReports = (try? store.records().count) ?? self.pendingReports
                self.status = outcome.result == "http-accepted" ? .delivered : .pending
                if outcome.result == "http-accepted", !self.stopping { self.retry() }
            }
        } catch {
            sending = false
            status = .pending
        }
    }

    func requestStop() {
        guard !stopping else { return }
        stopping = true
        grantAfterRevocation = false
        guard let adapter else { finishStop(); return }
        adapter.cancel { [self] in finishStop() }
    }

    func shutdown() async {
        requestStop()
        if stopped { return }
        await withCheckedContinuation { continuation in stopCallbacks.append { continuation.resume() } }
    }

    private func finishStop() {
        sending = false
        stopped = true
        let callbacks = stopCallbacks
        stopCallbacks.removeAll()
        callbacks.forEach { $0() }
    }
}
