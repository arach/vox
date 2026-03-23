import Foundation
import os

private enum VoxLogFileSink {
    private static let queue = DispatchQueue(label: "dev.vox.log-file")

    static func append(_ line: String) {
        queue.sync {
            do {
                try RuntimePaths.ensureDirectories()
                let url = RuntimePaths.daemonLogURL()
                let data = Data(line.utf8)

                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forWritingTo: url)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: url, options: .atomic)
                }
            } catch {
                // Best effort: logging should never break the runtime.
            }
        }
    }
}

public struct DualLogger: Sendable {
    private let osLogger: Logger
    private let category: String

    public init(subsystem: String, category: String) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    public func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        emit("DEBUG", message)
    }

    public func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        emit("INFO", message)
    }

    public func notice(_ message: String) {
        osLogger.notice("\(message, privacy: .public)")
        emit("NOTE", message)
    }

    public func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        emit("WARN", message)
    }

    public func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        emit("ERROR", message)
    }

    public func fault(_ message: String) {
        osLogger.fault("\(message, privacy: .public)")
        emit("FAULT", message)
    }

    private func emit(_ level: String, _ message: String) {
        var buf = [UInt8](repeating: 0, count: 32)
        var t = time(nil)
        var tm = tm()
        gmtime_r(&t, &tm)
        let len = strftime(&buf, buf.count, "%Y-%m-%dT%H:%M:%SZ", &tm)
        let ts = String(bytes: buf[..<len], encoding: .utf8) ?? "-"
        let line = "[\(ts)] [\(category)] \(level): \(message)\n"
        fputs(line, stderr)
        VoxLogFileSink.append(line)
    }
}

public enum VoxLog {
    private static let subsystem = "dev.vox"

    public static let core = DualLogger(subsystem: subsystem, category: "core")
    public static let engine = DualLogger(subsystem: subsystem, category: "engine")
    public static let service = DualLogger(subsystem: subsystem, category: "service")
    public static let audio = DualLogger(subsystem: subsystem, category: "audio")
    public static let daemon = DualLogger(subsystem: subsystem, category: "daemon")
}
