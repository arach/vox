import Foundation
import Testing
import VoxCore
import VoxEngine
@testable import VoxService

private actor MockTTSProvider: TTSProvider {
    private let modelId: String
    private let voiceId: String

    init(modelId: String = "mock-tts:v1", voiceId: String = "voice-mock") {
        self.modelId = modelId
        self.voiceId = voiceId
    }

    func models() async -> [TTSModelInfo] {
        [
            TTSModelInfo(
                id: modelId,
                name: "Mock TTS",
                backend: "mock",
                installed: true,
                preloaded: true,
                available: true
            )
        ]
    }

    func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        [
            TTSVoiceInfo(
                id: voiceId,
                name: "Mock Voice",
                language: "en-US",
                backend: "mock",
                modelId: modelId ?? self.modelId,
                available: true,
                isDefault: true
            )
        ]
    }

    func preload(
        modelId: String,
        voiceId: String?,
        progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> TTSModelInfo {
        progress(ModelProgress(modelId: modelId, progress: 1.0, status: "ready"))
        return TTSModelInfo(
            id: modelId,
            name: "Mock TTS",
            backend: "mock",
            installed: true,
            preloaded: true,
            available: true
        )
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        let bytes = Data([0x52, 0x49, 0x46, 0x46])
        let metrics = SynthesisMetrics(
            traceId: "mock-trace",
            characterCount: request.text.count,
            audioDurationMs: 320,
            outputBytes: bytes.count,
            wasPreloaded: true,
            modelCheckMs: 1,
            modelLoadMs: 0,
            voiceResolveMs: 1,
            synthesisMs: 12,
            totalMs: 16
        )

        return SynthesisOutput(
            modelId: request.modelId,
            voiceId: request.voiceId ?? voiceId,
            format: request.format,
            contentType: "audio/wav",
            audioData: bytes,
            elapsedMs: 16,
            metrics: metrics
        )
    }
}

struct SynthesisRouteTests {
    @Test("synthesize.generate helper returns audio metadata and metrics")
    func synthesizeGenerateReturnsStructuredOutput() async throws {
        let service = VoxRuntimeService(ttsEngine: TTSEngineManager(provider: MockTTSProvider()))

        let output = try await service.performSynthesizeGenerate(params: [
            "text": "hello world",
            "modelId": "mock-tts:v1",
            "voiceId": "voice-mock",
            "format": "wav"
        ])

        #expect(output.modelId == "mock-tts:v1")
        #expect(output.voiceId == "voice-mock")
        #expect(output.audioData == Data([0x52, 0x49, 0x46, 0x46]))
        #expect(output.metrics.synthesisMs == 12)
    }

    @Test("synthesize.voices helper returns the provider voice list")
    func synthesizeVoicesReturnsProviderVoices() async throws {
        let service = VoxRuntimeService(ttsEngine: TTSEngineManager(provider: MockTTSProvider()))

        let voices = try await service.performSynthesizeVoices(params: [
            "modelId": "mock-tts:v1"
        ])

        #expect(voices.count == 1)
        #expect(voices.first?.id == "voice-mock")
        #expect(voices.first?.modelId == "mock-tts:v1")
        #expect(voices.first?.isDefault == true)
    }

    @Test("synthesize.generate uses speech preferences when model and voice are omitted")
    func synthesizeGenerateUsesPreferredModelAndVoice() async throws {
        let service = VoxRuntimeService(
            ttsEngine: TTSEngineManager(provider: MockTTSProvider(
                modelId: "mock-tts:v2",
                voiceId: "voice-preferred"
            )),
            preferencesLoader: {
                VoxPreferences(
                    speech: VoxSpeechPreferences(
                        preferredSynthesisModelId: "mock-tts:v2",
                        preferredSynthesisVoiceId: "voice-preferred"
                    )
                )
            }
        )

        let output = try await service.performSynthesizeGenerate(params: [
            "text": "hello world"
        ])

        #expect(output.modelId == "mock-tts:v2")
        #expect(output.voiceId == "voice-preferred")
    }
}
