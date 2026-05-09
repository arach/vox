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

        if let preferredAvailable = availableConfiguredModels.first(where: { $0 != TTSDefaults.modelId }) {
            return preferredAvailable
        }

        if let firstAvailable = availableConfiguredModels.first {
            return firstAvailable
        }

        let configuredModels = entries.flatMap { $0.models ?? [] }
        return configuredModels.first ?? TTSDefaults.modelId
    }

    private static func isAvailableForDefaultSelection(
        _ entry: ProviderEntry,
        environment: [String: String]
    ) -> Bool {
        guard entry.id == "openai-tts" else {
            return true
        }

        return hasValue(entry.env?["OPENAI_API_KEY"])
            || hasValue(environment["OPENAI_API_KEY"])
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
