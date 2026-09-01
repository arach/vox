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
        switch entry.id.lowercased() {
        case "openai", "openai-tts":
            return hasValue(entry.env?["OPENAI_API_KEY"])
                || hasValue(environment["OPENAI_API_KEY"])
        case "elevenlabs", "elevenlabs-tts", "eleven-labs", "eleven-labs-tts":
            return hasValue(entry.env?["ELEVENLABS_API_KEY"])
                || hasValue(environment["ELEVENLABS_API_KEY"])
        case "minimax", "minimax-tts":
            return hasValue(entry.env?["MINIMAX_API_KEY"])
                || hasValue(environment["MINIMAX_API_KEY"])
        case "nvidia", "nvidia-tts", "magpie", "magpie-tts", "nvidia-magpie":
            return hasValue(entry.env?["NV_API_KEY"])
                || hasValue(entry.env?["NVIDIA_API_KEY"])
                || hasValue(environment["NV_API_KEY"])
                || hasValue(environment["NVIDIA_API_KEY"])
        case "groq", "groq-tts":
            return hasValue(entry.env?["GROQ_API_KEY"])
                || hasValue(environment["GROQ_API_KEY"])
        case "gemini", "gemini-tts", "google-tts", "google-gemini-tts":
            return hasValue(entry.env?["GEMINI_API_KEY"])
                || hasValue(entry.env?["GOOGLE_API_KEY"])
                || hasValue(entry.env?["GOOGLE_GENAI_API_KEY"])
                || hasValue(environment["GEMINI_API_KEY"])
                || hasValue(environment["GOOGLE_API_KEY"])
                || hasValue(environment["GOOGLE_GENAI_API_KEY"])
        default:
            return true
        }
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
