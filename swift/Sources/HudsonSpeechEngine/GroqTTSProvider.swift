import AVFoundation
import Foundation
import VoxCore

public actor GroqTTSProvider: TTSProvider {
    public static let providerID = "groq"
    public static let defaultModelID = "canopylabs/orpheus-v1-english"
    public static let arabicModelID = "canopylabs/orpheus-arabic-saudi"
    public static let supportedModelIDs = [defaultModelID, arabicModelID]
    public static let defaultVoiceID = "autumn"
    static let maximumInputCharacters = 200
    static let defaultRequestTimeout: TimeInterval = 12
    static let maximumRequestTimeout: TimeInterval = 30
    static let defaultBaseURL = "https://api.groq.com/openai/v1"

    public static let englishVoices: [(id: String, name: String, language: String)] = [
        ("autumn", "Autumn", "en"),
        ("diana", "Diana", "en"),
        ("hannah", "Hannah", "en"),
        ("austin", "Austin", "en"),
        ("daniel", "Daniel", "en"),
        ("troy", "Troy", "en")
    ]

    public static let arabicVoices: [(id: String, name: String, language: String)] = [
        ("abdullah", "Abdullah", "ar-SA"),
        ("fahad", "Fahad", "ar-SA"),
        ("sultan", "Sultan", "ar-SA"),
        ("lulwa", "Lulwa", "ar-SA"),
        ("noura", "Noura", "ar-SA"),
        ("aisha", "Aisha", "ar-SA")
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
            env?["GROQ_BASE_URL"],
            processEnv["GROQ_BASE_URL"]
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
        let catalog = resolvedModelId == Self.arabicModelID ? Self.arabicVoices : Self.englishVoices
        let defaultVoice = catalog[0].id
        return catalog.map { voice in
            TTSVoiceInfo(
                id: voice.id,
                name: voice.name,
                language: voice.language,
                backend: Self.providerID,
                modelId: resolvedModelId,
                available: available,
                isDefault: voice.id == defaultVoice
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
            _ = try resolveVoice(modelId: modelId, voiceId: voiceId)
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
            throw GroqTTSProviderError.missingText
        }
        guard text.count <= Self.maximumInputCharacters else {
            throw GroqTTSProviderError.inputTooLong(Self.maximumInputCharacters)
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
        let resolvedVoice = try resolveVoice(modelId: request.modelId, voiceId: request.voiceId)
        trace.end(resolvedVoice)

        trace.begin("inference")
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("audio/speech"))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = requestTimeout
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": request.modelId,
            "voice": resolvedVoice,
            "input": text,
            "response_format": TTSDefaults.format
        ]
        if let speed = request.speed {
            payload["speed"] = Self.clamp(speed, min: 0.5, max: 5)
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        log.info("Groq synthesis request started requestId=\(request.requestId) modelId=\(request.modelId) voiceId=\(resolvedVoice) textLength=\(text.count)")
        let (data, response) = try await RemoteTTSSupport.data(for: urlRequest, session: session)
        let httpResponse = try validateHTTPResponse(data: data, response: response, sensitiveValues: [text])
        guard PCMWAV.isStructurallyValid(data) else {
            throw data.isEmpty ? GroqTTSProviderError.emptyAudio : GroqTTSProviderError.invalidAudio
        }
        let synthesisMs = trace.end("\(data.count) bytes")
        let audioDurationMs = (try? inspectWaveData(data)) ?? 0
        let metrics = SynthesisMetrics(
            traceId: trace.traceId,
            characterCount: text.count,
            audioDurationMs: audioDurationMs,
            outputBytes: data.count,
            wasPreloaded: wasPreloaded,
            modelCheckMs: trace.durationMs(for: "model_check"),
            modelLoadMs: trace.durationMs(for: "model_load"),
            voiceResolveMs: trace.durationMs(for: "voice_resolve"),
            synthesisMs: synthesisMs,
            totalMs: trace.elapsedMs
        )

        log.info("Groq synthesis trace complete \(trace.summary)")
        return SynthesisOutput(
            modelId: request.modelId,
            voiceId: resolvedVoice,
            format: request.format.lowercased(),
            contentType: httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "audio/wav",
            audioData: data,
            elapsedMs: metrics.totalMs,
            metrics: metrics
        )
    }

    static func resolveAPIKey(
        providerCredentials: [String: String],
        env: [String: String]?,
        processEnv: [String: String]
    ) -> String? {
        RemoteTTSSupport.resolveSecret(
            lentValues: [
                providerCredentials["GROQ_API_KEY"],
                providerCredentials["groqApiKey"],
                providerCredentials["groq_api_key"]
            ],
            env: env,
            processEnv: processEnv,
            keys: ["GROQ_API_KEY"]
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
        let rawValue = env?["VOX_GROQ_TTS_TIMEOUT_SECONDS"]
            ?? env?["GROQ_TTS_TIMEOUT_SECONDS"]
            ?? processEnv["VOX_GROQ_TTS_TIMEOUT_SECONDS"]
            ?? processEnv["GROQ_TTS_TIMEOUT_SECONDS"]
        guard let rawValue, let parsed = TimeInterval(rawValue), parsed > 0 else {
            return defaultRequestTimeout
        }
        return min(parsed, maximumRequestTimeout)
    }

    static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }

    private func apiKeyAvailability() -> Bool {
        guard let apiKey else { return false }
        return !apiKey.isEmpty
    }

    private func resolveAPIKey(providerCredentials: [String: String]) throws -> String {
        guard let key = Self.resolveAPIKey(
            providerCredentials: providerCredentials,
            env: apiKey.map { ["GROQ_API_KEY": $0] },
            processEnv: [:]
        ) else {
            throw GroqTTSProviderError.missingAPIKey
        }
        return key
    }

    private func validate(modelId: String) throws {
        guard Self.supportedModelIDs.contains(modelId) else {
            throw GroqTTSProviderError.unsupportedModel(modelId)
        }
    }

    private func validate(format: String) throws {
        guard format.lowercased() == TTSDefaults.format else {
            throw GroqTTSProviderError.unsupportedFormat(format)
        }
    }

    private func resolveVoice(modelId: String, voiceId: String?) throws -> String {
        let catalog = modelId == Self.arabicModelID ? Self.arabicVoices : Self.englishVoices
        let resolved = (voiceId ?? catalog[0].id).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard catalog.contains(where: { $0.id == resolved }) else {
            throw GroqTTSProviderError.unsupportedVoice(voiceId ?? resolved)
        }
        return resolved
    }

    @discardableResult
    private func validateHTTPResponse(
        data: Data,
        response: URLResponse,
        sensitiveValues: [String] = []
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqTTSProviderError.nonHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GroqTTSProviderError.requestFailed(
                status: httpResponse.statusCode,
                message: RemoteTTSSupport.sanitizeVendorMessage(
                    from: data,
                    vendor: "Groq TTS",
                    sensitiveValues: sensitiveValues
                )
            )
        }
        return httpResponse
    }

    private func inspectWaveData(_ data: Data) throws -> Int {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-groq-\(UUID().uuidString)")
            .appendingPathExtension(TTSDefaults.format)
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        return Int((Double(file.length) / file.processingFormat.sampleRate) * 1000)
    }
}

