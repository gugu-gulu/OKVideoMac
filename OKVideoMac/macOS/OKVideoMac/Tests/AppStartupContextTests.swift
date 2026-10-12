import Darwin
import Foundation
import OKVideoCore
import XCTest
@testable import OKVideoMac

@MainActor
final class AppStartupContextTests: XCTestCase {
    private func directories() throws -> AppDirectories {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("OKVideoMac-StartupContext-\(UUID().uuidString)")
        let directories = try AppDirectories(applicationSupport: root.appendingPathComponent("Support"),
                                             caches: root.appendingPathComponent("Caches"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return directories
    }

    private func context(_ directories: AppDirectories) throws -> AppStartupContext {
        try AppStartupContext.prepare(directories: directories,
            environment: ["XCTestBundlePath": "isolated.xctest"],
            bundleIdentifier: "com.okvideomac.startup-tests", processIdentifier: getpid())
    }

    func testPreflightHoldsLeaseWithoutOpeningDatabase() throws {
        let directories = try directories()
        let context = try context(directories)
        XCTAssertFalse(context.hasStartedBusinessBootstrap)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.database
            .appendingPathComponent("OKVideoMac.sqlite3").path))
        XCTAssertThrowsError(try ApplicationInstanceLease(lockURL: context.applicationInstanceLease.lockURL))
    }

    func testCompetingPreflightCannotEnterBusiness() throws {
        let directories = try directories()
        let first = try context(directories)
        XCTAssertThrowsError(try context(directories))
        XCTAssertFalse(first.hasStartedBusinessBootstrap)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.database
            .appendingPathComponent("OKVideoMac.sqlite3").path))
    }

    func testOlderApplicationConflictStopsBeforeAcquiringLease() throws {
        enum Conflict: Error { case anotherApplication }
        let directories = try directories()
        var checked = false
        XCTAssertThrowsError(try AppStartupContext.prepare(directories: directories,
            environment: [:], bundleIdentifier: "com.okvideomac.startup-tests", processIdentifier: 42,
            checkExistingApplication: { identifier, pid in
                XCTAssertEqual(identifier, "com.okvideomac.startup-tests")
                XCTAssertEqual(pid, 42)
                checked = true
                throw Conflict.anotherApplication
            }))
        XCTAssertTrue(checked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.applicationSupport
            .appendingPathComponent(".instance.lock").path))
    }

    func testTestHostSkipsRunningApplicationPolicyButStillLocksItsOwnDirectory() throws {
        let directories = try directories()
        let context = try AppStartupContext.prepare(directories: directories,
            environment: ["XCTestConfigurationFilePath": "isolated.xctestconfiguration"],
            bundleIdentifier: "com.okvideomac.startup-tests", processIdentifier: getpid(),
            checkExistingApplication: { _, _ in XCTFail("Test host must skip production process lookup") })
        XCTAssertThrowsError(try ApplicationInstanceLease(lockURL: context.applicationInstanceLease.lockURL))
    }

    func testEnvironmentConsumesContextExactlyOnceBeforeDatabaseWork() throws {
        let directories = try directories()
        let context = try context(directories)
        let environment = try AppEnvironment.live(startupContext: context)
        XCTAssertTrue(environment.applicationInstanceLease === context.applicationInstanceLease)
        XCTAssertTrue(context.hasStartedBusinessBootstrap)
        XCTAssertThrowsError(try AppEnvironment.live(startupContext: context)) { error in
            guard case AppStartupContext.BootstrapError.alreadyConsumed = error else {
                return XCTFail("Duplicate bootstrap must fail before database work: \(error)")
            }
        }
    }

    func testLeaseSurvivesContextReleaseAndEndsWithEnvironment() throws {
        let directories = try directories()
        var startup: AppStartupContext? = try context(directories)
        weak var lease = startup?.applicationInstanceLease
        let lockURL = try XCTUnwrap(lease?.lockURL)
        var environment: AppEnvironment? = try AppEnvironment.live(startupContext: startup)
        startup = nil
        XCTAssertNotNil(lease)
        XCTAssertTrue(environment?.applicationInstanceLease === lease)
        XCTAssertThrowsError(try ApplicationInstanceLease(lockURL: lockURL))
        environment = nil
        XCTAssertNil(lease)
        let replacement = try ApplicationInstanceLease(lockURL: lockURL)
        withExtendedLifetime(replacement) {}
    }

    func testConsumedContextCannotRetryAfterInitializationHasStarted() throws {
        let context = try context(directories())
        try context.claimBusinessBootstrap()
        XCTAssertThrowsError(try AppEnvironment.live(startupContext: context))
    }
}
