import Foundation
import AVFoundation
import VoxBridge
import VoxCore
import VoxEngine
#if os(macOS)
import AppKit
#endif

struct AudioInputDeviceInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let isSystemDefault: Bool
}

@MainActor
final class SpeechPreferencesState: ObservableObject {
    @Published var preferredTranscriptionModelId = ""
    @Published var preferredSynthesisModelId = ""
    @Published var preferredSynthesisVoiceId = ""
    @Published var preferredInputDeviceId = ""
    @Published private(set) var asrModels: [ASRModelInfo] = []
    @Published private(set) var ttsModels: [TTSModelInfo] = []
    @Published private(set) var voices: [TTSVoiceInfo] = []
    @Published private(set) var inputDevices: [AudioInputDeviceInfo] = []
    @Published private(set) var microphonePermissionStatus = MicrophonePermission.statusString()
    @Published private(set) var defaultSynthesisModelId = TTSDefaults.modelId
    @Published private(set) var openAIKeyConfigured = false
    @Published private(set) var openAIKeyPreview = ""
    @Published var openAIAPIKeyInput = ""
    @Published var statusMessage: String?

    private let proxy = DaemonProxy()
    private let credentialStore = VoxCredentialStore()

    var effectiveSynthesisModelId: String {
        normalizedPreferenceValue(preferredSynthesisModelId) ?? defaultSynthesisModelId
    }

    var effectiveTranscriptionModelId: String {
        normalizedPreferenceValue(preferredTranscriptionModelId) ?? "parakeet:v3"
    }

    var effectiveSynthesisModel: TTSModelInfo? {
        ttsModels.first { $0.id == effectiveSynthesisModelId }
    }

    var effectiveSynthesisVoice: TTSVoiceInfo? {
        if let preferredVoiceId = normalizedPreferenceValue(preferredSynthesisVoiceId),
           let voice = voices.first(where: { $0.id == preferredVoiceId }) {
            return voice
        }
        return voices.first(where: { $0.isDefault }) ?? voices.first
    }

    var effectiveSynthesisBackendLabel: String {
        effectiveSynthesisModel?.backend ?? "unknown"
    }

    var effectiveSynthesisAvailabilityLabel: String {
        guard let model = effectiveSynthesisModel else {
            return ttsModels.isEmpty ? "models unavailable" : "not listed"
        }
        if model.available && model.installed {
            return model.preloaded ? "ready" : "available"
        }
        if isRemoteSynthesisModel(model) {
            return "needs API key"
        }
        if !model.installed {
            return "not installed"
        }
        return "provider offline"
    }

    var effectiveSynthesisNeedsAPIKey: Bool {
        guard let model = effectiveSynthesisModel else { return false }
        return isRemoteSynthesisModel(model) && !(model.available && model.installed)
    }

    var openAITTSModel: TTSModelInfo? {
        ttsModels.first { $0.id == TTSDefaults.modelId }
            ?? ttsModels.first { OpenAITTSProvider.supportedModelIDs.contains($0.id) }
    }

    var openAITTSReady: Bool {
        guard let model = openAITTSModel else { return openAIKeyConfigured }
        return model.available && model.installed
    }

    var effectiveSynthesisVoiceLabel: String {
        effectiveSynthesisVoice.map { voiceLabel($0) } ?? "Provider default"
    }

    var effectiveInputDeviceLabel: String {
        if let device = inputDevices.first(where: { $0.id == preferredInputDeviceId }) {
            return device.name
        }
        if let device = inputDevices.first(where: \.isSystemDefault) {
            return "System default · \(device.name)"
        }
        return "System default"
    }

    func load() async {
        loadPreferencesFromDisk()
        refreshInputDevices()
        refreshCredentialState()
        await refreshRemoteOptions()
    }

