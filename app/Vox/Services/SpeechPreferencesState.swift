import Foundation
import VoxBridge
import VoxCore
import VoxEngine

@MainActor
final class SpeechPreferencesState: ObservableObject {
    @Published var preferredTranscriptionModelId = ""
    @Published var preferredSynthesisModelId = ""
    @Published var preferredSynthesisVoiceId = ""
    @Published private(set) var asrModels: [ASRModelInfo] = []
    @Published private(set) var ttsModels: [TTSModelInfo] = []
    @Published private(set) var voices: [TTSVoiceInfo] = []
    @Published var statusMessage: String?

    private let proxy = DaemonProxy()

    func load() async {
        loadPreferencesFromDisk()
        await refreshRemoteOptions()
    }

    func updatePreferredTranscriptionModelId(_ modelId: String) {
        preferredTranscriptionModelId = modelId
        savePreferences()
    }

    func updatePreferredSynthesisModelId(_ modelId: String) async {
        preferredSynthesisModelId = modelId
        preferredSynthesisVoiceId = ""
        savePreferences()
        await refreshVoices()
    }

    func updatePreferredSynthesisVoiceId(_ voiceId: String) {
        preferredSynthesisVoiceId = voiceId
        savePreferences()
    }

    private func loadPreferencesFromDisk() {
        let preferences = (try? VoxPreferences.load()) ?? VoxPreferences()
        preferredTranscriptionModelId = preferences.speech.preferredTranscriptionModelId ?? ""
        preferredSynthesisModelId = preferences.speech.preferredSynthesisModelId ?? ""
        preferredSynthesisVoiceId = preferences.speech.preferredSynthesisVoiceId ?? ""
    }

    private func savePreferences() {
        do {
            var preferences = (try? VoxPreferences.load()) ?? VoxPreferences()
            preferences.speech.preferredTranscriptionModelId =
                normalizedPreferenceValue(preferredTranscriptionModelId)
            preferences.speech.preferredSynthesisModelId =
                normalizedPreferenceValue(preferredSynthesisModelId)
            preferences.speech.preferredSynthesisVoiceId =
                normalizedPreferenceValue(preferredSynthesisVoiceId)
            try preferences.save()
            statusMessage = "Saved Vox-wide speech defaults."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshRemoteOptions() async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            let asrResult = try await proxy.call("models.list")
            asrModels = parseASRModels(asrResult["models"])

            let ttsResult = try await proxy.call("synthesize.models")
            ttsModels = parseTTSModels(ttsResult["models"])

            await refreshVoices()

            if statusMessage == nil {
                statusMessage = "These defaults apply across Vox clients unless an app explicitly overrides them."
            }
        } catch {
            statusMessage = "Saved defaults still apply, but live model lists need the daemon running."
        }
    }

    private func refreshVoices() async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }

            guard let modelId = resolvedVoiceModelId() else {
                voices = []
                preferredSynthesisVoiceId = ""
                return
            }

            let result = try await proxy.call("synthesize.voices", params: ["modelId": modelId])
            voices = parseVoices(result["voices"])

            if !preferredSynthesisVoiceId.isEmpty,
               !voices.contains(where: { $0.id == preferredSynthesisVoiceId })
            {
                preferredSynthesisVoiceId = ""
            }
        } catch {
            voices = []
        }
    }

    private func resolvedVoiceModelId() -> String? {
        if let preferredModelId = normalizedPreferenceValue(preferredSynthesisModelId) {
            return preferredModelId
        }

        if ttsModels.contains(where: { $0.id == TTSDefaults.modelId }) {
            return TTSDefaults.modelId
        }

        return ttsModels.first?.id
    }

    private func normalizedPreferenceValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseASRModels(_ raw: Any?) -> [ASRModelInfo] {
        guard let models = raw as? [[String: Any]] else {
            return []
        }

        return models.compactMap { model in
            guard let id = model["id"] as? String,
                  let name = model["name"] as? String,
                  let backend = model["backend"] as? String,
                  let installed = model["installed"] as? Bool,
                  let preloaded = model["preloaded"] as? Bool,
                  let available = model["available"] as? Bool
            else {
                return nil
            }

            return ASRModelInfo(
                id: id,
                name: name,
                backend: backend,
                installed: installed,
                preloaded: preloaded,
                available: available
            )
        }
    }

    private func parseTTSModels(_ raw: Any?) -> [TTSModelInfo] {
        guard let models = raw as? [[String: Any]] else {
            return []
        }

        return models.compactMap { model in
            guard let id = model["id"] as? String,
                  let name = model["name"] as? String,
                  let backend = model["backend"] as? String,
                  let installed = model["installed"] as? Bool,
                  let preloaded = model["preloaded"] as? Bool,
                  let available = model["available"] as? Bool
            else {
                return nil
            }

            return TTSModelInfo(
                id: id,
                name: name,
                backend: backend,
                installed: installed,
                preloaded: preloaded,
                available: available
            )
        }
    }

    private func parseVoices(_ raw: Any?) -> [TTSVoiceInfo] {
        guard let voices = raw as? [[String: Any]] else {
            return []
        }

        return voices.compactMap { voice in
            guard let id = voice["id"] as? String,
                  let name = voice["name"] as? String,
                  let backend = voice["backend"] as? String,
                  let modelId = voice["modelId"] as? String,
                  let available = voice["available"] as? Bool
            else {
                return nil
            }

            return TTSVoiceInfo(
                id: id,
                name: name,
                language: voice["language"] as? String,
                backend: backend,
                modelId: modelId,
                available: available,
                isDefault: (voice["default"] as? Bool) ?? false
            )
        }
    }
}
