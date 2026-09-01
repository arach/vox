import Foundation
import VoxCore

public enum TTSDefaultModelSelector {
    public static func defaultModelId(
        for config: ProvidersConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let entries = config.providers.filter { $0.resolvedKind == .tts }
        let availableConfiguredModels = entries.flatMap { entry -> [String] in
            guard isAvailableForDefaultSelection(entry, environment: environment) else {
                return []
            }
            return entry.models ?? []
        }

        if availableConfiguredModels.contains(TTSDefaults.modelId) {
            return TTSDefaults.modelId
        }

        if let preferredOpenAIModel = availableConfiguredModels.first(where: isOpenAIModel) {
            return preferredOpenAIModel
        }

        if let preferredRemoteModel = availableConfiguredModels.first(where: isRemoteAPIModel) {
            return preferredRemoteModel
        }

        if availableConfiguredModels.contains(TTSDefaults.localModelId) {
            return TTSDefaults.localModelId
        }

        if let firstAvailable = availableConfiguredModels.first {
            return firstAvailable
        }

        let configuredModels = entries.flatMap { $0.models ?? [] }
        return configuredModels.first ?? TTSDefaults.modelId
    }

    public static func defaultModelId(from models: [TTSModelInfo]) -> String {
        let available = models.filter { $0.available && $0.installed }
        let candidates = available.isEmpty ? models : available
        let ids = candidates.map(\.id)

        if ids.contains(TTSDefaults.modelId) {
            return TTSDefaults.modelId
        }
        if let preferredOpenAIModel = ids.first(where: isOpenAIModel) {
            return preferredOpenAIModel
        }
        if let preferredRemoteModel = ids.first(where: isRemoteAPIModel) {
            return preferredRemoteModel
        }
        if ids.contains(TTSDefaults.localModelId) {
            return TTSDefaults.localModelId
        }
        return ids.first ?? TTSDefaults.modelId
    }

    private static func isOpenAIModel(_ modelId: String) -> Bool {
        OpenAITTSProvider.supportedModelIDs.contains(modelId)
    }

    private static func isRemoteAPIModel(_ modelId: String) -> Bool {
        OpenAITTSProvider.supportedModelIDs.contains(modelId)
            || ElevenLabsTTSProvider.supportedModelIDs.contains(modelId)
            || MiniMaxTTSProvider.supportedModelIDs.contains(modelId)
            || NVIDIAMagpieTTSProvider.supportedModelIDs.contains(modelId)
            || GroqTTSProvider.supportedModelIDs.contains(modelId)
            || GeminiTTSProvider.supportedModelIDs.contains(modelId)
    }

    private static func isAvailableForDefaultSelection(
        _ entry: ProviderEntry,
        environment: [String: String]
    ) -> Bool {
        switch TTSProviderFamily(providerId: entry.id) {
        case .openai:
            return hasValue(entry.env?["OPENAI_API_KEY"])
                || hasValue(environment["OPENAI_API_KEY"])
        case .elevenlabs:
            return hasValue(entry.env?["ELEVENLABS_API_KEY"])
                || hasValue(environment["ELEVENLABS_API_KEY"])
        case .minimax:
            return hasValue(entry.env?["MINIMAX_API_KEY"])
                || hasValue(environment["MINIMAX_API_KEY"])
        case .nvidia:
            return hasConfiguredSecret(
                entry.env,
                processEnv: environment,
                keys: ["NV_API_KEY", "NVIDIA_API_KEY"]
            )
        case .groq:
            return hasConfiguredSecret(
                entry.env,
                processEnv: environment,
                keys: ["GROQ_API_KEY"]
            )
        case .gemini:
            return hasConfiguredSecret(
                entry.env,
                processEnv: environment,
                keys: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GENAI_API_KEY"]
            )
        case .avspeech, .mlxAudio, nil:
            return true
        }
    }

    private static func hasConfiguredSecret(
        _ env: [String: String]?,
        processEnv: [String: String],
        keys: [String]
    ) -> Bool {
        RemoteTTSSupport.resolveSecret(
            lentValues: [],
            env: env,
            processEnv: processEnv,
            keys: keys
        ) != nil
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
