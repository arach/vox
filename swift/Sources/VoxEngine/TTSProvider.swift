import Foundation
import VoxCore

public enum TTSDefaults {
    public static let modelId = "avspeech:system"
    public static let format = "wav"
}

public struct SynthesisRequest: Sendable, Equatable {
    public let requestId: String
    public let text: String
    public let modelId: String
    public let voiceId: String?
    public let format: String
    public let speed: Double?
    public let instructions: String?

    public init(
        requestId: String = UUID().uuidString,
        text: String,
        modelId: String = TTSDefaults.modelId,
        voiceId: String? = nil,
        format: String = TTSDefaults.format,
        speed: Double? = nil,
        instructions: String? = nil
    ) {
        self.requestId = requestId
        self.text = text
        self.modelId = modelId
        self.voiceId = voiceId
        self.format = format
        self.speed = speed
        self.instructions = instructions
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

    public init(provider: any TTSProvider = AVSpeechSynthesizerProvider()) {
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
