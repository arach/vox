import Foundation
import VoxCore

public enum TTSDefaults {
    public static let modelId = "gpt-4o-mini-tts"
    public static let localModelId = "avspeech:system"
    public static let format = "wav"
}

public enum TTSDefaultProviderConfig {
    public static func inProcess() -> ProvidersConfig {
        ProvidersConfig(providers: [
            ProviderEntry(
                id: "openai-tts",
                kind: .tts,
                builtin: true,
                models: OpenAITTSProvider.supportedModelIDs
            ),
            ProviderEntry(
                id: "elevenlabs",
                kind: .tts,
                builtin: true,
                models: ElevenLabsTTSProvider.supportedModelIDs
            ),
            ProviderEntry(
                id: "minimax",
                kind: .tts,
                builtin: true,
                models: MiniMaxTTSProvider.supportedModelIDs
            ),
            ProviderEntry(
                id: "nvidia",
                kind: .tts,
                builtin: true,
                models: NVIDIAMagpieTTSProvider.supportedModelIDs
            ),
            ProviderEntry(
                id: "groq",
                kind: .tts,
                builtin: true,
                models: GroqTTSProvider.supportedModelIDs
            ),
            ProviderEntry(
                id: "gemini",
                kind: .tts,
                builtin: true,
                models: GeminiTTSProvider.supportedModelIDs
            ),
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [AVSpeechSynthesizerProvider.modelID]
            )
        ])
    }
}

public struct SynthesisRequest: Sendable, Equatable {
    public let requestId: String
    public let text: String
    public let modelId: String
    public let voiceId: String?
    public let format: String
    public let speed: Double?
    public let instructions: String?
    public let providerCredentials: [String: String]

    public init(
        requestId: String = UUID().uuidString,
        text: String,
        modelId: String = TTSDefaults.modelId,
        voiceId: String? = nil,
        format: String = TTSDefaults.format,
        speed: Double? = nil,
        instructions: String? = nil,
        providerCredentials: [String: String] = [:]
    ) {
        self.requestId = requestId
        self.text = text
        self.modelId = modelId
        self.voiceId = voiceId
        self.format = format
        self.speed = speed
        self.instructions = instructions
        self.providerCredentials = providerCredentials
    }
}

public protocol TTSProvider: Sendable {
    func models() async -> [TTSModelInfo]
    func voices(modelId: String?) async throws -> [TTSVoiceInfo]
    func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo
    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput
}

public actor TTSEngineManager {
    private let provider: any TTSProvider

    public init() {
        self.provider = TTSProviderRegistry(config: TTSDefaultProviderConfig.inProcess())
    }

    public init(provider: any TTSProvider) {
        self.provider = provider
    }

    public func models() async -> [TTSModelInfo] {
        await provider.models()
    }

    public func voices(modelId: String? = nil) async throws -> [TTSVoiceInfo] {
        try await provider.voices(modelId: modelId)
    }

    public func preload(
        modelId: String,
        voiceId: String? = nil,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        try await provider.preload(modelId: modelId, voiceId: voiceId, progress: progress)
    }

    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        try await provider.synthesize(request)
    }
}
