import AVFoundation
import Foundation
import VoxCore

public actor GeminiTTSProvider: TTSProvider {
    public static let providerID = "gemini"
    public static let defaultModelID = "gemini-2.5-flash-preview-tts"
    public static let supportedModelIDs = [
        "gemini-2.5-flash-preview-tts",
        "gemini-2.5-pro-preview-tts",
        "gemini-3.1-flash-tts-preview"
    ]
    public static let defaultVoiceID = "Puck"
    static let defaultRequestTimeout: TimeInterval = 12
    static let maximumRequestTimeout: TimeInterval = 30
    static let defaultBaseURL = "https://generativelanguage.googleapis.com/v1beta"

    public static let supportedVoices = [
        "Zephyr",
        "Puck",
        "Charon",
        "Kore",
        "Fenrir",
        "Leda",
        "Orus",
        "Aoede",
        "Callirrhoe",
        "Autonoe",
        "Enceladus",
        "Iapetus",
        "Umbriel",
        "Algieba",
        "Despina",
        "Erinome",
        "Algenib",
        "Rasalgethi",
        "Laomedeia",
        "Achernar",
        "Alnilam",
        "Schedar",
        "Gacrux",
        "Pulcherrima",
        "Achird",
        "Zubenelgenubi",
        "Vindemiatrix",
        "Sadachbia",
        "Sadaltager",
        "Sulafat"
    ]

    private let log = VoxLog.engine
    private let session: URLSession
    private let apiKey: String?
    private let baseURL: URL
    private let requestTimeout: TimeInterval
    private var preloadedModels: Set<String> = []

    public init(env: [String: String]? = nil, session: URLSession = .shared) {
        let processEnv = ProcessInfo.processInfo.environment
        self.session = session
        self.apiKey = Self.resolveConfiguredAPIKey(env: env, processEnv: processEnv)
        let rawBaseURL = RemoteTTSSupport.firstNonEmpty(
            env?["GEMINI_BASE_URL"],
            env?["GOOGLE_GENAI_BASE_URL"],
            processEnv["GEMINI_BASE_URL"],
            processEnv["GOOGLE_GENAI_BASE_URL"]
        ) ?? Self.defaultBaseURL
        self.baseURL = URL(string: rawBaseURL) ?? URL(string: Self.defaultBaseURL)!
        self.requestTimeout = Self.resolveRequestTimeout(env: env, processEnv: processEnv)
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
        let resolvedModelId = modelId ?? Self.defaultModelID
        try validate(modelId: resolvedModelId)
        let available = apiKeyAvailability()
        return Self.supportedVoices.map { voiceId in
            TTSVoiceInfo(
                id: voiceId,
                name: voiceId,
                language: nil,
                backend: Self.providerID,
                modelId: resolvedModelId,
                available: available,
                isDefault: voiceId == Self.defaultVoiceID
            )
        }
    }

    public func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        try validate(modelId: modelId)
        _ = try resolveAPIKey(providerCredentials: [:])
        if let voiceId {
            _ = try resolveVoice(voiceId: voiceId)
        }
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

        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw GeminiTTSProviderError.missingText
        }

        let trace = TranscriptionTrace()

        trace.begin("model_check")
        let apiKey = try resolveAPIKey(providerCredentials: request.providerCredentials)
        let wasPreloaded = preloadedModels.contains(request.modelId)
        trace.end(wasPreloaded ? "ready" : "cold")

        if !wasPreloaded {
            trace.begin("model_load")
            preloadedModels.insert(request.modelId)
            trace.end("prepared")
        }

        trace.begin("voice_resolve")
        let resolvedVoice = try resolveVoice(voiceId: request.voiceId)
        trace.end(resolvedVoice)

        let prompt = request.instructions?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .map { "\($0)\n\n\(text)" }
            ?? text

        trace.begin("inference")
        guard let endpoint = Self.generateContentURL(baseURL: baseURL, modelId: request.modelId) else {
            throw GeminiTTSProviderError.invalidURL
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = requestTimeout
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": ["voiceName": resolvedVoice]
                    ]
                ]
            ]
        ], options: [])

        log.info("Gemini synthesis request started requestId=\(request.requestId) modelId=\(request.modelId) voiceId=\(resolvedVoice) textLength=\(text.count)")
        let (data, response) = try await RemoteTTSSupport.data(for: urlRequest, session: session)
        _ = try validateHTTPResponse(
            data: data,
            response: response,
            sensitiveValues: [text, prompt, request.instructions].compactMap { $0 }
        )

        let audio = try Self.parseAudio(from: data)
        let synthesisMs = trace.end("\(audio.count) bytes")
        let audioDurationMs = (try? inspectWaveData(audio)) ?? 0
        let metrics = SynthesisMetrics(
            traceId: trace.traceId,
            characterCount: text.count,
            audioDurationMs: audioDurationMs,
            outputBytes: audio.count,
            wasPreloaded: wasPreloaded,
            modelCheckMs: trace.durationMs(for: "model_check"),
            modelLoadMs: trace.durationMs(for: "model_load"),
            voiceResolveMs: trace.durationMs(for: "voice_resolve"),
            synthesisMs: synthesisMs,
            totalMs: trace.elapsedMs
        )

        log.info("Gemini synthesis trace complete \(trace.summary)")
        return SynthesisOutput(
            modelId: request.modelId,
            voiceId: resolvedVoice,
            format: request.format.lowercased(),
            contentType: "audio/wav",
            audioData: audio,
            elapsedMs: metrics.totalMs,
            metrics: metrics
        )
    }

    static func parseAudio(from data: Data) throws -> Data {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = object["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let inline = parts.compactMap({ $0["inlineData"] as? [String: Any] }).first,
            let mimeType = inline["mimeType"] as? String,
            let encodedAudio = inline["data"] as? String,
            let audio = Data(base64Encoded: encodedAudio),
            !audio.isEmpty
        else {
            throw GeminiTTSProviderError.unreadableAudio
        }

        let normalizedMIME = mimeType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedMIME.hasPrefix("audio/wav") || normalizedMIME.hasPrefix("audio/x-wav") {
            guard PCMWAV.isStructurallyValid(audio) else {
                throw GeminiTTSProviderError.unsupportedAudioFormat
            }
            return audio
        }
        return try pcmWAV(audio: audio, mimeType: mimeType)
    }

    static func pcmWAV(audio: Data, mimeType: String) throws -> Data {
        let normalizedMIME = mimeType.lowercased()
        guard normalizedMIME.hasPrefix("audio/l16"), !audio.isEmpty else {
            throw GeminiTTSProviderError.unsupportedAudioFormat
        }

        var parameters: [String: String] = [:]
        for component in mimeType.split(separator: ";").dropFirst() {
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let key = pair[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            parameters[key] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard
            let sampleRate = UInt32(parameters["rate"] ?? "24000"),
            let channelCount = UInt16(parameters["channels"] ?? "1")
        else {
            throw GeminiTTSProviderError.unsupportedAudioFormat
        }

        do {
            return try PCMWAV.wrap(
                pcm: audio,
                sampleRate: sampleRate,
                channelCount: channelCount
            )
        } catch {
            throw GeminiTTSProviderError.unsupportedAudioFormat
        }
    }

    static func generateContentURL(baseURL: URL, modelId: String) -> URL? {
        var pathAllowed = CharacterSet.urlPathAllowed
        pathAllowed.remove(charactersIn: "/")
        guard let encodedModel = modelId.addingPercentEncoding(withAllowedCharacters: pathAllowed) else {
            return nil
        }
        return RemoteTTSSupport.joiningURL(baseURL, path: "models/\(encodedModel):generateContent")
    }

    static func resolveAPIKey(
        providerCredentials: [String: String],
        env: [String: String]?,
        processEnv: [String: String]
    ) -> String? {
        RemoteTTSSupport.resolveSecret(
            lentValues: [
                providerCredentials["GEMINI_API_KEY"],
                providerCredentials["GOOGLE_API_KEY"],
                providerCredentials["GOOGLE_GENAI_API_KEY"],
                providerCredentials["geminiApiKey"],
                providerCredentials["googleApiKey"],
                providerCredentials["googleGenaiApiKey"],
                providerCredentials["gemini_api_key"],
                providerCredentials["google_api_key"],
                providerCredentials["google_genai_api_key"]
            ],
            env: env,
            processEnv: processEnv,
            keys: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENAI_API_KEY"]
        )
    }

    static func resolveConfiguredAPIKey(
        env: [String: String]?,
        processEnv: [String: String]
    ) -> String? {
        resolveAPIKey(providerCredentials: [:], env: env, processEnv: processEnv)
    }

    static func resolveRequestTimeout(
        env: [String: String]?,
        processEnv: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        let rawValue = env?["VOX_GEMINI_TTS_TIMEOUT_SECONDS"]
            ?? env?["GEMINI_TTS_TIMEOUT_SECONDS"]
            ?? processEnv["VOX_GEMINI_TTS_TIMEOUT_SECONDS"]
            ?? processEnv["GEMINI_TTS_TIMEOUT_SECONDS"]
        guard let rawValue, let parsed = TimeInterval(rawValue), parsed > 0 else {
            return defaultRequestTimeout
        }
        return min(parsed, maximumRequestTimeout)
    }

    private func apiKeyAvailability() -> Bool {
        guard let apiKey else { return false }
        return !apiKey.isEmpty
    }

    private func resolveAPIKey(providerCredentials: [String: String]) throws -> String {
        guard let key = Self.resolveAPIKey(
            providerCredentials: providerCredentials,
            env: apiKey.map { ["GEMINI_API_KEY": $0] },
            processEnv: [:]
        ) else {
            throw GeminiTTSProviderError.missingAPIKey
        }
        return key
    }

    private func validate(modelId: String) throws {
        guard Self.supportedModelIDs.contains(modelId) else {
            throw GeminiTTSProviderError.unsupportedModel(modelId)
        }
    }

    private func validate(format: String) throws {
        guard format.lowercased() == TTSDefaults.format else {
            throw GeminiTTSProviderError.unsupportedFormat(format)
        }
    }

    private func resolveVoice(voiceId: String?) throws -> String {
        let resolved = (voiceId ?? Self.defaultVoiceID).trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.supportedVoices.contains(where: { $0.caseInsensitiveCompare(resolved) == .orderedSame }) else {
            throw GeminiTTSProviderError.unsupportedVoice(voiceId ?? resolved)
        }
        return Self.supportedVoices.first { $0.caseInsensitiveCompare(resolved) == .orderedSame } ?? resolved
    }

    @discardableResult
    private func validateHTTPResponse(
        data: Data,
        response: URLResponse,
        sensitiveValues: [String] = []
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiTTSProviderError.nonHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GeminiTTSProviderError.requestFailed(
                status: httpResponse.statusCode,
                message: RemoteTTSSupport.sanitizeVendorMessage(
                    from: data,
                    vendor: "Gemini TTS",
                    sensitiveValues: sensitiveValues
                )
            )
        }
        return httpResponse
    }

    private func inspectWaveData(_ data: Data) throws -> Int {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-gemini-\(UUID().uuidString)")
            .appendingPathExtension(TTSDefaults.format)
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        return Int((Double(file.length) / file.processingFormat.sampleRate) * 1000)
    }
}

public enum GeminiTTSProviderError: Error, LocalizedError {
    case missingText
    case missingAPIKey
    case unsupportedModel(String)
    case unsupportedVoice(String)
    case unsupportedFormat(String)
    case invalidURL
    case unreadableAudio
    case unsupportedAudioFormat
    case nonHTTPResponse
    case requestFailed(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingText:
            return "Missing text"
        case .missingAPIKey:
            return "Missing GEMINI_API_KEY (or GOOGLE_API_KEY) for Gemini TTS provider."
        case .unsupportedModel(let modelId):
            return "Unsupported Gemini TTS model: \(modelId)"
        case .unsupportedVoice(let voiceId):
            return "Unsupported Gemini TTS voice: \(voiceId)"
        case .unsupportedFormat(let format):
            return "Unsupported synthesis format: \(format). Gemini TTS is currently configured for wav output."
        case .invalidURL:
            return "Could not build the Gemini TTS URL."
        case .unreadableAudio:
            return "Gemini returned unreadable audio."
        case .unsupportedAudioFormat:
            return "Gemini returned an unsupported audio format."
        case .nonHTTPResponse:
            return "Gemini TTS request returned a non-HTTP response."
        case .requestFailed(let status, let message):
            return "Gemini TTS request failed (HTTP \(status)): \(message)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
