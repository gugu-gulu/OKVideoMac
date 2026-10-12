import Foundation
import OKVideoCore
import OKCrashDiagnostics
import XCTest
@testable import OKVideoMac

@MainActor
final class AppStartupControllerTests: XCTestCase {
    private func fixture() throws -> (AppLaunchSession, ReportStore) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("OKStartupShell-\(UUID().uuidString)")
        let directories=try AppDirectories(applicationSupport:root.appendingPathComponent("Support"),caches:root.appendingPathComponent("Caches"))
        let context=try AppStartupContext.prepare(directories:directories,
            environment:["XCTestBundlePath":"isolated.xctest"],bundleIdentifier:"com.okvideomac.shell-tests",processIdentifier:42)
        let store=try ReportStore(root:root.appendingPathComponent("Reports"))
        addTeardownBlock { try? FileManager.default.removeItem(at:root) }
        return (AppLaunchSession(startup:.success(context),crashManager:nil),store)
    }

    private func addReport(_ store: ReportStore, id:Int=1) throws {
        let json:[String:Any]=[
            "id":String(format:"%032x",id),"timestamp":Date().timeIntervalSinceReferenceDate,
            "version":"0.8.4","build":"137","osVersion":"14.8.9","architecture":"arm64",
            "signal":"SIGTRAP","signalCode":"TRAP_BRKPT",
            "threads":[["number":0,"crashed":true,"frames":[["pc":4294971396,"imageBase":4294967296]]]],
            "images":[["uuid":"12345678-1234-1234-1234-123456789ABC","base":4294967296,"size":8192,"name":"OKVideoMac","vmaddr":4294967296]]
        ]
        try store.save(JSONDecoder().decode(CrashRecord.self,from:JSONSerialization.data(withJSONObject:json)))
    }

    private func settle(_ controller: AppStartupController) async {
        for _ in 0..<20 { if controller.phase != .starting { return };await Task.yield() }
    }

    func testRecoveryDoesNotCreateBusinessUntilExplicitContinue() async throws {
        let (session,store)=try fixture();try addReport(store)
        var starts=0
        let controller=AppStartupController(session:session,store:store,bootstrap:{starts+=1;return AppState(environment:nil)})
        controller.beginIfReady();await Task.yield()
        XCTAssertEqual(controller.phase,.recovery);XCTAssertEqual(starts,0);XCTAssertNil(controller.business)
        XCTAssertFalse(controller.canRunBusinessEvents)
        controller.continueStartup();controller.continueStartup();controller.beginIfReady();await settle(controller)
        XCTAssertEqual(starts,1);XCTAssertEqual(controller.phase,.ready)
        XCTAssertFalse(store.consent);XCTAssertEqual(try store.records().count,1)
    }

    func testAcknowledgedReportDoesNotBlockNextCleanStartup() async throws {
        let (session,store)=try fixture();try addReport(store);try store.acknowledgeRecoveryPrompt()
        var starts=0
        let controller=AppStartupController(session:session,store:store,bootstrap:{starts+=1;return AppState(environment:nil)})
        XCTAssertEqual(controller.phase,.starting)
        controller.beginIfReady();controller.beginIfReady();await settle(controller)
        XCTAssertEqual(starts,1);XCTAssertEqual(controller.phase,.ready)
    }

    func testNewCrashRepromptsAfterAcknowledgedReport() throws {
        let (session,store)=try fixture();try addReport(store);try store.acknowledgeRecoveryPrompt();try addReport(store,id:2)
        let controller=AppStartupController(session:session,store:store,bootstrap:{XCTFail("Business started early");return AppState(environment:nil)})
        XCTAssertEqual(controller.phase,.recovery);XCTAssertEqual(controller.pendingReports,2)
    }

    func testFailedPromptAcknowledgementStillStartsOnlyOnce() async throws {
        let (session,store)=try fixture();try addReport(store)
        try FileManager.default.createDirectory(at:store.root.appendingPathComponent("recovery-prompt.json"),withIntermediateDirectories:false)
        var starts=0
        let controller=AppStartupController(session:session,store:store,bootstrap:{starts+=1;return AppState(environment:nil)})
        controller.continueStartup();controller.continueStartup();await settle(controller)
        XCTAssertEqual(starts,1);XCTAssertTrue(controller.recoveryWarning)
    }

    func testClosingRecoveryNeverCreatesBusinessAndKeepsUnacknowledgedReport() async throws {
        let (session,store)=try fixture();try addReport(store)
        var starts=0
        let controller=AppStartupController(session:session,store:store,bootstrap:{starts+=1;return AppState(environment:nil)})
        controller.requestTermination();controller.continueStartup();controller.beginIfReady();await Task.yield()
        XCTAssertEqual(starts,0);XCTAssertNil(controller.business);XCTAssertTrue(try store.needsRecoveryPrompt())
    }

    func testQuitBeforeScheduledBootstrapCancelsBusinessCreation() async throws {
        let (session,store)=try fixture();var starts=0
        let controller=AppStartupController(session:session,store:store,bootstrap:{starts+=1;return AppState(environment:nil)})
        controller.beginIfReady();controller.requestTermination();await Task.yield()
        XCTAssertEqual(starts,0);XCTAssertEqual(controller.phase,.terminating)
    }

    func testFileOpensStayBoundedBeforeBusinessAndReleaseOnQuit() throws {
        let (session,store)=try fixture();try addReport(store)
        let controller=AppStartupController(session:session,store:store,bootstrap:{XCTFail("File opened before recovery decision");return AppState(environment:nil)})
        for i in 0..<AppStartupController.maximumQueuedFiles { XCTAssertTrue(controller.openFile(URL(fileURLWithPath:"/private/tmp/config-\(i).json"))) }
        XCTAssertFalse(controller.openFile(URL(fileURLWithPath:"/private/tmp/overflow.json")))
        XCTAssertEqual(controller.pendingFileCount,16);XCTAssertNil(controller.business)
        controller.requestTermination();XCTAssertEqual(controller.pendingFileCount,0)
        XCTAssertFalse(controller.openFile(URL(fileURLWithPath:"/private/tmp/late.json")))
    }

    func testPreflightFailureHasNoBusinessAndRejectsFileOpen() throws {
        enum Failed:Error {case preflight}
        var starts=0
        let controller=AppStartupController(session:AppLaunchSession(startup:.failure(Failed.preflight),crashManager:nil),bootstrap:{starts+=1;return AppState(environment:nil)})
        controller.beginIfReady();controller.continueStartup()
        XCTAssertEqual(controller.phase,.failed);XCTAssertEqual(starts,0);XCTAssertNil(controller.business)
        XCTAssertFalse(controller.openFile(URL(fileURLWithPath:"/private/tmp/late.json")))
    }
}
