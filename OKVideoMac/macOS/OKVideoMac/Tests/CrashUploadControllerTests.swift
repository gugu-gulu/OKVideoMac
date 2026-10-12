import Foundation
import OKCrashDiagnostics
import XCTest
@testable import OKVideoMac

@MainActor
final class CrashUploadControllerTests: XCTestCase {
    private final class Sender: CrashReportSending {
        let store: ReportStore
        var active = false
        var ids: [String] = []
        var sendCompletion: ((SentryAdapter.Outcome) -> Void)?
        var revokeCompletion: ((Error?) -> Void)?
        var cancelCompletion: (() -> Void)?
        init(_ store: ReportStore) { self.store = store }
        func send(_ record: CrashRecord, dsn: String, allowLoopback: Bool, contaminateScopeForTest: Bool,
                  completion: @escaping (SentryAdapter.Outcome) -> Void) throws {
            XCTAssertTrue(store.consent)
            XCTAssertFalse(contaminateScopeForTest)
            ids.append(record.id); active = true; sendCompletion = completion
        }
        func complete(_ result: String) throws {
            if result == "http-accepted", let record = try store.records().first { try store.acknowledge(record) }
            let outcome = try JSONDecoder().decode(SentryAdapter.Outcome.self,
                from: Data("{\"result\":\"\(result)\",\"handlersUnchanged\":true}".utf8))
            active = false; let done = sendCompletion; sendCompletion = nil; done?(outcome)
        }
        func revoke(completion: @escaping (Error?) -> Void) {
            try? store.setConsent(false); revokeCompletion = completion
        }
        func finishRevoke(error: Error? = nil) throws {
            active = false; sendCompletion = nil
            if error == nil { try store.discard(); try store.removeSDKCache() }
            let done = revokeCompletion; revokeCompletion = nil; done?(error)
        }
        func cancel(completion: @escaping () -> Void) { cancelCompletion = completion }
    }

