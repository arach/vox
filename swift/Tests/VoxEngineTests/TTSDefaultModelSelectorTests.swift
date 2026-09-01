import Testing
import VoxCore
@testable import HudsonSpeechEngine

struct TTSDefaultModelSelectorTests {
    @Test("default selector falls back to AVSpeech when OpenAI has no API key")
    func skipsOpenAIWithoutAPIKey() {
        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.localModelId]
            ),
            ProviderEntry(
                id: "openai-tts",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.modelId]
            )
        ])

        let modelId = TTSDefaultModelSelector.defaultModelId(for: config, environment: [:])

        #expect(modelId == TTSDefaults.localModelId)
    }

    @Test("default selector can prefer OpenAI when API key is configured")
    func prefersOpenAIWithAPIKey() {
        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.localModelId]
            ),
            ProviderEntry(
                id: "openai-tts",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.modelId],
                env: ["OPENAI_API_KEY": "test-key"]
            )
        ])

        let modelId = TTSDefaultModelSelector.defaultModelId(for: config, environment: [:])

        #expect(modelId == TTSDefaults.modelId)
    }

    @Test("default selector skips remote providers without API keys")
    func skipsRemoteProvidersWithoutAPIKeys() {
        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "mlx-audio",
                kind: .tts,
                builtin: true,
                models: ["mlx-community/Kokoro-82M-bf16"]
            ),
            ProviderEntry(
                id: "openai-tts",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.modelId]
            ),
            ProviderEntry(
                id: "elevenlabs",
                kind: .tts,
                builtin: true,
                models: [ElevenLabsTTSProvider.supportedModelIDs[0]]
            ),
            ProviderEntry(
                id: "minimax",
                kind: .tts,
                builtin: true,
                models: [MiniMaxTTSProvider.supportedModelIDs[0]]
            ),
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.localModelId]
            )
        ])

        let modelId = TTSDefaultModelSelector.defaultModelId(for: config, environment: [:])

        #expect(modelId == TTSDefaults.localModelId)
    }

    @Test("default selector can use ElevenLabs when configured and OpenAI is unavailable")
    func prefersElevenLabsWhenConfigured() {
        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "openai-tts",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.modelId]
            ),
            ProviderEntry(
                id: "elevenlabs",
                kind: .tts,
                builtin: true,
                models: [ElevenLabsTTSProvider.supportedModelIDs[0]]
            ),
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.localModelId]
            )
        ])

        let modelId = TTSDefaultModelSelector.defaultModelId(
            for: config,
            environment: ["ELEVENLABS_API_KEY": "test-key"]
        )

        #expect(modelId == ElevenLabsTTSProvider.supportedModelIDs[0])
    }

    @Test("default selector skips NVIDIA, Groq, and Gemini without API keys")
    func skipsNewRemoteProvidersWithoutAPIKeys() {
        let config = TTSDefaultProviderConfig.inProcess()
        let modelId = TTSDefaultModelSelector.defaultModelId(for: config, environment: [:])
        #expect(modelId == TTSDefaults.localModelId)
        #expect(config.providers.contains(where: { $0.id == "nvidia" }))
        #expect(config.providers.contains(where: { $0.id == "groq" }))
        #expect(config.providers.contains(where: { $0.id == "gemini" }))
        #expect(config.providers.first(where: { $0.id == "openai-tts" })?.models?.contains(TTSDefaults.modelId) == true)
    }

    @Test("default selector can use NVIDIA when configured and OpenAI is unavailable")
    func prefersNVIDIAWhenConfigured() {
        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "openai-tts",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.modelId]
            ),
            ProviderEntry(
                id: "nvidia",
                kind: .tts,
                builtin: true,
                models: NVIDIAMagpieTTSProvider.supportedModelIDs
            ),
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.localModelId]
            )
        ])

        let modelId = TTSDefaultModelSelector.defaultModelId(
            for: config,
            environment: ["NV_API_KEY": "test-key"]
        )

        #expect(modelId == NVIDIAMagpieTTSProvider.modelID)
    }
}
