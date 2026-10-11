import XCTest
import Foundation
@testable import CrashVisibilityCore

final class CrashVisibilityTests: XCTestCase {
    func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("CVPTests-" + UUID().uuidString) }
    func record(id: Int = 1, date: Date = Date()) -> CrashRecord {
        .init(id: String(format: "%032x", id), timestamp: date, version: "0.1.0", build: "1", osVersion: "14.8.9", architecture: "arm64", signal: "SIGTRAP", signalCode: "TRAP_BRKPT", threads: [.init(number: 0, crashed: true, frames: [.init(pc: 0x100001004, imageBase: 0x100000000)])], images: [.init(uuid: "12345678-1234-1234-1234-123456789ABC", base: 0x100000000, size: 0x2000, name: "CrashVisibilityPrototype", vmaddr: 0x100000000)])
    }
    func testFreshStoreDeniesUpload() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let s=try ReportStore(root:r);XCTAssertFalse(s.consent);XCTAssertTrue(try s.records().isEmpty)
    }
    func testConsentPersistsAndRevokes() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        do { let s=try ReportStore(root:r);try s.setConsent(true) }
        do { let s=try ReportStore(root:r);XCTAssertTrue(s.consent);try s.setConsent(false) }
        XCTAssertFalse(try ReportStore(root:r).consent)
    }
    func testCorruptConsentFailsClosed() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        try ReportStore.privateDirectory(r);try Data("garbage".utf8).write(to:r.appendingPathComponent("consent.json"))
        XCTAssertFalse(try ReportStore(root:r).consent)
    }
    func testPendingBoundAndOriginalMetadata() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let s=try ReportStore(root:r)
        for n in 1...8 { try s.save(record(id:n,date:Date().addingTimeInterval(Double(-n)))) }
        let saved=try s.records();XCTAssertEqual(saved.count,3);XCTAssertEqual(saved.last?.version,"0.1.0");XCTAssertEqual(saved.last?.build,"1")
        XCTAssertEqual(saved.last?.id,record(id:1).id)
    }
    func testExpiryAndCorruptionArePruned() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let s=try ReportStore(root:r);try s.save(record(date:Date().addingTimeInterval(-8*86400)))
        try Data("broken".utf8).write(to:s.pending.appendingPathComponent("bad.json"))
        XCTAssertTrue(try s.records().isEmpty)
    }
    func testReportPermissionsAndInstanceLease() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let s=try ReportStore(root:r);try s.save(record())
        XCTAssertThrowsError(try ReportStore(root:r))
        let dirs=try FileManager.default.attributesOfItem(atPath:r.path)
        XCTAssertEqual((dirs[.posixPermissions] as? NSNumber)?.intValue,0o700)
        let file=try FileManager.default.contentsOfDirectory(at:s.pending,includingPropertiesForKeys:nil).first!
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
    }
    func testSDKCacheRemovedWithoutSDKStartup() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        try ReportStore.privateDirectory(r.appendingPathComponent("sentry-cache"));try Data("DO_NOT_SEND".utf8).write(to:r.appendingPathComponent("sentry-cache/stale"))
        let s=try ReportStore(root:r);XCTAssertFalse(FileManager.default.fileExists(atPath:s.cache.path));XCTAssertFalse(s.consent)
    }
    func testInvalidRawInputDoesNotBecomeEvent() {
        XCTAssertThrowsError(try CrashMapper.parse(Data("malformed".utf8)))
        XCTAssertThrowsError(try CrashMapper.parse(Data(repeating:0,count:CrashMapper.maxRawBytes+1)))
    }
    func testWhitelistRejectsPrivateModuleAndMetadata() throws {
        var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(record())) as! [String:Any]
        object["version"]="https://private.invalid/token"
        let bad=try JSONDecoder().decode(CrashRecord.self,from:JSONSerialization.data(withJSONObject:object));XCTAssertFalse(bad.isValid)
        object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(record())) as! [String:Any]
        var images=object["images"] as! [[String:Any]];images[0]["name"]="/Users/private/video.mov";object["images"]=images
        XCTAssertFalse(try JSONDecoder().decode(CrashRecord.self,from:JSONSerialization.data(withJSONObject:object)).isValid)
    }
    func testMapperCanonicalizesUUIDAndRejectsFreeText() {
        XCTAssertEqual(CrashMapper.uuidString("12345678123412341234123456789abc"),"12345678-1234-1234-1234-123456789ABC")
        XCTAssertNil(CrashMapper.uuidString("private token"));XCTAssertEqual(CrashMapper.allowedCode("https://private.invalid"),"UNKNOWN")
    }
    func testPrivateConfigRequiresOwnerOnlyFile() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) };try ReportStore.privateDirectory(r)
        let file=r.appendingPathComponent("app.env");try Data("SENTRY_DSN=https://test@example.invalid/1\nSENTRY_AUTH_TOKEN=DO_NOT_SEND\n".utf8).write(to:file)
        try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:file.path);XCTAssertThrowsError(try PrivateConfiguration.dsn(at:file.path))
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path);XCTAssertEqual(try PrivateConfiguration.dsn(at:file.path),"https://test@example.invalid/1")
        XCTAssertNil(try PrivateConfiguration.dsn(at:nil))
    }
    func testSerializedSentryEventIsAllowlisted() throws {
        let event=SentryUploadWorker.event(record());let data=try JSONSerialization.data(withJSONObject:event.serialize())
        let object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        XCTAssertEqual(Set(object.keys),Set(["event_id","timestamp","level","platform","release","dist","environment","contexts","threads","exception","debug_meta"]))
        XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("/Users/"))
        XCTAssertEqual(object["dist"] as? String,"1")
    }
    @MainActor func testRecoveryAcknowledgementSurvivesNormalRestart() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let store=try ReportStore(root:r);try store.save(record())
        var starts=0
        let first=RecoveryCoordinator(store:store,dsn:nil,startup:{starts += 1})
        XCTAssertTrue(first.waitingForDecision);XCTAssertEqual(starts,0)
        first.continueStartup();first.continueStartup()
        XCTAssertEqual(starts,1);XCTAssertFalse(store.consent)
        let next=RecoveryCoordinator(store:store,dsn:nil,startup:{starts += 1})
        XCTAssertFalse(next.waitingForDecision,"Acknowledged old reports must not block every normal launch")
        XCTAssertEqual(starts,2);XCTAssertEqual(try store.records().count,1)
    }
    @MainActor func testNewCrashStillPromptsAfterAcknowledgedReport() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let store=try ReportStore(root:r);try store.save(record())
        RecoveryCoordinator(store:store,dsn:nil,startup:{}).continueStartup()
        try store.save(record(id:2))
        let next=RecoveryCoordinator(store:store,dsn:nil,startup:{})
        XCTAssertTrue(next.waitingForDecision);XCTAssertEqual(next.pendingCount,2)
    }
    @MainActor func testUnavailableCaptureDoesNotBlockStartup() {
        var starts=0
        let model=RecoveryCoordinator(store:nil,dsn:nil,startup:{starts += 1})
        XCTAssertFalse(model.waitingForDecision);XCTAssertEqual(starts,1)
        model.continueStartup();XCTAssertEqual(starts,1)
    }

    @MainActor func testRecoveryCopyAfterRevocationDoesNotClaimPendingReport() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let store=try ReportStore(root:r);try store.save(record());try store.setConsent(true)
        let model=RecoveryCoordinator(store:store,dsn:nil,startup:{})
        model.setConsent(false)
        XCTAssertFalse(model.consent);XCTAssertEqual(model.pendingCount,0)
        XCTAssertFalse(model.recoveryExplanation.contains("报告仅保存在本机"))
        XCTAssertTrue(model.recoveryExplanation.contains("已无待处理报告"))
    }
    func testRecoveryAcknowledgementPersistsAcrossStoreInstances() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        do { let s=try ReportStore(root:r);try s.save(record());try s.acknowledgeRecoveryPrompt() }
        let s=try ReportStore(root:r);XCTAssertFalse(try s.needsRecoveryPrompt())
        XCTAssertFalse(s.consent);XCTAssertEqual(try s.records().count,1)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath:r.appendingPathComponent("recovery-prompt.json").path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
    }
    @MainActor func testRecoveryAcknowledgementWriteFailureStillContinuesOnce() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let s=try ReportStore(root:r);try s.save(record())
        try FileManager.default.createDirectory(at:r.appendingPathComponent("recovery-prompt.json"),withIntermediateDirectories:false)
        var starts=0;let m=RecoveryCoordinator(store:s,dsn:nil,startup:{starts += 1})
        m.continueStartup();m.continueStartup();XCTAssertEqual(starts,1)
        XCTAssertTrue(m.status.contains("无法保存"));XCTAssertFalse(s.consent)
    }
    @MainActor func testMalformedAcknowledgementPromptsButDoesNotGrantConsent() throws {
        let r=root();defer { try? FileManager.default.removeItem(at:r) }
        let s=try ReportStore(root:r);try s.save(record())
        try Data("invalid".utf8).write(to:r.appendingPathComponent("recovery-prompt.json"))
        let m=RecoveryCoordinator(store:s,dsn:nil,startup:{})
        XCTAssertTrue(m.waitingForDecision);XCTAssertFalse(m.consent)
    }

    @MainActor func testOversizedWorkerPacketRejectedBeforeSpawn() throws {
        let r=root(); defer { try? FileManager.default.removeItem(at:r) }
        let s=try ReportStore(root:r); try s.setConsent(true)
        let original=record()
        let frame=CrashRecord.Frame(pc:UInt64.max-1,imageBase:UInt64.max-1000)
        let large=CrashRecord(id:original.id,timestamp:original.timestamp,version:original.version,build:original.build,
            osVersion:original.osVersion,architecture:original.architecture,signal:original.signal,signalCode:original.signalCode,
            threads:(0..<128).map { .init(number:$0,crashed:$0==0,frames:Array(repeating:frame,count:256)) },images:original.images)
        XCTAssertTrue(large.isValid)
        XCTAssertGreaterThan(try JSONEncoder().encode(large).count,CrashMapper.maxRawBytes)
        let adapter=SentryAdapter(store:s)
        XCTAssertThrowsError(try adapter.send(large,dsn:"http://test@127.0.0.1:1/1",allowLoopback:true) { _ in XCTFail("must not start") })
        XCTAssertFalse(adapter.active);XCTAssertFalse(FileManager.default.fileExists(atPath:s.cache.path))
    }

}
