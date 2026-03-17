import AVFoundation
import Foundation

public struct RuntimeInfo: Codable, Sendable, Equatable {
    public let version: String
    public let serviceName: String
    public let port: UInt16
    public let pid: Int32
    public let startedAt: Date

    public init(version: String, serviceName: String, port: UInt16, pid: Int32, startedAt: Date) {
        self.version = version
        self.serviceName = serviceName
        self.port = port
        self.pid = pid
        self.startedAt = startedAt
    }

    public func dictionaryValue() -> [String: Any] {
        [
            "version": version,
            "serviceName": serviceName,
            "port": Int(port),
            "pid": Int(pid),
            "startedAt": ISO8601DateFormatter().string(from: startedAt)
        ]
    }
}

public enum RuntimeRegistry {
    public static func read() throws -> RuntimeInfo? {
        let url = RuntimePaths.runtimeFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RuntimeInfo.self, from: data)
    }

    public static func write(_ runtime: RuntimeInfo) throws {
        try RuntimePaths.ensureDirectories()
        let data = try JSONEncoder().encode(runtime)
        try data.write(to: RuntimePaths.runtimeFileURL(), options: .atomic)
    }

    public static func remove() throws {
        let url = RuntimePaths.runtimeFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

public struct DoctorCheck: Codable, Sendable, Equatable {
    public let name: String
    public let status: String
    public let detail: String

    public init(name: String, status: String, detail: String) {
        self.name = name
        self.status = status
        self.detail = detail
    }

    public func dictionaryValue() -> [String: Any] {
        [
            "name": name,
            "status": status,
            "detail": detail
        ]
    }
}

public struct DoctorReport: Codable, Sendable, Equatable {
    public let ready: Bool
    public let checks: [DoctorCheck]

    public init(ready: Bool, checks: [DoctorCheck]) {
        self.ready = ready
        self.checks = checks
    }

    public func dictionaryValue() -> [String: Any] {
        [
            "ready": ready,
            "checks": checks.map { $0.dictionaryValue() }
        ]
    }
}

public struct ASRModelInfo: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let backend: String
    public let installed: Bool
    public let preloaded: Bool
    public let available: Bool

    public init(id: String, name: String, backend: String, installed: Bool, preloaded: Bool, available: Bool) {
        self.id = id
        self.name = name
        self.backend = backend
        self.installed = installed
        self.preloaded = preloaded
        self.available = available
    }

    public func dictionaryValue() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "backend": backend,
            "installed": installed,
            "preloaded": preloaded,
            "available": available
        ]
    }
}

public struct ModelProgress: Sendable, Equatable {
    public let modelId: String
    public let progress: Double
    public let status: String

    public init(modelId: String, progress: Double, status: String) {
        self.modelId = modelId
        self.progress = progress
        self.status = status
    }

    public func dictionaryValue() -> [String: Any] {
        [
            "modelId": modelId,
            "progress": progress,
            "status": status
        ]
    }
}

public struct WarmupStatus: Codable, Sendable, Equatable {
    public let modelId: String
    public let state: String
    public let requestedBy: String?
    public let scheduledFor: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    public let lastError: String?

    public init(
        modelId: String,
        state: String,
        requestedBy: String? = nil,
        scheduledFor: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.modelId = modelId
        self.state = state
        self.requestedBy = requestedBy
        self.scheduledFor = scheduledFor
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.lastError = lastError
    }

    public func dictionaryValue() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        return [
            "modelId": modelId,
            "state": state,
            "requestedBy": requestedBy ?? NSNull(),
            "scheduledFor": scheduledFor.map { formatter.string(from: $0) } ?? NSNull(),
            "startedAt": startedAt.map { formatter.string(from: $0) } ?? NSNull(),
            "completedAt": completedAt.map { formatter.string(from: $0) } ?? NSNull(),
            "lastError": lastError ?? NSNull()
        ]
    }
}

public struct TranscriptionOutput: Sendable, Equatable {
    public let modelId: String
    public let text: String
    public let elapsedMs: Int
    public let metrics: TranscriptionMetrics

    public init(modelId: String, text: String, elapsedMs: Int, metrics: TranscriptionMetrics) {
        self.modelId = modelId
        self.text = text
        self.elapsedMs = elapsedMs
        self.metrics = metrics
    }

    public func dictionaryValue() -> [String: Any] {
        [
            "modelId": modelId,
            "text": text,
            "elapsedMs": elapsedMs,
            "metrics": metrics.dictionaryValue()
        ]
    }
}

public struct TranscriptionMetrics: Codable, Sendable, Equatable {
    public let traceId: String
    public let audioDurationMs: Int
    public let inputBytes: Int
    public let wasPreloaded: Bool
    public let fileCheckMs: Int
    public let modelCheckMs: Int
    public let modelLoadMs: Int
    public let audioLoadMs: Int
    public let audioPrepareMs: Int
    public let inferenceMs: Int
    public let totalMs: Int

