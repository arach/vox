import Foundation
import VoxCore

public actor OpenAIASRProvider: ASRProvider {
    public static let providerID = "openai-transcribe"
    public static let fallbackModelIDs = [
        "gpt-transcribe",
        "gpt-4o-transcribe",
        "gpt-4o-mini-transcribe",
        "whisper-1"
    ]
    static let defaultRequestTimeout: TimeInterval = 30
    static let maximumRequestTimeout: TimeInterval = 120
    static let defaultBaseURL = "https://api.openai.com/v1"

    private let log = VoxLog.engine
    private let session: URLSession
    private let apiKey: String?
    private let baseURL: URL
    private let requestTimeout: TimeInterval
    private let catalogStore: ModelCatalogStore
    private var preloadedModels: Set<String> = []

    public init(
        env: [String: String]? = nil,
        session: URLSession = .shared,
        catalogStore: ModelCatalogStore = .shared
    ) {
        self.session = session
        self.catalogStore = catalogStore
        self.apiKey = env?["OPENAI_API_KEY"]
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let rawBaseURL = env?["OPENAI_BASE_URL"]
            ?? ProcessInfo.processInfo.environment["OPENAI_BASE_URL"]
            ?? Self.defaultBaseURL
        self.baseURL = URL(string: rawBaseURL) ?? URL(string: Self.defaultBaseURL)!
        self.requestTimeout = Self.resolveRequestTimeout(env: env)
    }

    public func models() async -> [ASRModelInfo] {
        let available = apiKeyAvailability()
        return supportedModelIDs().map { modelId in
            ASRModelInfo(
                id: modelId,
                name: modelId,
                backend: "openai",
                installed: available,
                preloaded: preloadedModels.contains(modelId),
                available: available
            )
        }
    }

    public func install(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try await preload(modelId: modelId, progress: progress)
    }

    public func preload(
        modelId: String,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> ASRModelInfo {
        try validate(modelId: modelId)
        _ = try resolveAPIKey()
        progress(ModelProgress(modelId: modelId, progress: 0.2, status: "starting"))
        preloadedModels.insert(modelId)
        progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        return ASRModelInfo(
            id: modelId,
            name: modelId,
            backend: "openai",
            installed: true,
            preloaded: true,
            available: true
        )
    }

    public func transcribe(url: URL, modelId: String) async throws -> TranscriptionOutput {
        try validate(modelId: modelId)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw NSError(domain: "VoxEngine", code: 5201, userInfo: [
                NSLocalizedDescriptionKey: "Audio file is not readable at \(url.path)"
            ])
        }

        let trace = TranscriptionTrace()
        trace.begin("file_check")
        let audioData = try Data(contentsOf: url)
        let inputBytes = audioData.count
        trace.end("\(inputBytes) bytes")

        trace.begin("model_check")
        let apiKey = try resolveAPIKey()
        let wasPreloaded = preloadedModels.contains(modelId)
        trace.end(wasPreloaded ? "ready" : "cold")

        if !wasPreloaded {
            trace.begin("model_load")
            preloadedModels.insert(modelId)
            trace.end("prepared")
        }

        trace.begin("inference")
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        urlRequest.timeoutInterval = requestTimeout
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "VoxOpenAIASR-\(UUID().uuidString)"
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = Self.multipartBody(
            boundary: boundary,
            modelId: modelId,
            fileName: url.lastPathComponent,
            fileData: audioData
        )

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "VoxEngine", code: 5202, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI transcription returned a non-HTTP response."
            ])
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "VoxEngine", code: 5203, userInfo: [
                NSLocalizedDescriptionKey: "OpenAI transcription failed: \(message)"
            ])
        }

        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let text = (payload?["text"] as? String) ?? ""
        let inferenceMs = trace.end("\(text.count) chars")

        let metrics = TranscriptionMetrics(
            traceId: trace.traceId,
            audioDurationMs: 0,
            inputBytes: inputBytes,
            wasPreloaded: wasPreloaded,
            fileCheckMs: trace.durationMs(for: "file_check"),
            modelCheckMs: trace.durationMs(for: "model_check"),
            modelLoadMs: trace.durationMs(for: "model_load"),
            audioLoadMs: 0,
            audioPrepareMs: 0,
            inferenceMs: inferenceMs,
            totalMs: trace.elapsedMs
        )

        log.info("OpenAI transcription trace complete \(trace.summary)")
        return TranscriptionOutput(
            modelId: modelId,
            text: text,
            elapsedMs: metrics.totalMs,
            metrics: metrics,
            words: []
        )
    }

    func supportedModelIDs() -> [String] {
        let catalogIDs = catalogStore.openaiTranscribeModelIDs()
        return catalogIDs.isEmpty ? Self.fallbackModelIDs : catalogIDs
    }

    static func resolveRequestTimeout(
        env: [String: String]?,
        processEnv: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        let rawValue = env?["VOX_OPENAI_ASR_TIMEOUT_SECONDS"]
            ?? env?["OPENAI_ASR_TIMEOUT_SECONDS"]
            ?? processEnv["VOX_OPENAI_ASR_TIMEOUT_SECONDS"]
            ?? processEnv["OPENAI_ASR_TIMEOUT_SECONDS"]
        guard
            let rawValue,
            let parsed = TimeInterval(rawValue),
            parsed > 0
        else {
            return defaultRequestTimeout
        }
        return min(parsed, maximumRequestTimeout)
    }

    static func multipartBody(boundary: String, modelId: String, fileName: String, fileData: Data) -> Data {
        var body = Data()
        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("\(modelId)\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func apiKeyAvailability() -> Bool {
        guard let apiKey = apiKey ?? VoxCredentialStore().openAIAPIKey() else { return false }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resolveAPIKey() throws -> String {
        let resolvedKey = apiKey ?? VoxCredentialStore().openAIAPIKey()
        guard let resolvedKey, !resolvedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "VoxEngine", code: 5204, userInfo: [
                NSLocalizedDescriptionKey: "Missing OPENAI_API_KEY for OpenAI transcription provider."
            ])
        }
        return resolvedKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(modelId: String) throws {
        guard supportedModelIDs().contains(modelId) else {
            throw NSError(domain: "VoxEngine", code: 5205, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported OpenAI transcription model: \(modelId)"
            ])
        }
    }
}
