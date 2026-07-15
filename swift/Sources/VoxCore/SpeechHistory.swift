import Foundation

public enum SpeechHistoryKind: String, Codable, Sendable, Equatable {
    case transcription
    case synthesis
}

public enum SpeechHistorySource: String, Codable, Sendable, Equatable {
    case file
    case live
}

public struct SpeechHistoryRecord: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let id: String
    public let kind: SpeechHistoryKind
    public let source: SpeechHistorySource?
    public let route: String
    public let sessionId: String?
    public let requestId: String?
    public let clientId: String
    public let originAppId: String?
    public let modelId: String
    public let voiceId: String?
    public let text: String?
    public let textLength: Int
    public let words: [WordTiming]?
    public let elapsedMs: Int
    public let metrics: PerformanceMetrics?
    public let outcome: String
    public let error: String?
    public let startedAt: Date?
    public let completedAt: Date
    public let metadata: [String: String]?

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        kind: SpeechHistoryKind,
        source: SpeechHistorySource? = nil,
        route: String,
        sessionId: String? = nil,
        requestId: String? = nil,
        clientId: String,
        originAppId: String? = nil,
        modelId: String,
        voiceId: String? = nil,
        text: String? = nil,
        textLength: Int,
        words: [WordTiming]? = nil,
        elapsedMs: Int,
        metrics: PerformanceMetrics? = nil,
        outcome: String,
        error: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.source = source
        self.route = route
        self.sessionId = sessionId
        self.requestId = requestId
        self.clientId = clientId
        self.originAppId = originAppId
        self.modelId = modelId
        self.voiceId = voiceId
        self.text = text
        self.textLength = textLength
        self.words = words
        self.elapsedMs = elapsedMs
        self.metrics = metrics
        self.outcome = outcome
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.metadata = metadata
    }

    public static func transcription(
        source: SpeechHistorySource,
        route: String,
        sessionId: String? = nil,
        clientId: String,
        modelId: String,
        output: TranscriptionOutput,
        startedAt: Date? = nil,
        completedAt: Date = Date()
    ) -> SpeechHistoryRecord {
        SpeechHistoryRecord(
            kind: .transcription,
            source: source,
            route: route,
            sessionId: sessionId,
            clientId: clientId,
            modelId: modelId,
            text: output.text,
            textLength: output.text.count,
            words: output.words,
            elapsedMs: output.elapsedMs,
            metrics: output.metrics.performanceMetrics,
            outcome: "ok",
            startedAt: startedAt,
            completedAt: completedAt
        )
    }

    public func dictionaryValue() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "schemaVersion": schemaVersion,
            "id": id,
            "kind": kind.rawValue,
            "route": route,
            "clientId": clientId,
            "modelId": modelId,
            "textLength": textLength,
            "elapsedMs": elapsedMs,
            "outcome": outcome,
            "completedAt": formatter.string(from: completedAt)
        ]

        if let source {
            payload["source"] = source.rawValue
        }
        if let sessionId {
            payload["sessionId"] = sessionId
        }
        if let requestId {
            payload["requestId"] = requestId
        }
        if let originAppId {
            payload["originAppId"] = originAppId
        }
        if let voiceId {
            payload["voiceId"] = voiceId
        }
        if let text {
            payload["text"] = text
        }
        if let words {
            payload["words"] = words.map { $0.dictionaryValue() }
        }
        if let metrics {
            payload["metrics"] = metrics.dictionaryValue()
        }
        if let error {
            payload["error"] = error
        }
        if let startedAt {
            payload["startedAt"] = formatter.string(from: startedAt)
        }
        if let metadata {
            payload["metadata"] = metadata
        }

        return payload
    }
}

public struct SpeechHistoryListFilter: Sendable, Equatable {
    public let kind: SpeechHistoryKind?
    public let source: SpeechHistorySource?
    public let clientId: String?
    public let modelId: String?
    public let sessionId: String?
    public let outcome: String?
    public let query: String?
    public let before: String?
    public let limit: Int

