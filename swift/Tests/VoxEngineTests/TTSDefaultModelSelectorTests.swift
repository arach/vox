import Testing
import VoxCore
@testable import VoxEngine

struct TTSDefaultModelSelectorTests {
    @Test("default selector falls back to AVSpeech when OpenAI has no API key")
    func skipsOpenAIWithoutAPIKey() {
        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.modelId]
            ),
            ProviderEntry(
                id: "openai-tts",
                kind: .tts,
                builtin: true,
                models: ["gpt-4o-mini-tts"]
            )
        ])

        let modelId = TTSDefaultModelSelector.defaultModelId(for: config, environment: [:])

        #expect(modelId == TTSDefaults.modelId)
    }

    @Test("default selector can prefer OpenAI when API key is configured")
    func prefersOpenAIWithAPIKey() {
        let config = ProvidersConfig(providers: [
            ProviderEntry(
                id: "avspeech",
                kind: .tts,
                builtin: true,
                models: [TTSDefaults.modelId]
            ),
            ProviderEntry(
                id: "openai-tts",
                kind: .tts,
                builtin: true,
                models: ["gpt-4o-mini-tts"],
                env: ["OPENAI_API_KEY": "test-key"]
            )
        ])

        let modelId = TTSDefaultModelSelector.defaultModelId(for: config, environment: [:])

        #expect(modelId == "gpt-4o-mini-tts")
    }
}
