import AVFoundation
import Foundation
import VoxCore

public actor NVIDIAMagpieTTSProvider: TTSProvider {
    public static let providerID = "nvidia"
    public static let modelID = "magpie-tts-multilingual"
    public static let supportedModelIDs = [modelID]
    public static let defaultVoiceID = "Magpie-Multilingual.EN-US.Aria"
    public static let encoding = "LINEAR_PCM"
    public static let sampleRateHz = 44_100
    static let maximumInputCharacters = 2_000
    static let defaultRequestTimeout: TimeInterval = 60
    static let maximumRequestTimeout: TimeInterval = 120

    static let defaultSynthesizeURL = URL(
        string: "https://877104f7-e885-42b9-8de8-f6e4c6303969.invocation.api.nvcf.nvidia.com/v1/audio/synthesize"
    )!
    static let defaultVoicesURL = URL(
        string: "https://877104f7-e885-42b9-8de8-f6e4c6303969.invocation.api.nvcf.nvidia.com/v1/audio/list_voices"
    )!

    private let log = VoxLog.engine
    private let session: URLSession
    private let apiKey: String?
    private let synthesizeURL: URL
    private let voicesURL: URL
    private let requestTimeout: TimeInterval
    private var preloadedModels: Set<String> = []

    public init(env: [String: String]? = nil, session: URLSession = .shared) {
        let processEnv = ProcessInfo.processInfo.environment
        self.session = session
        self.apiKey = Self.resolveConfiguredAPIKey(env: env, processEnv: processEnv)
        self.synthesizeURL = Self.resolveSynthesizeURL(env: env, processEnv: processEnv)
        self.voicesURL = Self.resolveVoicesURL(env: env, processEnv: processEnv)
        self.requestTimeout = Self.resolveRequestTimeout(env: env, processEnv: processEnv)
    }

    public func models() async -> [TTSModelInfo] {
        let available = apiKeyAvailability()
        return Self.supportedModelIDs.map { modelId in
            TTSModelInfo(
                id: modelId,
                name: "NVIDIA Magpie TTS Multilingual",
                backend: Self.providerID,
                installed: available,
                preloaded: preloadedModels.contains(modelId),
                available: available
            )
        }
    }

    public func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        let resolvedModelId = modelId ?? Self.modelID
        try validate(modelId: resolvedModelId)

        guard let apiKey = try? resolveAPIKey(providerCredentials: [:]) else {
            return [Self.fallbackVoice(modelId: resolvedModelId, available: false)]
        }

        var request = URLRequest(url: voicesURL)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await RemoteTTSSupport.data(for: request, session: session)
        try validateHTTPResponse(data: data, response: response, operation: "voice discovery")
        let parsed = Self.parseVoices(from: data, modelId: resolvedModelId, available: true)
        guard !parsed.isEmpty else {
            throw NVIDIAMagpieTTSProviderError.emptyVoiceCatalog
        }
        return parsed
    }

    public func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        try validate(modelId: modelId)
        _ = try resolveAPIKey(providerCredentials: [:])
        progress(ModelProgress(modelId: modelId, progress: 0.2, status: "starting"))
        preloadedModels.insert(modelId)
        progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        return (await models()).first(where: { $0.id == modelId }) ?? TTSModelInfo(
            id: modelId,
            name: "NVIDIA Magpie TTS Multilingual",
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
            throw NVIDIAMagpieTTSProviderError.missingText
        }
        guard text.count <= Self.maximumInputCharacters else {
            throw NVIDIAMagpieTTSProviderError.inputTooLong(Self.maximumInputCharacters)
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
        let resolvedVoice = Self.resolveVoice(voiceId: request.voiceId)
        let language = Self.language(for: resolvedVoice)
        trace.end(resolvedVoice)

        trace.begin("inference")
        let boundary = "Vox-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: synthesizeURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = requestTimeout
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.httpBody = Self.multipartBody(
            boundary: boundary,
            fields: [
                ("text", text),
                ("language", language),
                ("voice", resolvedVoice),
                ("encoding", Self.encoding),
                ("sample_rate_hz", String(Self.sampleRateHz))
            ]
        )

        log.info("NVIDIA Magpie synthesis request started requestId=\(request.requestId) modelId=\(request.modelId) voiceId=\(resolvedVoice) language=\(language) textLength=\(text.count)")
        let (data, response) = try await RemoteTTSSupport.data(for: urlRequest, session: session)
        let httpResponse = try validateHTTPResponse(
            data: data,
            response: response,
            operation: "synthesis",
            sensitiveValues: [text]
        )
        let audioData = try Self.decodeAudio(
            data,
            contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"),
            sampleRate: UInt32(Self.sampleRateHz)
        )
        let synthesisMs = trace.end("\(audioData.count) bytes")
        let audioDurationMs = (try? inspectWaveData(audioData)) ?? 0
        let metrics = SynthesisMetrics(
            traceId: trace.traceId,
            characterCount: text.count,
            audioDurationMs: audioDurationMs,
            outputBytes: audioData.count,
            wasPreloaded: wasPreloaded,
            modelCheckMs: trace.durationMs(for: "model_check"),
            modelLoadMs: trace.durationMs(for: "model_load"),
            voiceResolveMs: trace.durationMs(for: "voice_resolve"),
            synthesisMs: synthesisMs,
            totalMs: trace.elapsedMs
        )

        log.info("NVIDIA Magpie synthesis trace complete \(trace.summary)")
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

    static func language(for voice: String) -> String {
        let parts = voice.split(separator: ".")
        guard let locale = parts.first(where: { isLocaleSegment($0) }) else { return "en-US" }
        let languageParts = locale.split(separator: "-", maxSplits: 1)
        return "\(languageParts[0].lowercased())-\(languageParts[1].uppercased())"
    }

    static func displayName(for voice: String) -> String {
        let parts = voice.split(separator: ".")
        guard let localeIndex = parts.firstIndex(where: { isLocaleSegment($0) }),
              parts.index(after: localeIndex) < parts.endIndex else {
            return parts.last.map(String.init) ?? voice
        }
        return parts[parts.index(after: localeIndex)...]
            .map(String.init)
            .joined(separator: " · ")
    }

    static func parseVoices(
        from data: Data,
        modelId: String = modelID,
        available: Bool = true
    ) -> [TTSVoiceInfo] {
        guard let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var ids = Set<String>()
        for value in catalog.values {
            guard let group = value as? [String: Any], let voices = group["voices"] as? [Any] else {
                continue
            }
            for value in voices {
                guard let id = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !id.isEmpty else { continue }
                ids.insert(id)
            }
        }
        return ids.map { id in
            TTSVoiceInfo(
                id: id,
                name: displayName(for: id),
                language: language(for: id),
                backend: providerID,
                modelId: modelId,
                available: available,
                isDefault: id == defaultVoiceID
            )
        }.sorted {
            if $0.language != $1.language {
                return ($0.language ?? "") < ($1.language ?? "")
            }
            if $0.name != $1.name {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.id < $1.id
        }
    }

    static func multipartBody(boundary: String, fields: [(String, String)]) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    static func resolveAPIKey(
        providerCredentials: [String: String],
        env: [String: String]?,
        processEnv: [String: String]
    ) -> String? {
        RemoteTTSSupport.resolveSecret(
            lentValues: [
                providerCredentials["NV_API_KEY"],
                providerCredentials["NVIDIA_API_KEY"],
                providerCredentials["nvApiKey"],
                providerCredentials["nvidiaApiKey"],
                providerCredentials["nv_api_key"],
                providerCredentials["nvidia_api_key"]
            ],
            env: env,
            processEnv: processEnv,
            keys: ["NV_API_KEY", "NVIDIA_API_KEY"]
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
        let rawValue = env?["VOX_NVIDIA_TTS_TIMEOUT_SECONDS"]
            ?? env?["NVIDIA_TTS_TIMEOUT_SECONDS"]
            ?? processEnv["VOX_NVIDIA_TTS_TIMEOUT_SECONDS"]
            ?? processEnv["NVIDIA_TTS_TIMEOUT_SECONDS"]
        guard let rawValue, let parsed = TimeInterval(rawValue), parsed > 0 else {
            return defaultRequestTimeout
        }
        return min(parsed, maximumRequestTimeout)
    }

    static func resolveSynthesizeURL(
        env: [String: String]?,
        processEnv: [String: String]
    ) -> URL {
        if let override = RemoteTTSSupport.firstNonEmpty(
            env?["NVIDIA_TTS_URL"],
            env?["NVIDIA_SYNTHESIZE_URL"],
            processEnv["NVIDIA_TTS_URL"],
            processEnv["NVIDIA_SYNTHESIZE_URL"]
        ), let url = URL(string: override) {
            return url
        }
        if let base = RemoteTTSSupport.firstNonEmpty(env?["NVIDIA_BASE_URL"], processEnv["NVIDIA_BASE_URL"]),
           let url = URL(string: base)?.appendingPathComponent("v1/audio/synthesize") {
            return url
        }
        return defaultSynthesizeURL
    }

    static func resolveVoicesURL(
        env: [String: String]?,
        processEnv: [String: String]
    ) -> URL {
        if let override = RemoteTTSSupport.firstNonEmpty(
            env?["NVIDIA_VOICES_URL"],
            processEnv["NVIDIA_VOICES_URL"]
        ), let url = URL(string: override) {
            return url
        }
        if let base = RemoteTTSSupport.firstNonEmpty(env?["NVIDIA_BASE_URL"], processEnv["NVIDIA_BASE_URL"]),
           let url = URL(string: base)?.appendingPathComponent("v1/audio/list_voices") {
            return url
        }
        return defaultVoicesURL
    }

    private func apiKeyAvailability() -> Bool {
        guard let apiKey else { return false }
        return !apiKey.isEmpty
    }

    private func resolveAPIKey(providerCredentials: [String: String]) throws -> String {
        guard let key = Self.resolveAPIKey(
            providerCredentials: providerCredentials,
            env: apiKey.map { ["NV_API_KEY": $0] },
            processEnv: [:]
        ) else {
            throw NVIDIAMagpieTTSProviderError.missingAPIKey
        }
        return key
    }

    private func validate(modelId: String) throws {
        guard Self.supportedModelIDs.contains(modelId) else {
            throw NVIDIAMagpieTTSProviderError.unsupportedModel(modelId)
        }
    }

    private func validate(format: String) throws {
        guard format.lowercased() == TTSDefaults.format else {
            throw NVIDIAMagpieTTSProviderError.unsupportedFormat(format)
        }
    }

    @discardableResult
    private func validateHTTPResponse(
        data: Data,
        response: URLResponse,
        operation: String,
        sensitiveValues: [String] = []
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NVIDIAMagpieTTSProviderError.nonHTTPResponse(operation)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NVIDIAMagpieTTSProviderError.requestFailed(
                operation: operation,
                status: httpResponse.statusCode,
                message: RemoteTTSSupport.sanitizeVendorMessage(
                    from: data,
                    vendor: "NVIDIA Magpie",
                    sensitiveValues: sensitiveValues
                )
            )
        }
        return httpResponse
    }

    static func decodeAudio(
        _ data: Data,
        contentType: String?,
        sampleRate: UInt32
    ) throws -> Data {
        if PCMWAV.isStructurallyValid(data) {
            return data
        }
        guard !data.isEmpty else {
            throw NVIDIAMagpieTTSProviderError.emptyAudio
        }

        let mime = (contentType ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if mime.contains("wav") || mime.contains("json") || mime.contains("html") || mime.hasPrefix("text/") {
            throw NVIDIAMagpieTTSProviderError.invalidAudio
        }

        do {
            return try PCMWAV.wrap(pcm: data, sampleRate: sampleRate)
        } catch {
            throw NVIDIAMagpieTTSProviderError.invalidAudio
        }
    }

    private static func resolveVoice(voiceId: String?) -> String {
        let trimmed = voiceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultVoiceID : trimmed
    }

    private static func fallbackVoice(modelId: String, available: Bool) -> TTSVoiceInfo {
        TTSVoiceInfo(
            id: defaultVoiceID,
            name: displayName(for: defaultVoiceID),
            language: language(for: defaultVoiceID),
            backend: providerID,
            modelId: modelId,
            available: available,
            isDefault: true
        )
    }

    private static func isLocaleSegment(_ value: Substring) -> Bool {
        let parts = value.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, (2...3).contains(parts[0].count), parts[1].count == 2 else {
            return false
        }
        return parts.allSatisfy { part in
            part.unicodeScalars.allSatisfy(CharacterSet.letters.contains)
        }
    }

    private func inspectWaveData(_ data: Data) throws -> Int {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-nvidia-\(UUID().uuidString)")
            .appendingPathExtension(TTSDefaults.format)
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        return Int((Double(file.length) / file.processingFormat.sampleRate) * 1000)
    }
}

public enum NVIDIAMagpieTTSProviderError: Error, LocalizedError {
    case missingText
    case missingAPIKey
    case inputTooLong(Int)
    case unsupportedModel(String)
    case unsupportedFormat(String)
    case emptyVoiceCatalog
    case emptyAudio
    case invalidAudio
    case nonHTTPResponse(String)
    case requestFailed(operation: String, status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingText:
            return "Missing text"
        case .missingAPIKey:
            return "Missing NV_API_KEY (or NVIDIA_API_KEY) for NVIDIA Magpie TTS provider."
        case .inputTooLong(let limit):
            return "NVIDIA Magpie accepts at most \(limit) normalized characters. Split longer text before synthesis."
        case .unsupportedModel(let modelId):
            return "Unsupported NVIDIA Magpie TTS model: \(modelId)"
        case .unsupportedFormat(let format):
            return "Unsupported synthesis format: \(format). NVIDIA Magpie TTS is currently configured for wav output."
        case .emptyVoiceCatalog:
            return "NVIDIA Magpie voice discovery returned no voices."
        case .emptyAudio:
            return "NVIDIA Magpie returned no audio."
        case .invalidAudio:
            return "NVIDIA Magpie returned audio that is not a valid WAVE file or aligned LINEAR_PCM payload."
        case .nonHTTPResponse(let operation):
            return "NVIDIA Magpie \(operation) returned a non-HTTP response."
        case .requestFailed(let operation, let status, let message):
            return "NVIDIA Magpie \(operation) failed (HTTP \(status)): \(message)"
        }
    }
}