    private func fixture() throws -> (ReportStore, Sender) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("OKUploadTests-\(UUID())")
        let store = try ReportStore(root: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (store, Sender(store))
    }
    private func save(_ store: ReportStore, id: Int = 1) throws {
        let object: [String: Any] = ["id": String(format: "%032x", id), "timestamp": Date().timeIntervalSinceReferenceDate,
            "version": "0.8.4", "build": "137", "osVersion": "14.8.9", "architecture": "arm64", "signal": "SIGTRAP", "signalCode": "TRAP_BRKPT",
            "threads": [["number": 0, "crashed": true, "frames": [["pc": 4294971396, "imageBase": 4294967296]]]],
            "images": [["uuid": "12345678-1234-1234-1234-123456789ABC", "base": 4294967296, "size": 8192, "name": "OKVideoMac", "vmaddr": 4294967296]]]
        try store.save(JSONDecoder().decode(CrashRecord.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    private func model(_ store: ReportStore, _ sender: Sender) -> CrashUploadController {
        CrashUploadController(store: store, configuration: CrashUploadConfiguration(dsn: "https://public@example.invalid/1"), adapter: sender)
    }

    func testDefaultAndRetryCannotSendWithoutConsent() throws {
        let (store, sender) = try fixture(); try save(store)
        let model = model(store, sender); model.start(); model.retry()
        XCTAssertFalse(model.consent); XCTAssertEqual(model.pendingReports, 1); XCTAssertTrue(sender.ids.isEmpty)
    }
    func testGrantPersistsBeforeSendingAndRepeatedRetryDoesNotDuplicate() throws {
        let (store, sender) = try fixture(); try save(store)
        let model = model(store, sender); model.setConsent(true); model.retry(); model.start(); model.start()
        XCTAssertTrue(store.consent); XCTAssertEqual(sender.ids.count, 1); XCTAssertTrue(model.sending)
        try sender.complete("http-accepted")
        XCTAssertEqual(model.pendingReports, 0); XCTAssertFalse(model.sending); XCTAssertTrue(try store.records().isEmpty)
    }
    func testFailureKeepsEventIDForExplicitRetry() throws {
        let (store, sender) = try fixture(); try save(store)
        let model = model(store, sender); model.setConsent(true); try sender.complete("pending")
        XCTAssertEqual(model.status, .pending); XCTAssertTrue(model.canRetry); XCTAssertEqual(sender.ids.count, 1)
        model.retry(); XCTAssertEqual(sender.ids.count, 2); XCTAssertEqual(sender.ids[0], sender.ids[1])
    }
    func testConfirmedSendDrainsAtMostRetainedReports() throws {
        let (store, sender) = try fixture(); try save(store); try save(store, id: 2); try save(store, id: 3)
        let model = model(store, sender); model.setConsent(true)
        for _ in 0..<3 { try sender.complete("http-accepted") }
        XCTAssertEqual(sender.ids.count, 3); XCTAssertEqual(model.pendingReports, 0); XCTAssertFalse(model.sending)
    }
    func testRevokeClosesConsentBeforeCleanupAndLateSendCannotRestart() throws {
        let (store, sender) = try fixture(); try save(store)
        let model = model(store, sender); model.setConsent(true)
        let late = sender.sendCompletion
        model.setConsent(false); XCTAssertFalse(store.consent); XCTAssertFalse(model.consent); XCTAssertTrue(model.revoking)
        model.retry(); try sender.finishRevoke()
        late?(try JSONDecoder().decode(SentryAdapter.Outcome.self, from: Data("{\"result\":\"pending\",\"handlersUnchanged\":true}".utf8)))
        XCTAssertFalse(model.canRetry); XCTAssertEqual(sender.ids.count, 1); XCTAssertEqual(model.pendingReports, 0); XCTAssertEqual(model.status, .revoked)
    }
    func testImmediateRegrantWaitsForCleanupAndDoesNotReplayDiscardedReport() throws {
        let (store, sender) = try fixture(); try save(store)
        let model = model(store, sender); model.setConsent(true); model.setConsent(false); model.setConsent(true)
        XCTAssertFalse(store.consent); XCTAssertEqual(sender.ids.count, 1)
        try sender.finishRevoke(); XCTAssertTrue(model.consent); XCTAssertTrue(store.consent)
        XCTAssertEqual(sender.ids.count, 1); XCTAssertEqual(model.pendingReports, 0)
    }
    func testFailedRevocationNeverRegrants() throws {
        enum Failure: Error { case cleanup }
        let (store, sender) = try fixture(); try save(store)
        let model = model(store, sender); model.setConsent(true); model.setConsent(false); model.setConsent(true)
        try sender.finishRevoke(error: Failure.cleanup)
        XCTAssertFalse(model.consent); XCTAssertFalse(store.consent); XCTAssertEqual(model.status, .storageFailed)
    }
    func testFailedConsentWriteCannotStartTransport() throws {
        let (store, sender) = try fixture(); try save(store)
        try FileManager.default.createDirectory(at: store.root.appendingPathComponent("consent.json"), withIntermediateDirectories: false)
        let model = model(store, sender); model.setConsent(true)
        XCTAssertFalse(store.consent); XCTAssertEqual(model.status, .storageFailed); XCTAssertTrue(sender.ids.isEmpty)
    }
    func testMissingConfigurationStillAllowsLocalConsentAndRevoke() throws {
        let (store, sender) = try fixture(); try save(store)
        let model = CrashUploadController(store: store, configuration: nil, adapter: sender)
        model.setConsent(true); XCTAssertEqual(model.status, .unconfigured); XCTAssertTrue(sender.ids.isEmpty)
        model.setConsent(false); try sender.finishRevoke(); XCTAssertFalse(model.consent); XCTAssertEqual(model.pendingReports, 0)
    }
    func testStoppingBlocksRegrantAndKeepsUnsentReport() async throws {
        let (store, sender) = try fixture(); try save(store)
        let model = model(store, sender); model.setConsent(true); model.requestStop(); model.setConsent(true); model.retry()
        XCTAssertTrue(model.stopping); XCTAssertEqual(sender.ids.count, 1); XCTAssertEqual(try store.records().count, 1)
        sender.cancelCompletion?(); await model.shutdown()
        XCTAssertTrue(store.consent); XCTAssertEqual(try store.records().count, 1)
    }
}
