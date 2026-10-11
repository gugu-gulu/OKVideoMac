import Foundation
import CrashReporter

public final class OKCrashManager {
    public let store: ReportStore
    private let reporter: PLCrashReporter
    public private(set) var recovered = false
    public private(set) var recoveryFailed = false

    /// Called by the executable entry point, before SwiftUI App.main() or any mock business bootstrap.
    public init(root: URL, metadata: RunMetadata) throws {
        store = try ReportStore(root: root)
        let raw = root.appendingPathComponent("raw", isDirectory: true)
        try ReportStore.privateDirectory(raw)
        let config = PLCrashReporterConfig(signalHandlerType: .mach, symbolicationStrategy: [],
            shouldRegisterUncaughtExceptionHandler: true, basePath: raw.path,
            maxReportBytes: UInt(CrashMapper.maxRawBytes))
        reporter = PLCrashReporter(configuration: config)
        // Archive the previous report before the capture library can replace its pending slot.
        if reporter.hasPendingCrashReport() {
            do {
                let record = try CrashMapper.parse(reporter.loadPendingCrashReportDataAndReturnError())
                try store.save(record)
                recovered = true
            } catch { recoveryFailed = true }
            // Raw input is bounded and transient. Malformed reports must not create a startup crash loop.
            try reporter.purgePendingCrashReportAndReturnError()
        }
        reporter.customData = try JSONEncoder().encode(metadata)
        try reporter.enableAndReturnError()
    }
}
