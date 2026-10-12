import AppKit
import Combine
import Foundation
import OKCrashDiagnostics
import OKVideoCore

/// The SwiftUI shell owns no AppState until the single business-start gate opens.
@MainActor
final class AppStartupController: ObservableObject {
    enum Phase: Equatable { case recovery, starting, ready, failed, terminating }
    static let maximumQueuedFiles = 16
    @Published private(set) var phase: Phase
    @Published private(set) var business: AppState?
    @Published private(set) var recoveryWarning = false
    let session: AppLaunchSession
    let store: ReportStore?
    let diagnostics: CrashUploadController
    private let bootstrap: () -> AppState
    private var hasStarted = false
    private var bootstrapTask: Task<Void, Never>?
    private var fileOpenTask: Task<Void, Never>?
    private var files: [ScopedFileOpen] = []
    var pendingFileCount: Int { files.count }
    var pendingReports: Int { (try? store?.records().count) ?? 0 }
    var consent: Bool { diagnostics.consent }
    var canRunBusinessEvents: Bool { phase == .ready }

    init(session: AppLaunchSession, store: ReportStore? = nil,
         bootstrap: (() -> AppState)? = nil) {
        self.session = session
        self.store = store ?? session.crashManager?.store
        self.diagnostics = store.map { CrashUploadController(store: $0, configuration: nil) } ?? session.diagnostics
        self.bootstrap = bootstrap ?? { session.bootstrapBusiness() }
        if case .failure = session.startup { phase = .failed }
        else { phase = ((try? self.store?.needsRecoveryPrompt()) ?? false) ? .recovery : .starting }
        diagnostics.start()
    }

    var failureMessage: String? {
        guard case .failure(let error) = session.startup else { return nil }
        return CommonUserFacingErrorMapper.message(for: error) ?? LogRedactor.text(error.localizedDescription)
    }

    func beginIfReady() {
        guard phase == .starting, !hasStarted, bootstrapTask == nil else { return }
        bootstrapTask = Task { @MainActor [weak self] in
            await Task.yield()
#if OKVIDEO_CRASH_ACCEPTANCE
            await CrashAcceptance.delayBootstrapIfRequested()
#endif
            guard let self, !Task.isCancelled, self.phase == .starting, !self.hasStarted else { return }
            self.hasStarted = true
            let business = self.bootstrap()
            self.business = business
            self.phase = .ready
            self.bootstrapTask = nil
            self.drainFiles()
        }
    }

    func continueStartup() {
        guard phase == .recovery else { return }
        do { try store?.acknowledgeRecoveryPrompt() }
        catch { recoveryWarning = true }
        phase = .starting
        beginIfReady()
    }

    @discardableResult
    func openFile(_ url: URL) -> Bool {
        guard phase != .failed, phase != .terminating, files.count < Self.maximumQueuedFiles else { return false }
        files.append(ScopedFileOpen(url))
        if canRunBusinessEvents { drainFiles() }
        return true
    }

    private func drainFiles() {
        guard canRunBusinessEvents, let business, fileOpenTask == nil, !files.isEmpty else { return }
        fileOpenTask = Task { @MainActor [weak self, weak business] in
            guard let self, let business else { return }
            while !Task.isCancelled, self.canRunBusinessEvents, !self.files.isEmpty {
                let request = self.files.removeFirst()
                _ = await business.importConfiguration(source: .localFile(request.url),
                    name: request.url.deletingPathExtension().lastPathComponent)
                request.finish()
            }
            self.fileOpenTask = nil
        }
    }

    func requestTermination() {
        phase = .terminating
        diagnostics.requestStop()
        bootstrapTask?.cancel(); bootstrapTask = nil
        fileOpenTask?.cancel(); fileOpenTask = nil
        files.removeAll()
    }
}

private final class ScopedFileOpen {
    let url: URL
    private var accessing: Bool
    init(_ url: URL) { self.url = url; accessing = url.startAccessingSecurityScopedResource() }
    func finish() { if accessing { url.stopAccessingSecurityScopedResource(); accessing = false } }
    deinit { finish() }
}
