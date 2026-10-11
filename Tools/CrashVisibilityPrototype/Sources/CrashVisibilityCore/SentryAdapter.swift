import Foundation
import Darwin
import HandlerProbe

/// Main-thread consent/queue owner. Pipe IO, deadlines and child reaping run in UploadProcess.
@MainActor public final class SentryAdapter {
    public struct Outcome: Codable, Sendable {
        public let result: String
        public let handlersUnchanged: Bool
        public let httpStatus: Int?
    }
    private let store: ReportStore
    private let fault: UploadWorkerFault
    private var worker: UploadProcess?
    private var completion: ((Outcome) -> Void)?
    private var revocation: ((Error?) -> Void)?
    private var revocationError: Error?
    private var handlersBefore: UnsafeMutableRawPointer?
    private var exceptionHandlerBefore: UInt = 0
    public var active: Bool { worker != nil }
    public init(store: ReportStore, faultForTests: UploadWorkerFault = .none) { self.store = store; fault = faultForTests }

    nonisolated static func validateDSN(_ dsn: String, allowLoopback: Bool) throws {
        guard let endpoint = URLComponents(string: dsn), endpoint.user?.isEmpty == false,
              endpoint.host?.isEmpty == false, endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              endpoint.path.split(separator: "/").last?.allSatisfy(\.isNumber) == true,
              endpoint.scheme == "https" || (allowLoopback && endpoint.scheme == "http" && endpoint.host == "127.0.0.1")
        else { throw PrototypeError.invalidConfiguration }
    }
    public func send(_ record: CrashRecord, dsn: String, allowLoopback: Bool = false,
                     contaminateScopeForTest: Bool = false, completion: @escaping (Outcome) -> Void) throws {
        guard !active, revocation == nil, store.consent, record.isValid else { throw PrototypeError.unavailable }
        try Self.validateDSN(dsn, allowLoopback: allowLoopback)
        let packet = try JSONEncoder().encode(SentryUploadWorker.Input(record: record, dsn: dsn,
            cachePath: store.cache.path, allowLoopback: allowLoopback, contaminateScopeForTest: contaminateScopeForTest))
        guard packet.count <= CrashMapper.maxRawBytes else { throw PrototypeError.invalidReport }
        try store.removeSDKCache(); try ReportStore.privateDirectory(store.cache)
        handlersBefore = cvp_handlers_snapshot(); exceptionHandlerBefore = Self.exceptionHandlerAddress()
        let attempt = UploadProcess(); worker = attempt; self.completion = completion
        attempt.start(executable: Bundle.main.executableURL, packet: packet, fault: fault) { [self] result in
            DispatchQueue.main.async { [self] in
                guard worker === attempt else { return }
                finish(result, record: record)
            }
        }
    }
    /// Consent closes immediately. Completion runs only after the child exits and cleanup completes.
    public func revoke(completion: @escaping (Error?) -> Void = { _ in }) {
        guard revocation == nil else { completion(PrototypeError.unavailable); return }
        do { try store.setConsent(false) } catch { revocationError = error }
        revocation = completion
        if let worker { worker.cancel() }
        else { finishRevocation() }
    }
    private func finishRevocation() {
        do { try store.discard(); try store.removeSDKCache() } catch { revocationError = revocationError ?? error }
        let callback = revocation, error = revocationError
        revocation = nil; revocationError = nil; callback?(error)
    }
    private func finish(_ result: UploadProcess.Result, record: CrashRecord) {
        // UploadProcess calls back after its defer has reaped the child and closed the pipes.
        let unchanged = handlersBefore == nil || (cvp_handlers_match(handlersBefore) && exceptionHandlerBefore == Self.exceptionHandlerAddress())
        cvp_handlers_free(handlersBefore); handlersBefore = nil
        let response = result.response
        var status = revocation == nil ? "pending" : "revoked"
        if revocation == nil, result.succeeded, let code = response?.httpStatus,
           (200..<300).contains(code), response?.handlersUnchanged == true, unchanged, store.consent {
            do { try store.acknowledge(record); status = "http-accepted" }
            catch { status = "receipt-not-persisted" }
        }
        do { try store.removeSDKCache() } catch { status = "cache-cleanup-failed" }
        worker = nil
        let done = completion; completion = nil
        // Keep revocation active while the send callback executes; it must not start another send.
        done?(Outcome(result: status, handlersUnchanged: unchanged && (response?.handlersUnchanged ?? true), httpStatus: response?.httpStatus))
        if revocation != nil { finishRevocation() }
    }
    private static func exceptionHandlerAddress() -> UInt {
        NSGetUncaughtExceptionHandler().map { unsafeBitCast($0, to: UInt.self) } ?? 0
    }
}