    public init(
        kind: SpeechHistoryKind? = nil,
        source: SpeechHistorySource? = nil,
        clientId: String? = nil,
        modelId: String? = nil,
        sessionId: String? = nil,
        outcome: String? = nil,
        query: String? = nil,
        before: String? = nil,
        limit: Int = 50
    ) {
        self.kind = kind
        self.source = source
        self.clientId = clientId
        self.modelId = modelId
        self.sessionId = sessionId
        self.outcome = outcome
        self.query = query
        self.before = before
        self.limit = max(1, min(limit, 500))
    }
}

public actor SpeechHistoryRecorder {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL = RuntimePaths.historyLogURL()) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func record(_ record: SpeechHistoryRecord) async {
        do {
            try append(record)
        } catch {
            VoxLog.core.error("Failed to write speech history record: \(error.localizedDescription)")
        }
    }

    public func append(_ record: SpeechHistoryRecord) throws {
        try RuntimePaths.ensureDirectories()
        let data = try encoder.encode(record) + Data([0x0a])

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL, options: .atomic)
        }
    }

    public func list(filter: SpeechHistoryListFilter = SpeechHistoryListFilter()) throws -> [SpeechHistoryRecord] {
        let records = try readAll()
        let filtered = records
            .filter { record in matches(record, filter: filter) }
            .sorted { $0.completedAt > $1.completedAt }
        return Array(filtered.prefix(filter.limit))
    }

    public func get(id: String) throws -> SpeechHistoryRecord? {
        try readAll().first { $0.id == id }
    }

    public func delete(id: String) throws -> Bool {
        let records = try readAll()
        let kept = records.filter { $0.id != id }
        guard kept.count != records.count else { return false }
        try writeAll(kept)
        return true
    }

    public func clear(filter: SpeechHistoryListFilter = SpeechHistoryListFilter(limit: 500)) throws -> Int {
        let records = try readAll()
        let kept = records.filter { !matches($0, filter: filter, applyLimitAndCursor: false) }
        let deleted = records.count - kept.count
        if deleted > 0 {
            try writeAll(kept)
        }
        return deleted
    }

    private func readAll() throws -> [SpeechHistoryRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return try text
            .split(separator: "\n")
            .map { line in
                guard let lineData = String(line).data(using: .utf8) else {
                    throw NSError(domain: "VoxCore", code: 3001, userInfo: [
                        NSLocalizedDescriptionKey: "Invalid speech history line encoding."
                    ])
                }
                return try decoder.decode(SpeechHistoryRecord.self, from: lineData)
            }
    }

    private func writeAll(_ records: [SpeechHistoryRecord]) throws {
        try RuntimePaths.ensureDirectories()
        let lines = try records.map { record in
            String(data: try encoder.encode(record), encoding: .utf8) ?? "{}"
        }
        let data = Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8)
        try data.write(to: fileURL, options: .atomic)
    }

    private func matches(
        _ record: SpeechHistoryRecord,
        filter: SpeechHistoryListFilter,
        applyLimitAndCursor: Bool = true
    ) -> Bool {
        if let kind = filter.kind, record.kind != kind { return false }
        if let source = filter.source, record.source != source { return false }
        if let clientId = filter.clientId, record.clientId != clientId { return false }
        if let modelId = filter.modelId, record.modelId != modelId { return false }
        if let sessionId = filter.sessionId, record.sessionId != sessionId { return false }
        if let outcome = filter.outcome, record.outcome != outcome { return false }
        if let query = filter.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            guard record.text?.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
                return false
            }
        }
        if applyLimitAndCursor, let before = filter.before, !before.isEmpty {
            if record.id == before { return false }
            if let beforeDate = ISO8601DateFormatter().date(from: before) {
                return record.completedAt < beforeDate
            }
        }
        return true
    }
}
