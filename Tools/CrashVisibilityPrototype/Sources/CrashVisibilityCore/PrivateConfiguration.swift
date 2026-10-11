import Foundation
import Darwin

public enum PrivateConfiguration {
    /// Read DSN only. This file is never bundled and its contents are never logged.
    public static func dsn(at path: String?) throws -> String? {
        guard let path else { return nil }
        let url = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0,
              let size = attributes[.size] as? NSNumber, size.intValue < 16384 else { throw PrototypeError.invalidConfiguration }
        let text = try String(contentsOf: url, encoding: .utf8)
        let values = text.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("#") }.compactMap { line -> String? in
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces) == "SENTRY_DSN" else { return nil }
            return pair[1].trimmingCharacters(in: .whitespaces)
        }
        guard values.count == 1, !values[0].isEmpty else { throw PrototypeError.invalidConfiguration }
        return values[0]
    }
}
