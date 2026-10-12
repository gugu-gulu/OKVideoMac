import AppKit
import Darwin
import Foundation
import OKVideoCore

/// Owns the existing business lease before any database/player initialization.
/// AppEnvironment retains the same lease when the context is consumed.
@MainActor
final class AppStartupContext {
    enum BootstrapError: Error { case alreadyConsumed }

    let directories: AppDirectories
    let acceptance: ImportedAcceptanceWorkspace?
    let applicationInstanceLease: ApplicationInstanceLease
    private(set) var hasStartedBusinessBootstrap = false

    private init(directories: AppDirectories, acceptance: ImportedAcceptanceWorkspace?,
                 applicationInstanceLease: ApplicationInstanceLease) {
        self.directories = directories
        self.acceptance = acceptance
        self.applicationInstanceLease = applicationInstanceLease
    }

    static func prepare() throws -> AppStartupContext {
        let environment = ProcessInfo.processInfo.environment
        return try prepare(
            directories: AppEnvironment.runtimeDirectories(environment: environment),
            acceptance: AppEnvironment.acceptanceWorkspace(environment: environment),
            environment: environment,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.okvideomac.OKVideoMac",
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        )
    }

    /// Explicit directories keep policy tests and acceptance hosts off user data.
    static func prepare(
        directories: AppDirectories,
        acceptance: ImportedAcceptanceWorkspace? = nil,
        environment: [String: String],
        bundleIdentifier: String,
        processIdentifier: pid_t,
        checkExistingApplication: @MainActor (String, pid_t) throws -> Void = {
            try ApplicationInstancePolicy.rejectOtherRunningApplication(
                bundleIdentifier: $0, currentProcessIdentifier: $1
            )
        }
    ) throws -> AppStartupContext {
        if !AppEnvironment.isXCTestHost(environment: environment) {
            try checkExistingApplication(bundleIdentifier, processIdentifier)
        }
        let lease = try ApplicationInstanceLease(
            lockURL: directories.applicationSupport.appendingPathComponent(".instance.lock")
        )
        return AppStartupContext(directories: directories, acceptance: acceptance,
                                 applicationInstanceLease: lease)
    }

    func claimBusinessBootstrap() throws {
        guard !hasStartedBusinessBootstrap else { throw BootstrapError.alreadyConsumed }
        hasStartedBusinessBootstrap = true
    }
}
