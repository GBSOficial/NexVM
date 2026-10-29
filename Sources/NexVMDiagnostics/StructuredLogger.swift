import Foundation
import os

public enum LogLevel: String, Codable, Sendable, Comparable {
    case debug, info, warning, error

    private var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warning: 2
        case .error: 3
        }
    }
    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rank < b.rank }
}

public struct LogEntry: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var level: LogLevel
    public var category: String
    public var message: String
    public var vmID: UUID?
}

/// Append-only JSON Lines logger. Writes to a local file only; nothing leaves the machine.
public actor StructuredLogger {
    private let fileURL: URL
    private let minimumLevel: LogLevel
    private let osLog: Logger
    private var handle: FileHandle?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    public init(fileURL: URL, minimumLevel: LogLevel = .info, subsystem: String = "org.nexvm.app") {
        self.fileURL = fileURL
        self.minimumLevel = minimumLevel
        self.osLog = Logger(subsystem: subsystem, category: "nexvm")
    }

    public func log(_ level: LogLevel, _ category: String, _ message: String, vmID: UUID? = nil) {
        guard level >= minimumLevel else { return }
        osLog.log(level: osLevel(level), "\(category, privacy: .public): \(message, privacy: .private)")
        let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message, vmID: vmID)
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)
        do {
            let h = try openHandle()
            try h.write(contentsOf: data)
        } catch {
            osLog.error("log write failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func close() {
        try? handle?.close()
        handle = nil
    }

    private func openHandle() throws -> FileHandle {
        if let handle { return handle }
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        if !fm.fileExists(atPath: fileURL.path) {
            // Logs may contain paths and VM names: owner-only.
            fm.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let h = try FileHandle(forWritingTo: fileURL)
        try h.seekToEnd()
        handle = h
        return h
    }

    private func osLevel(_ l: LogLevel) -> OSLogType {
        switch l {
        case .debug: .debug
        case .info: .info
        case .warning: .default
        case .error: .error
        }
    }
}

public enum LogReader {
    public static func read(fileURL: URL) throws -> [LogEntry] {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try data.split(separator: 0x0A).map { try decoder.decode(LogEntry.self, from: Data($0)) }
    }
}