public enum GroqTTSProviderError: Error, LocalizedError {
    case missingText
    case missingAPIKey
    case inputTooLong(Int)
    case unsupportedModel(String)
    case unsupportedVoice(String)
    case unsupportedFormat(String)
    case emptyAudio
    case invalidAudio
    case nonHTTPResponse
    case requestFailed(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingText:
            return "Missing text"
        case .missingAPIKey:
            return "Missing GROQ_API_KEY for Groq TTS provider."
        case .inputTooLong(let limit):
            return "Groq Orpheus accepts at most \(limit) characters. Split longer text before synthesis."
        case .unsupportedModel(let modelId):
            return "Unsupported Groq TTS model: \(modelId)"
        case .unsupportedVoice(let voiceId):
            return "Unsupported Groq TTS voice: \(voiceId)"
        case .unsupportedFormat(let format):
            return "Unsupported synthesis format: \(format). Groq TTS is currently configured for wav output."
        case .emptyAudio:
            return "Groq returned empty audio."
        case .invalidAudio:
            return "Groq returned audio that is not a structurally valid WAV file."
        case .nonHTTPResponse:
            return "Groq TTS request returned a non-HTTP response."
        case .requestFailed(let status, let message):
            return "Groq TTS request failed (HTTP \(status)): \(message)"
        }
    }
}
