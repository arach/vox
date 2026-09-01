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

    @Test("default selector from live model list matches the configured ranking")
    func defaultModelIdFromModelListPrefersRemoteWhenAvailable() {
        let models = [
            TTSModelInfo(
                id: TTSDefaults.localModelId,
                name: "AVSpeech",
                backend: "avspeech",
                installed: true,
                preloaded: true,
                available: true
            ),
            TTSModelInfo(
                id: NVIDIAMagpieTTSProvider.modelID,
                name: "NVIDIA Magpie",
                backend: "nvidia",
                installed: true,
                preloaded: false,
                available: true
            ),
            TTSModelInfo(
                id: TTSDefaults.modelId,
                name: "OpenAI",
                backend: "openai",
                installed: false,
                preloaded: false,
                available: false
            )
        ]

        #expect(TTSDefaultModelSelector.defaultModelId(from: models) == NVIDIAMagpieTTSProvider.modelID)
    }

    @Test("blank NVIDIA env aliases fence process secrets for default selection")
    func nvidiaBlankEnvFencesDefaultSelection() {
        let avspeech = ProviderEntry(
            id: "avspeech",
            kind: .tts,
            builtin: true,
            models: [TTSDefaults.localModelId]
        )
        let blankPrimary = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "nvidia",
                kind: .tts,
                builtin: true,
                models: NVIDIAMagpieTTSProvider.supportedModelIDs,
                env: ["NV_API_KEY": ""]
            )
        ])
        let blankAlias = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "magpie",
                kind: .tts,
                builtin: true,
                models: NVIDIAMagpieTTSProvider.supportedModelIDs,
                env: ["NVIDIA_API_KEY": "  "]
            )
        ])
        let missingKeys = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "nvidia",
                kind: .tts,
                builtin: true,
                models: NVIDIAMagpieTTSProvider.supportedModelIDs,
                env: ["NVIDIA_TTS_URL": "https://example.test"]
            )
        ])

        #expect(TTSDefaultModelSelector.defaultModelId(
            for: blankPrimary,
            environment: ["NV_API_KEY": "process-secret", "NVIDIA_API_KEY": "alias-secret"]
        ) == TTSDefaults.localModelId)
        #expect(TTSDefaultModelSelector.defaultModelId(
            for: blankAlias,
            environment: ["NV_API_KEY": "process-secret"]
        ) == TTSDefaults.localModelId)
        #expect(TTSDefaultModelSelector.defaultModelId(
            for: missingKeys,
            environment: ["NVIDIA_API_KEY": "process-secret"]
        ) == NVIDIAMagpieTTSProvider.modelID)
        #expect(TTSDefaultModelSelector.defaultModelId(
            for: ProvidersConfig(providers: [
                avspeech,
                ProviderEntry(
                    id: "nvidia",
                    kind: .tts,
                    builtin: true,
                    models: NVIDIAMagpieTTSProvider.supportedModelIDs
                )
            ]),
            environment: ["NV_API_KEY": "process-secret"]
        ) == NVIDIAMagpieTTSProvider.modelID)
    }

    @Test("blank GROQ_API_KEY fences process secrets for default selection")
    func groqBlankEnvFencesDefaultSelection() {
        let avspeech = ProviderEntry(
            id: "avspeech",
            kind: .tts,
            builtin: true,
            models: [TTSDefaults.localModelId]
        )
        let blank = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "groq-tts",
                kind: .tts,
                builtin: true,
                models: GroqTTSProvider.supportedModelIDs,
                env: ["GROQ_API_KEY": ""]
            )
        ])
        let missing = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "groq",
                kind: .tts,
                builtin: true,
                models: GroqTTSProvider.supportedModelIDs,
                env: ["GROQ_BASE_URL": "https://example.test"]
            )
        ])

        #expect(TTSDefaultModelSelector.defaultModelId(
            for: blank,
            environment: ["GROQ_API_KEY": "process-secret"]
        ) == TTSDefaults.localModelId)
        #expect(TTSDefaultModelSelector.defaultModelId(
            for: missing,
            environment: ["GROQ_API_KEY": " process-secret "]
        ) == GroqTTSProvider.defaultModelID)
    }

    @Test("blank Gemini/Google env aliases fence process secrets for default selection")
    func geminiBlankEnvFencesDefaultSelection() {
        let avspeech = ProviderEntry(
            id: "avspeech",
            kind: .tts,
            builtin: true,
            models: [TTSDefaults.localModelId]
        )
        let blankGemini = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "gemini",
                kind: .tts,
                builtin: true,
                models: GeminiTTSProvider.supportedModelIDs,
                env: ["GEMINI_API_KEY": ""]
            )
        ])
        let blankGoogle = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "google-tts",
                kind: .tts,
                builtin: true,
                models: GeminiTTSProvider.supportedModelIDs,
                env: ["GOOGLE_API_KEY": "  "]
            )
        ])
        let blankGenai = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "gemini-tts",
                kind: .tts,
                builtin: true,
                models: GeminiTTSProvider.supportedModelIDs,
                env: ["GOOGLE_GENAI_API_KEY": ""]
            )
        ])
        let missing = ProvidersConfig(providers: [
            avspeech,
            ProviderEntry(
                id: "gemini",
                kind: .tts,
                builtin: true,
                models: GeminiTTSProvider.supportedModelIDs,
                env: ["GEMINI_BASE_URL": "https://example.test"]
            )
        ])

        #expect(TTSDefaultModelSelector.defaultModelId(
            for: blankGemini,
            environment: ["GEMINI_API_KEY": "process-secret", "GOOGLE_API_KEY": "google-secret"]
        ) == TTSDefaults.localModelId)
        #expect(TTSDefaultModelSelector.defaultModelId(
            for: blankGoogle,
            environment: ["GEMINI_API_KEY": "process-secret"]
        ) == TTSDefaults.localModelId)
        #expect(TTSDefaultModelSelector.defaultModelId(
            for: blankGenai,
            environment: ["GOOGLE_API_KEY": "process-secret"]
        ) == TTSDefaults.localModelId)
        #expect(TTSDefaultModelSelector.defaultModelId(
            for: missing,
            environment: ["GOOGLE_GENAI_API_KEY": "process-genai"]
        ) == GeminiTTSProvider.defaultModelID)
    }
}
