import Foundation
import CrashReporter
import CryptoKit

/// Only these fields can cross the local-report boundary. Never carries arbitrary log strings.
public struct CrashRecord: Codable, Equatable, Sendable {
    public struct Image: Codable, Equatable, Sendable {
        public let uuid: String
        public let base: UInt64
        public let size: UInt64
        public let name: String
        public let vmaddr: UInt64?
    }
    public struct Frame: Codable, Equatable, Sendable {
        public let pc: UInt64
        public let imageBase: UInt64?
    }
    public struct Thread: Codable, Equatable, Sendable {
        public let number: Int
        public let crashed: Bool
        public let frames: [Frame] // oldest first, as required by Sentry
    }
    public let id: String
    public let timestamp: Date
    public let version: String
    public let build: String
    public let osVersion: String
    public let architecture: String
    public let signal: String
    public let signalCode: String
    public let threads: [Thread]
    public let images: [Image]
}

public struct RunMetadata: Codable, Sendable {
    public let version: String
    public let build: String
    public let imageVMAddresses: [String: UInt64]?
    public init(version: String, build: String, imageVMAddresses: [String: UInt64]? = nil) {
        self.version = version; self.build = build; self.imageVMAddresses = imageVMAddresses
    }
}

public enum CrashMapper {
    public static let maxRawBytes = 1_048_576
    public static func parse(_ data: Data) throws -> CrashRecord {
        guard data.count <= maxRawBytes else { throw CrashDiagnosticError.invalidReport }
        let report = try PLCrashReport(data: data)
        guard let rawMeta = report.customData,
              let meta = try? JSONDecoder().decode(RunMetadata.self, from: rawMeta),
              numeric(meta.version), numeric(meta.build) else { throw CrashDiagnosticError.invalidReport }
        let images: [CrashRecord.Image] = (report.images as? [PLCrashReportBinaryImageInfo] ?? []).prefix(1024).compactMap { image in
            guard image.hasImageUUID, let uuid = uuidString(image.imageUUID) else { return nil }
            let basename = URL(fileURLWithPath: image.imageName).lastPathComponent
            let name = ["OKVideoMac"].contains(basename) ? basename : "image-\(uuid)"
            return .init(uuid: uuid, base: image.imageBaseAddress, size: image.imageSize, name: name, vmaddr: meta.imageVMAddresses?[uuid])
        }
        let threads: [CrashRecord.Thread] = (report.threads as? [PLCrashReportThreadInfo] ?? []).prefix(128).map { thread in
            let frames = (thread.stackFrames as? [PLCrashReportStackFrameInfo] ?? []).prefix(256).map { frame -> CrashRecord.Frame in
                let pc = frame.instructionPointer
                let image = images.first { pc >= $0.base && pc - $0.base < $0.size }
                return .init(pc: pc, imageBase: image?.base)
            }.reversed()
            return .init(number: thread.threadNumber, crashed: thread.crashed, frames: Array(frames))
        }
        guard threads.contains(where: { $0.crashed && !$0.frames.isEmpty }), !images.isEmpty else { throw CrashDiagnosticError.invalidReport }
        let digest = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
        let cpu = report.machineInfo?.processorInfo?.type ?? report.systemInfo.processorInfo.type
        let architecture = cpu == 0x0100000c ? "arm64" : cpu == 0x01000007 ? "x86_64" : "unknown"
        return .init(id: digest, timestamp: report.systemInfo.timestamp,
                     version: meta.version, build: meta.build,
                     osVersion: numeric(report.systemInfo.operatingSystemVersion) ? report.systemInfo.operatingSystemVersion : "unknown",
                     architecture: architecture,
                     signal: allowedCode(report.signalInfo.name), signalCode: allowedCode(report.signalInfo.code),
                     threads: threads, images: images)
    }
    static func numeric(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 32 && value.unicodeScalars.allSatisfy { "0123456789.".unicodeScalars.contains($0) }
    }
    static func allowedCode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789")
        return value.count <= 64 && !value.isEmpty && value.unicodeScalars.allSatisfy(allowed.contains) ? value : "UNKNOWN"
    }
    static func uuidString(_ input: String) -> String? {
        let hex = input.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32, hex.unicodeScalars.allSatisfy(CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains) else { return nil }
        let parts = [8, 4, 4, 4, 12]; var index = hex.startIndex
        let formatted = parts.map { count -> String in
            let end = hex.index(index, offsetBy: count); defer { index = end }
            return String(hex[index..<end])
        }.joined(separator: "-")
        return UUID(uuidString: formatted)?.uuidString
    }
}

extension CrashRecord {
    var isValid: Bool {
        id.count == 32 && id.unicodeScalars.allSatisfy(CharacterSet(charactersIn: "0123456789abcdef").contains)
        && CrashMapper.numeric(version) && CrashMapper.numeric(build)
        && (osVersion == "unknown" || CrashMapper.numeric(osVersion))
        && ["arm64", "x86_64", "unknown"].contains(architecture)
        && CrashMapper.allowedCode(signal) == signal && CrashMapper.allowedCode(signalCode) == signalCode
        && timestamp.timeIntervalSince1970.isFinite
        && !images.isEmpty && images.count <= 1024 && images.allSatisfy {
            CrashMapper.uuidString($0.uuid) == $0.uuid && $0.size > 0
            && ["OKVideoMac", "image-" + $0.uuid].contains($0.name)
        }
        && !threads.isEmpty && threads.count <= 128
        && threads.contains { $0.crashed && !$0.frames.isEmpty }
        && threads.allSatisfy { $0.number >= 0 && $0.frames.count <= 256 }
    }
}

public enum CrashDiagnosticError: Error { case invalidReport, alreadyRunning, invalidConfiguration, unavailable }
