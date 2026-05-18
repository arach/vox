import Foundation
import Testing
import VoxCore
@testable import VoxEngine

struct TTSProviderTests {
    @Test("TTSEngineManager allows concurrent synthesis requests")
    func ttsEngineManagerAllowsConcurrentSynthesisRequests() async throws {
        let provider = ConcurrencyCheckingTTSProvider()
        let manager = TTSEngineManager(provider: provider)

        async let first = manager.synthesize(SynthesisRequest(
            text: "first",
            modelId: "test-tts"
        ))
        async let second = manager.synthesize(SynthesisRequest(
            text: "second",
            modelId: "test-tts"
        ))

        _ = try await [first, second]
        #expect(await provider.maxConcurrentSynthesisRequests() == 2)
    }

    @Test("OpenAI TTS timeout defaults to a sane latency budget")
    func openAITTSTimeoutDefaultsAndCaps() {
        #expect(OpenAITTSProvider.resolveRequestTimeout(env: nil, processEnv: [:]) == 12)
        #expect(OpenAITTSProvider.resolveRequestTimeout(
            env: ["VOX_OPENAI_TTS_TIMEOUT_SECONDS": "12.5"],
            processEnv: [:]
        ) == 12.5)
        #expect(OpenAITTSProvider.resolveRequestTimeout(
            env: ["VOX_OPENAI_TTS_TIMEOUT_SECONDS": "300"],
            processEnv: [:]
        ) == 30)
        #expect(OpenAITTSProvider.resolveRequestTimeout(
            env: ["VOX_OPENAI_TTS_TIMEOUT_SECONDS": "nope"],
            processEnv: [:]
        ) == 12)
    }

    @Test("AVSpeechSynthesizerProvider lists system voices and emits wav audio")
    func avSpeechSynthesizerProviderGeneratesAudio() async throws {
        let provider = AVSpeechSynthesizerProvider()
        let voices = try await provider.voices(modelId: AVSpeechSynthesizerProvider.modelID)
        let voice = try #require(voices.first)

        let output = try await provider.synthesize(SynthesisRequest(
            text: "Vox synthesis test",
            modelId: AVSpeechSynthesizerProvider.modelID,
            voiceId: voice.id
        ))

        #expect(output.modelId == AVSpeechSynthesizerProvider.modelID)
        #expect(output.voiceId == voice.id)
        #expect(output.format == "wav")
        #expect(output.audioData.count > 0)
        #expect(output.metrics.audioDurationMs > 0)
        #expect(output.metrics.outputBytes == output.audioData.count)
    }
}

private actor ConcurrencyCheckingTTSProvider: TTSProvider {
    private var activeSynthesisRequests = 0
    private var maxActiveSynthesisRequests = 0

    func maxConcurrentSynthesisRequests() -> Int {
        maxActiveSynthesisRequests
    }

    func models() async -> [TTSModelInfo] {
        [
            TTSModelInfo(
                id: "test-tts",
                name: "Test TTS",
                backend: "test",
                installed: true,
                preloaded: true,
                available: true
            )
        ]
    }

    func voices(modelId: String?) async throws -> [TTSVoiceInfo] {
        [
            TTSVoiceInfo(
                id: "test",
                name: "Test",
                backend: "test",
                modelId: modelId ?? "test-tts",
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
        progress(ModelProgress(modelId: modelId, progress: 1, status: "ready"))
        return TTSModelInfo(
            id: modelId,
            name: modelId,
            backend: "test",
            installed: true,
            preloaded: true,
            available: true
        )
    }

    func synthesize(_ request: SynthesisRequest) async throws -> SynthesisOutput {
        activeSynthesisRequests += 1
        maxActiveSynthesisRequests = max(maxActiveSynthesisRequests, activeSynthesisRequests)
        try await Task.sleep(nanoseconds: 80_000_000)
        activeSynthesisRequests -= 1
        return SynthesisOutput(
            modelId: request.modelId,
            voiceId: request.voiceId ?? "test",
            format: request.format,
            contentType: "audio/wav",
            audioData: Data("RIFF".utf8),
            elapsedMs: 80,
            metrics: SynthesisMetrics(
                traceId: "test",
                characterCount: request.text.count,
                audioDurationMs: 100,
                outputBytes: 4,
                wasPreloaded: true,
                modelCheckMs: 0,
                modelLoadMs: 0,
                voiceResolveMs: 0,
                synthesisMs: 80,
                totalMs: 80
            )
        )
    }
}