    func refreshOptions() async {
        refreshInputDevices()
        refreshCredentialState()
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

    func updatePreferredInputDeviceId(_ deviceId: String) {
        preferredInputDeviceId = deviceId
        savePreferences()
        refreshInputDevices()
    }

    func refreshInputDevices() {
        microphonePermissionStatus = MicrophonePermission.statusString()
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        inputDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
            .map { device in
                AudioInputDeviceInfo(
                    id: device.uniqueID,
                    name: device.localizedName,
                    isSystemDefault: device.uniqueID == defaultID
                )
            }
            .sorted { lhs, rhs in
                if lhs.isSystemDefault != rhs.isSystemDefault {
                    return lhs.isSystemDefault && !rhs.isSystemDefault
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        if !preferredInputDeviceId.isEmpty,
           !inputDevices.contains(where: { $0.id == preferredInputDeviceId }) {
            preferredInputDeviceId = ""
            savePreferences()
        }
    }

    func requestMicrophonePermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            statusMessage = "Microphone access is already authorized."
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            refreshInputDevices()
            statusMessage = granted
                ? "Microphone access granted."
                : "Microphone access was not granted."
        case .denied:
            refreshInputDevices()
            statusMessage = "Microphone access is denied. Enable Vox in System Settings."
        case .restricted:
            refreshInputDevices()
            statusMessage = "Microphone access is restricted by macOS policy."
        @unknown default:
            refreshInputDevices()
            statusMessage = "Microphone access is unavailable."
        }
    }

    func openMicrophonePrivacySettings() {
        #if os(macOS)
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security"
        ]
        for rawURL in settingsURLs {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                statusMessage = "Opened microphone privacy settings."
                return
            }
        }
        statusMessage = "Unable to open microphone privacy settings."
        #else
        statusMessage = "Open Privacy & Security settings to enable microphone access."
        #endif
    }

    func saveOpenAIAPIKey() {
        do {
            try credentialStore.setOpenAIAPIKey(openAIAPIKeyInput)
            openAIAPIKeyInput = ""
            refreshCredentialState()
            if !OpenAITTSProvider.supportedModelIDs.contains(effectiveSynthesisModelId) {
                preferredSynthesisModelId = TTSDefaults.modelId
                preferredSynthesisVoiceId = ""
                savePreferences()
            }
            statusMessage = "Saved encrypted OpenAI API key for Vox."
            Task { await refreshRemoteOptions() }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteOpenAIAPIKey() {
        do {
            try credentialStore.deleteOpenAIAPIKey()
            refreshCredentialState()
            statusMessage = "Removed Vox OpenAI API key."
            Task { await refreshRemoteOptions() }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func useOpenAITTS() async {
        preferredSynthesisModelId = TTSDefaults.modelId
        preferredSynthesisVoiceId = ""
        savePreferences()
        await refreshRemoteOptions()
        statusMessage = openAIKeyConfigured
            ? "OpenAI TTS is now the Vox synthesis default."
            : "OpenAI TTS selected. Add an OpenAI API key before testing voice output."
    }

    private func loadPreferencesFromDisk() {
        let preferences = (try? VoxPreferences.load()) ?? VoxPreferences()
        preferredTranscriptionModelId = preferences.speech.preferredTranscriptionModelId ?? ""
        preferredSynthesisModelId = preferences.speech.preferredSynthesisModelId ?? ""
        preferredSynthesisVoiceId = preferences.speech.preferredSynthesisVoiceId ?? ""
        preferredInputDeviceId = preferences.speech.preferredInputDeviceId ?? ""
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
            preferences.speech.preferredInputDeviceId =
                normalizedPreferenceValue(preferredInputDeviceId)
            try preferences.save()
            statusMessage = "Saved Vox-wide speech defaults."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshCredentialState() {
        let state = credentialStore.state()
        openAIKeyConfigured = state.openAIConfigured
        openAIKeyPreview = state.openAIPreview ?? ""
    }

    private func refreshRemoteOptions() async {
        do {
            if !(await proxy.isConnected) {
                try await proxy.connect()
            }
            defer {
                Task {
                    await proxy.disconnect()
                }
            }

            let asrResult = try await proxy.call("models.list")
            asrModels = parseASRModels(asrResult["models"])

            let ttsResult = try await proxy.call("synthesize.models")
            ttsModels = parseTTSModels(ttsResult["models"])
            defaultSynthesisModelId = recommendedSynthesisModelId()

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
            defer {
                Task {
                    await proxy.disconnect()
                }
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

        return defaultSynthesisModelId
    }

    private func recommendedSynthesisModelId() -> String {
        let availableModels = ttsModels.filter { $0.available && $0.installed }
        let candidateModels = availableModels.isEmpty ? ttsModels : availableModels

        return candidateModels.first { $0.id == TTSDefaults.modelId }?.id
            ?? candidateModels.first { OpenAITTSProvider.supportedModelIDs.contains($0.id) }?.id
            ?? candidateModels.first?.id
            ?? TTSDefaults.modelId
    }

    private func normalizedPreferenceValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func voiceLabel(_ voice: TTSVoiceInfo) -> String {
        if let language = voice.language, !language.isEmpty {
            return "\(voice.name) (\(language))"
        }
        return voice.name
    }

    private func isRemoteSynthesisModel(_ model: TTSModelInfo) -> Bool {
        switch model.backend.lowercased() {
        case "openai", "elevenlabs", "minimax":
            return true
        default:
            return OpenAITTSProvider.supportedModelIDs.contains(model.id)
                || ElevenLabsTTSProvider.supportedModelIDs.contains(model.id)
                || MiniMaxTTSProvider.supportedModelIDs.contains(model.id)
        }
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