    public init(
        traceId: String,
        audioDurationMs: Int,
        inputBytes: Int,
        wasPreloaded: Bool,
        fileCheckMs: Int,
        modelCheckMs: Int,
        modelLoadMs: Int,
        audioLoadMs: Int,
        audioPrepareMs: Int,
        inferenceMs: Int,
        totalMs: Int
    ) {
        self.traceId = traceId
        self.audioDurationMs = audioDurationMs
        self.inputBytes = inputBytes
        self.wasPreloaded = wasPreloaded
        self.fileCheckMs = fileCheckMs
        self.modelCheckMs = modelCheckMs
        self.modelLoadMs = modelLoadMs
        self.audioLoadMs = audioLoadMs
        self.audioPrepareMs = audioPrepareMs
        self.inferenceMs = inferenceMs
        self.totalMs = totalMs
    }

    public var realtimeFactor: Double {
        guard audioDurationMs > 0 else { return 0 }
        return Double(inferenceMs) / Double(audioDurationMs)
    }

    private enum CodingKeys: String, CodingKey {
        case traceId
        case audioDurationMs
        case inputBytes
        case wasPreloaded
        case fileCheckMs
        case modelCheckMs
        case modelLoadMs
        case audioLoadMs
        case audioPrepareMs
        case inferenceMs
        case totalMs
        case realtimeFactor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        traceId = try container.decode(String.self, forKey: .traceId)
        audioDurationMs = try container.decode(Int.self, forKey: .audioDurationMs)
        inputBytes = try container.decode(Int.self, forKey: .inputBytes)
        wasPreloaded = try container.decode(Bool.self, forKey: .wasPreloaded)
        fileCheckMs = try container.decode(Int.self, forKey: .fileCheckMs)
        modelCheckMs = try container.decode(Int.self, forKey: .modelCheckMs)
        modelLoadMs = try container.decode(Int.self, forKey: .modelLoadMs)
        audioLoadMs = try container.decode(Int.self, forKey: .audioLoadMs)
        audioPrepareMs = try container.decode(Int.self, forKey: .audioPrepareMs)
        inferenceMs = try container.decode(Int.self, forKey: .inferenceMs)
        totalMs = try container.decode(Int.self, forKey: .totalMs)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(traceId, forKey: .traceId)
        try container.encode(audioDurationMs, forKey: .audioDurationMs)
        try container.encode(inputBytes, forKey: .inputBytes)
        try container.encode(wasPreloaded, forKey: .wasPreloaded)
        try container.encode(fileCheckMs, forKey: .fileCheckMs)
        try container.encode(modelCheckMs, forKey: .modelCheckMs)
        try container.encode(modelLoadMs, forKey: .modelLoadMs)
        try container.encode(audioLoadMs, forKey: .audioLoadMs)
        try container.encode(audioPrepareMs, forKey: .audioPrepareMs)
        try container.encode(inferenceMs, forKey: .inferenceMs)
        try container.encode(totalMs, forKey: .totalMs)
        try container.encode(realtimeFactor, forKey: .realtimeFactor)
    }

    public func dictionaryValue() -> [String: Any] {
        [
            "traceId": traceId,
            "audioDurationMs": audioDurationMs,
            "inputBytes": inputBytes,
            "wasPreloaded": wasPreloaded,
            "fileCheckMs": fileCheckMs,
            "modelCheckMs": modelCheckMs,
            "modelLoadMs": modelLoadMs,
            "audioLoadMs": audioLoadMs,
            "audioPrepareMs": audioPrepareMs,
            "inferenceMs": inferenceMs,
            "totalMs": totalMs,
            "realtimeFactor": realtimeFactor
        ]
    }
}

public struct PerformanceSample: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let clientId: String
    public let route: String
    public let modelId: String
    public let outcome: String
    public let textLength: Int
    public let error: String?
    public let metrics: TranscriptionMetrics?

    public init(
        timestamp: Date = Date(),
        clientId: String,
        route: String,
        modelId: String,
        outcome: String,
        textLength: Int,
        error: String? = nil,
        metrics: TranscriptionMetrics? = nil
    ) {
        self.timestamp = timestamp
        self.clientId = clientId
        self.route = route
        self.modelId = modelId
        self.outcome = outcome
        self.textLength = textLength
        self.error = error
        self.metrics = metrics
    }
}

public enum SessionState: String, Sendable {
    case starting
    case recording
    case processing
    case done
    case cancelled
    case error
}

public enum MicrophonePermission {
    public static func statusString() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unknown"
        }
    }
}
