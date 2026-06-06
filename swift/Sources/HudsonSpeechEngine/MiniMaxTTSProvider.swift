import Foundation
import VoxCore

public actor MiniMaxTTSProvider: TTSProvider {
    public static let providerID = "minimax"
    public static let supportedModelIDs = [
        "speech-2.8-hd",
        "speech-2.8-turbo",
        "speech-2.6-hd",
        "speech-2.6-turbo",
        "speech-02-hd",
        "speech-02-turbo",
        "speech-01-hd",
        "speech-01-turbo"
    ]
    public static let defaultVoiceID = "English_expressive_narrator"
    public static let defaultVoices: [(id: String, name: String, language: String)] = [
        ("English_expressive_narrator", "Expressive Narrator", "en"),
        ("English_radiant_girl", "Radiant Girl", "en"),
        ("English_magnetic_voiced_man", "Magnetic-voiced Male", "en"),
        ("English_compelling_lady1", "Compelling Lady", "en"),
        ("English_CalmWoman", "Calm Woman", "en")
    ]

    private static let defaultBaseURL = "https://api.minimax.io/v1"

    private let log = VoxLog.engine
    private let session: URLSession
    private let apiKey: String?
    private let baseURL: URL
    private var preloadedModels: Set<String> = []

    public init(env: [String: String]? = nil, session: URLSession = .shared) {
        self.session = session
        self.apiKey = env?["MINIMAX_API_KEY"]
            ?? ProcessInfo.processInfo.environment["MINIMAX_API_KEY"]
        let rawBaseURL = env?["MINIMAX_BASE_URL"]
            ?? ProcessInfo.processInfo.environment["MINIMAX_BASE_URL"]
            ?? Self.defaultBaseURL
        self.baseURL = URL(string: rawBaseURL) ?? URL(string: Self.defaultBaseURL)!
    }

    public func models() async -> [TTSModelInfo] {
        let available = apiKeyAvailability()
        return Self.supportedModelIDs.map { modelId in
            TTSModelInfo(
                id: modelId,
                name: modelId,
                backend: Self.providerID,
                installed: available,
                preloaded: preloadedModels.contains(modelId),
                available: available
            )
        }
    }

    public func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        let resolvedModelId = modelId ?? Self.supportedModelIDs[0]
        try validate(modelId: resolvedModelId)
        let available = apiKeyAvailability()

        return Self.defaultVoices.map { voice in
            TTSVoiceInfo(
                id: voice.id,
                name: voice.name,
                language: voice.language,
                backend: Self.providerID,
                modelId: resolvedModelId,
                available: available,
                isDefault: voice.id == Self.defaultVoiceID
            )
        }
    }

    public func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        try validate(modelId: modelId)
        _ = try resolveAPIKey()
        progress(ModelProgress(modelId: modelId, progress: 0.2, status: "starting"))
        preloadedModels.insert(modelId)
        progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        return (await models()).first(where: { $0.id == modelId }) ?? TTSModelInfo(
            id: modelId,
            name: modelId,
            backend: Self.providerID,
            installed: true,
            preloaded: true,
            available: true
        )
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        try validate(modelId: request.modelId)
        try validate(format: request.format)
        guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MiniMaxTTSProviderError.missingText
        }

        let trace = TranscriptionTrace()

        trace.begin("model_check")
        let apiKey = try resolveAPIKey()
        let wasPreloaded = preloadedModels.contains(request.modelId)
        trace.end(wasPreloaded ? "ready" : "cold")

        if !wasPreloaded {
            trace.begin("model_load")
            preloadedModels.insert(request.modelId)
            trace.end("prepared")
        }

        trace.begin("voice_resolve")
        let resolvedVoice = request.voiceId ?? Self.defaultVoiceID
        trace.end(resolvedVoice)

        trace.begin("inference")
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("t2a_v2"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": request.modelId,
            "text": request.text,
            "stream": false,
            "language_boost": "auto",
            "output_format": "hex",
            "voice_setting": [
                "voice_id": resolvedVoice,
                "speed": request.speed ?? 1.0,
                "vol": 1.0,
                "pitch": 0
            ],
            "audio_setting": [
                "sample_rate": 32000,
                "bitrate": 128000,
                "format": TTSDefaults.format,
                "channel": 1
            ]
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await session.data(for: urlRequest)
        try validateHTTPResponse(data: data, response: response)
        let synthesisMs = trace.end("\(data.count) response bytes")

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MiniMaxTTSProviderError.invalidResponse("synthesize")
        }

        if let baseResponse = object["base_resp"] as? [String: Any],
           let statusCode = baseResponse["status_code"] as? Int,
           statusCode != 0 {
            let message = (baseResponse["status_msg"] as? String) ?? "status_code \(statusCode)"
            throw MiniMaxTTSProviderError.requestFailed(message)
        }

        guard let dataObject = object["data"] as? [String: Any],
              let audioHex = dataObject["audio"] as? String,
              let audioData = Data(hexEncoded: audioHex) else {
            throw MiniMaxTTSProviderError.invalidResponse("synthesize.audio")
        }

        let extraInfo = object["extra_info"] as? [String: Any]
        let audioDurationMs = (extraInfo?["audio_length"] as? Int) ?? 0
        let outputBytes = (extraInfo?["audio_size"] as? Int) ?? audioData.count
        let traceId = (object["trace_id"] as? String) ?? trace.traceId

        let metrics = SynthesisMetrics(
            traceId: traceId,
            characterCount: (extraInfo?["usage_characters"] as? Int) ?? request.text.count,
            audioDurationMs: audioDurationMs,
            outputBytes: outputBytes,
            wasPreloaded: wasPreloaded,
            modelCheckMs: trace.durationMs(for: "model_check"),
            modelLoadMs: trace.durationMs(for: "model_load"),
            voiceResolveMs: trace.durationMs(for: "voice_resolve"),
            synthesisMs: synthesisMs,
            totalMs: trace.elapsedMs
        )

        log.info("MiniMax synthesis trace complete \(trace.summary)")
        return SynthesisOutput(
            modelId: request.modelId,
            voiceId: resolvedVoice,
            format: request.format.lowercased(),
            contentType: "audio/wav",
            audioData: audioData,
            elapsedMs: metrics.totalMs,
            metrics: metrics
        )
    }

    private func apiKeyAvailability() -> Bool {
        guard let apiKey else { return false }
        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resolveAPIKey() throws -> String {
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MiniMaxTTSProviderError.missingAPIKey
        }
        return apiKey
    }

    private func validate(modelId: String) throws {
        guard Self.supportedModelIDs.contains(modelId) else {
            throw MiniMaxTTSProviderError.unsupportedModel(modelId)
        }
    }

    private func validate(format: String) throws {
        guard format.lowercased() == TTSDefaults.format else {
            throw MiniMaxTTSProviderError.unsupportedFormat(format)
        }
    }

    private func validateHTTPResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MiniMaxTTSProviderError.nonHTTPResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw MiniMaxTTSProviderError.requestFailed(message)
        }
    }
}

public enum MiniMaxTTSProviderError: Error, LocalizedError {
    case missingText
    case missingAPIKey
    case unsupportedModel(String)
    case unsupportedFormat(String)
    case nonHTTPResponse
    case requestFailed(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingText:
            return "Missing text"
        case .missingAPIKey:
            return "Missing MINIMAX_API_KEY for MiniMax TTS provider."
        case .unsupportedModel(let modelId):
            return "Unsupported MiniMax TTS model: \(modelId)"
        case .unsupportedFormat(let format):
            return "Unsupported synthesis format: \(format). MiniMax TTS is currently configured for wav output."
        case .nonHTTPResponse:
            return "MiniMax TTS request returned a non-HTTP response."
        case .requestFailed(let message):
            return "MiniMax TTS request failed: \(message)"
        case .invalidResponse(let method):
            return "Invalid MiniMax TTS response for \(method)."
        }
    }
}

private extension Data {
    init?(hexEncoded string: String) {
        let hex = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count.isMultiple(of: 2) else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)

        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        self.init(bytes)
    }
}
