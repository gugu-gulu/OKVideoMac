import Foundation
import Darwin

/// Prototype-only fault injection. No credentials or report bytes are passed in argv.
public enum UploadWorkerFault: String, Sendable {
    case none, spawnFailure, noRead, exitBeforeRead, exitAfterRead, noReply, invalidReply, oversizedReply
}

/// Owns all blocking process operations off the main thread. Cancellation is a flag, not a wait.
/// One instance stays alive until its child is reaped and both pipes have been closed.
final class UploadProcess: @unchecked Sendable {
    struct Result {
        let response: SentryAdapter.Outcome?
        let succeeded: Bool
    }
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    static let maxResponseBytes = 4096
    static let deadlineSeconds: TimeInterval = 8

    func start(executable: URL?, packet: Data, fault: UploadWorkerFault, completion: @escaping (Result) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            completion(run(executable: executable, packet: packet, fault: fault))
        }
    }
    private func run(executable: URL?, packet: Data, fault: UploadWorkerFault) -> Result {
        let process = Process(), input = Pipe(), output = Pipe()
        defer {
            // This wait is deliberately off the main thread. Cache cleanup follows reaping.
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            for handle in [input.fileHandleForReading, input.fileHandleForWriting,
                           output.fileHandleForReading, output.fileHandleForWriting] { try? handle.close() }
        }
        process.executableURL = fault == .spawnFailure ? URL(fileURLWithPath: "/nonexistent-cvp-upload-worker") : executable
        process.arguments = fault == .none ? ["--upload-worker"] : ["--upload-worker", fault.rawValue]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        let writeFD = input.fileHandleForWriting.fileDescriptor, readFD = output.fileHandleForReading.fileDescriptor
        // A child closing stdin must yield EPIPE, never install/change a process-wide SIGPIPE handler.
        guard fcntl(writeFD, F_SETNOSIGPIPE, 1) != -1,
              fcntl(writeFD, F_SETFL, fcntl(writeFD, F_GETFL) | O_NONBLOCK) != -1,
              fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK) != -1,
              !isCancelled else { return Result(response: nil, succeeded: false) }
        let deadline = ProcessInfo.processInfo.systemUptime + Self.deadlineSeconds
        do { try process.run() } catch { return Result(response: nil, succeeded: false) }
        try? input.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
        var framed = packet; framed.append(10)
        var offset = 0, reply = Data(), reachedEOF = false
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !isCancelled && ProcessInfo.processInfo.systemUptime < deadline {
            if offset < framed.count {
                let count = framed.withUnsafeBytes { bytes in
                    Darwin.write(writeFD, bytes.baseAddress!.advanced(by: offset), framed.count - offset)
                }
                if count > 0 { offset += count }
                else if count < 0 && errno != EAGAIN && errno != EINTR { return Result(response: nil, succeeded: false) }
            }
            // Read throughout the lifetime: a noisy worker cannot fill stdout and deadlock its exit.
            let count = Darwin.read(readFD, &buffer, buffer.count)
            if count > 0 {
                guard reply.count + count <= Self.maxResponseBytes else { return Result(response: nil, succeeded: false) }
                reply.append(contentsOf: buffer.prefix(count))
            } else if count == 0 { reachedEOF = true }
            else if errno != EAGAIN && errno != EINTR { return Result(response: nil, succeeded: false) }
            if !process.isRunning && reachedEOF {
                process.waitUntilExit()
                return Result(response: try? JSONDecoder().decode(SentryAdapter.Outcome.self, from: reply),
                              succeeded: process.terminationStatus == 0 && offset == framed.count)
            }
            // Poll off-main; include write readiness only while packet data remains.
            var descriptors = [pollfd(fd: readFD, events: Int16(POLLIN), revents: 0),
                               pollfd(fd: offset < framed.count ? writeFD : -1, events: Int16(POLLOUT), revents: 0)]
            _ = poll(&descriptors, nfds_t(descriptors.count), 10)
        }
        return Result(response: nil, succeeded: false)
    }
}
