import SwiftUI
import HudsonUI
import VoxCore
import VoxEngine

struct TTSConfigTab: View {
    @ObservedObject var speechPreferences: SpeechPreferencesState
    @StateObject private var state = SpeechCheckState()

    var body: some View {
        VoxScreen(
            title: "Configure TTS",
            badge: "SPEECH OUT",
            summary: "Choose the synthesis provider, save provider credentials, select a voice, and play a short check."
        ) {
            providerCredentialsCard
            synthesisDefaultsCard
            voiceCheckCard
        }
        .task {
            await speechPreferences.refreshOptions()
        }
    }

    private var providerCredentialsCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack {
                    HudSectionLabel("OpenAI")
                    Spacer()
                    VoxStatusText(
                        speechPreferences.openAIKeyConfigured ? "KEY STORED" : "NO KEY",
                        tint: speechPreferences.openAIKeyConfigured ? HudPalette.statusOk : HudPalette.statusWarn
                    )
                }

                HudInset {
                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        HudKVRow(
                            "Credential",
                            value: speechPreferences.openAIKeyConfigured
                                ? "stored encrypted (\(speechPreferences.openAIKeyPreview))"
                                : "not stored",
                            valueColor: speechPreferences.openAIKeyConfigured ? HudPalette.muted : HudPalette.statusWarn
                        )
                        HudKVRow(
                            "Model",
                            value: speechPreferences.openAITTSModel?.id ?? TTSDefaults.modelId,
                            valueColor: speechPreferences.openAITTSReady ? HudPalette.muted : HudPalette.statusWarn
                        )
                    }
                }

                HudSecretField(
                    "sk-...",
                    text: $speechPreferences.openAIAPIKeyInput,
                    icon: "key.fill"
                )

                HStack(spacing: HudSpacing.md) {
                    HudButton("Save Key", icon: "lock", style: .primary(.cyan)) {
                        speechPreferences.saveOpenAIAPIKey()
                    }
                    .disabled(speechPreferences.openAIAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    HudButton("Use OpenAI TTS", icon: "speaker.wave.2", style: .secondary) {
                        Task { await speechPreferences.useOpenAITTS() }
                    }

                    if speechPreferences.openAIKeyConfigured {
                        HudButton("Remove", icon: "trash", style: .ghost) {
                            speechPreferences.deleteOpenAIAPIKey()
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var synthesisDefaultsCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack {
                    HudSectionLabel("Synthesis Default")
                    Spacer()
                    VoxStatusText(
                        speechPreferences.effectiveSynthesisAvailabilityLabel.uppercased(),
                        tint: speechPreferences.effectiveSynthesisNeedsAPIKey ? HudPalette.statusWarn : HudPalette.muted
                    )
                }

                HudInset {
                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        HudKVRow("Model", value: speechPreferences.effectiveSynthesisModelId)
                        HudKVRow("Backend", value: speechPreferences.effectiveSynthesisBackendLabel, valueColor: HudPalette.muted)
                        HudKVRow("Voice", value: speechPreferences.effectiveSynthesisVoiceLabel, valueColor: HudPalette.muted)
                    }
                }

                VStack(alignment: .leading, spacing: HudSpacing.md) {
                    Picker(
                        "Model",
                        selection: Binding(
                            get: { speechPreferences.preferredSynthesisModelId },
                            set: { newValue in
                                Task {
                                    await speechPreferences.updatePreferredSynthesisModelId(newValue)
                                }
                            }
                        )
                    ) {
                        Text("Vox Default (\(speechPreferences.defaultSynthesisModelId))")
                            .tag("")
                        ForEach(speechPreferences.ttsModels, id: \.id) { model in
                            Text(ttsModelLabel(model))
                                .tag(model.id)
                        }
                    }

                    Picker(
                        "Voice",
                        selection: Binding(
                            get: { speechPreferences.preferredSynthesisVoiceId },
                            set: { newValue in
                                speechPreferences.updatePreferredSynthesisVoiceId(newValue)
                            }
                        )
                    ) {
                        Text("Provider Default")
                            .tag("")
                        ForEach(speechPreferences.voices, id: \.id) { voice in
                            Text(voiceLabel(voice))
                                .tag(voice.id)
                        }
                    }
                    .disabled(speechPreferences.voices.isEmpty)
                }
                .pickerStyle(.menu)

                HStack(spacing: HudSpacing.md) {
                    HudButton("Refresh Models", icon: "arrow.clockwise", style: .secondary) {
                        Task { await speechPreferences.refreshOptions() }
                    }
                    Spacer(minLength: 0)
                }

                if let statusMessage = speechPreferences.statusMessage, !statusMessage.isEmpty {
                    HudInset {
                        VoxBodyText(statusMessage)
                    }
                }
            }
        }
    }

    private var voiceCheckCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack {
                    HudSectionLabel("Quick TTS Test")
                    Spacer()
                    if state.isBusy {
                        VoxStatusText("WORKING", tint: HudPalette.statusWarn)
                    }
                }

                ttsInput

                HStack(spacing: HudSpacing.md) {
                    HudButton("Speak Text", icon: "speaker.wave.2", style: .primary(.cyan)) {
                        state.playVoiceSample(
                            modelId: speechPreferences.effectiveSynthesisModelId,
                            voiceId: speechPreferences.effectiveSynthesisVoice?.id,
                            text: state.synthesisText
                        )
                    }
                    .disabled(state.isBusy || speechPreferences.effectiveSynthesisNeedsAPIKey || synthesisInputIsEmpty)

                    Spacer(minLength: 0)
                }

                HudInset {
                    VoxBodyText(
                        state.status,
                        tint: speechPreferences.effectiveSynthesisNeedsAPIKey ? HudPalette.statusWarn : HudPalette.muted
                    )
                }

                if let metrics = state.lastSynthesisMetrics {
                    MetricsPanel(title: "Synthesis Metrics") {
                        HudKVRow("Load", value: "\(metrics.modelLoadMs)ms")
                        HudKVRow("Voice", value: "\(metrics.voiceResolveMs)ms")
                        HudKVRow("Synthesis", value: "\(metrics.synthesisMs)ms")
                        HudKVRow("Total", value: "\(metrics.totalMs)ms", valueColor: HudPalette.muted)
                    }
                }
            }
        }
    }

    private var ttsInput: some View {
        TextField("Text to synthesize", text: $state.synthesisText, axis: .vertical)
            .font(HudFont.ui(HudTextSize.sm))
            .foregroundStyle(HudPalette.ink)
            .lineLimit(2...4)
            .textFieldStyle(.plain)
            .padding(HudSpacing.md)
            .background(
                HudPalette.surface.opacity(0.35),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(HudHairline.subtle, lineWidth: 1)
            )
            .disabled(state.isBusy)
    }

    private var synthesisInputIsEmpty: Bool {
        state.synthesisText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func ttsModelLabel(_ model: TTSModelInfo) -> String {
        let suffix = model.available && model.installed ? model.backend : "\(model.backend) · unavailable"
        return "\(model.id) · \(suffix)"
    }

    private func voiceLabel(_ voice: TTSVoiceInfo) -> String {
        if let language = voice.language, !language.isEmpty {
            return voice.isDefault ? "\(voice.name) (\(language)) · default" : "\(voice.name) (\(language))"
        }
        return voice.isDefault ? "\(voice.name) · default" : voice.name
    }
}

struct ASRConfigTab: View {
    @ObservedObject var speechPreferences: SpeechPreferencesState
    @StateObject private var state = SpeechCheckState()

    var body: some View {
        VoxScreen(
            title: "Configure ASR",
            badge: "SPEECH IN",
            summary: "Choose the transcription model and microphone input, then record a short dictation check."
        ) {
            transcriptionDefaultsCard
            dictationCheckCard
        }
        .task {
            await speechPreferences.refreshOptions()
            state.refreshInputDevices(speechPreferences)
        }
    }

    private var transcriptionDefaultsCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HudSectionLabel("Transcription Default")

                HudInset {
                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        HudKVRow("ASR Model", value: speechPreferences.effectiveTranscriptionModelId)
                        HudKVRow("Input Device", value: speechPreferences.effectiveInputDeviceLabel, valueColor: HudPalette.muted)
                        micPermissionRow
                    }
                }

                VStack(alignment: .leading, spacing: HudSpacing.md) {
                    Picker(
                        "Model",
                        selection: Binding(
                            get: { speechPreferences.preferredTranscriptionModelId },
                            set: { newValue in
                                speechPreferences.updatePreferredTranscriptionModelId(newValue)
                            }
                        )
                    ) {
                        Text("Vox Default (parakeet:v3)")
                            .tag("")
                        ForEach(speechPreferences.asrModels, id: \.id) { model in
                            Text("\(model.id) · \(model.backend)")
                                .tag(model.id)
                        }
                    }

                    Picker(
                        "Input Device",
                        selection: Binding(
                            get: { speechPreferences.preferredInputDeviceId },
                            set: { newValue in
                                speechPreferences.updatePreferredInputDeviceId(newValue)
                            }
                        )
                    ) {
                        Text("System Default")
                            .tag("")
                        ForEach(speechPreferences.inputDevices) { device in
                            Text(device.isSystemDefault ? "\(device.name) · system default" : device.name)
                                .tag(device.id)
                        }
                    }
                    .disabled(speechPreferences.inputDevices.isEmpty)
                }
                .pickerStyle(.menu)

                HStack(spacing: HudSpacing.md) {
                    HudButton("Refresh Inputs", icon: "arrow.clockwise", style: .secondary) {
                        Task { await speechPreferences.refreshOptions() }
                    }
                    Spacer(minLength: 0)
                }

                if let statusMessage = speechPreferences.statusMessage, !statusMessage.isEmpty {
                    HudInset {
                        VoxBodyText(statusMessage)
                    }
                }
            }
        }
    }

    private var dictationCheckCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack {
                    HudSectionLabel("Dictation Check")
                    Spacer()
                    if state.isRecording {
                        VoxStatusText("RECORDING", tint: HudPalette.statusError)
                    }
                }

                HStack(spacing: HudSpacing.md) {
                    if state.isRecording {
                        HudButton("Stop And Transcribe", icon: "stop.fill", style: .primary(.cyan)) {
                            state.stopAndTranscribe(modelId: speechPreferences.effectiveTranscriptionModelId)
                        }
                        .disabled(state.isBusy)

                        HudButton("Cancel", icon: "xmark", style: .ghost) {
                            state.cancelRecording()
                        }
                        .disabled(state.isBusy)
                    } else {
                        HudButton("Record", icon: "mic.fill", style: .primary(.cyan)) {
                            state.startRecording(inputDeviceId: speechPreferences.preferredInputDeviceId)
                        }
                        .disabled(state.isBusy)
                    }

                    Spacer()
                }

                HudInset {
                    VoxBodyText(state.status, tint: state.isRecording ? HudPalette.statusError : HudPalette.muted)
                }

                if state.transcriptText.isEmpty {
                    VoxEmptyList(
                        title: "No transcript yet",
                        subtitle: "Record a short phrase to validate local transcription.",
                        icon: "text.alignleft"
                    )
                } else {
                    HudInset {
                        ScrollView {
                            Text(state.transcriptText)
                                .font(HudFont.ui(13))
                                .foregroundStyle(HudPalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 120)
                    }
                }

                if let metrics = state.lastTranscriptionMetrics {
                    MetricsPanel(title: "Transcription Metrics") {
                        HudKVRow("Duration", value: "\(metrics.audioDurationMs)ms")
                        HudKVRow("Load", value: "\(metrics.modelLoadMs)ms")
                        HudKVRow("Infer", value: "\(metrics.inferenceMs)ms")
                        HudKVRow("Total", value: "\(metrics.totalMs)ms", valueColor: HudPalette.muted)
                    }
                }
            }
        }
    }

    private var microphoneTint: Color {
        speechPreferences.microphonePermissionStatus == "authorized" ? HudPalette.statusOk : HudPalette.statusWarn
    }

    private var microphonePermissionIcon: String {
        speechPreferences.microphonePermissionStatus == "authorized"
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var microphonePermissionLabel: String {
        speechPreferences.microphonePermissionStatus == "authorized"
            ? "Authorized"
            : speechPreferences.microphonePermissionStatus
    }

    private var micPermissionRow: some View {
        VoxIconKVRow(
            label: "Mic Permission",
            value: microphonePermissionLabel,
            icon: microphonePermissionIcon,
            tint: microphoneTint
        )
    }
}

struct SpeechCheckTab: View {
    @ObservedObject var speechPreferences: SpeechPreferencesState
    @StateObject private var state = SpeechCheckState()

    var body: some View {
        VoxScreen(
            title: "Speech Check",
            badge: "LOCAL",
            summary: "Run a short voice and microphone check using the current Vox defaults."
        ) {
            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Current Defaults")

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow("ASR Model", value: selectedTranscriptionModelLabel)
                            HudKVRow("TTS Model", value: speechPreferences.effectiveSynthesisModelId)
                            HudKVRow("Voice", value: speechPreferences.effectiveSynthesisVoiceLabel, valueColor: HudPalette.muted)
                            HudKVRow("Input Device", value: speechPreferences.effectiveInputDeviceLabel, valueColor: HudPalette.muted)
                            micPermissionRow
                        }
                    }

                    VoxBodyText("Change model, voice, input, or credentials from Runtime. This screen only exercises the selected defaults.", tint: HudPalette.muted)
                }
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack {
                        HudSectionLabel("Voice Check")
                        Spacer()
                        VoxStatusText(
                            speechPreferences.effectiveSynthesisAvailabilityLabel.uppercased(),
                            tint: speechPreferences.effectiveSynthesisNeedsAPIKey ? HudPalette.statusWarn : HudPalette.muted
                        )
                    }

                    HStack(spacing: HudSpacing.md) {
                        HudButton("Play Voice", icon: "speaker.wave.2", style: .primary(.cyan)) {
                            state.playVoiceSample(
                                modelId: speechPreferences.effectiveSynthesisModelId,
                                voiceId: speechPreferences.effectiveSynthesisVoice?.id
                            )
                        }
                        .disabled(state.isBusy || state.isRecording || speechPreferences.effectiveSynthesisNeedsAPIKey)

                        Spacer()
                    }

                    HudInset {
                        VoxBodyText(state.voiceSampleText, tint: HudPalette.ink)
                    }

                    if let metrics = state.lastSynthesisMetrics {
                        MetricsPanel(title: "Synthesis Metrics") {
                            HudKVRow("Load", value: "\(metrics.modelLoadMs)ms")
                            HudKVRow("Voice", value: "\(metrics.voiceResolveMs)ms")
                            HudKVRow("Synthesis", value: "\(metrics.synthesisMs)ms")
                            HudKVRow("Total", value: "\(metrics.totalMs)ms", valueColor: HudPalette.muted)
                        }
                    }
                }
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack {
                        HudSectionLabel("Dictation Check")
                        Spacer()
                        if state.isRecording {
                            VoxStatusText("RECORDING", tint: HudPalette.statusError)
                        }
                    }

                    HStack(spacing: HudSpacing.md) {
                        if state.isRecording {
                            HudButton("Stop And Transcribe", icon: "stop.fill", style: .primary(.cyan)) {
                                state.stopAndTranscribe(modelId: selectedTranscriptionModelLabel)
                            }
                            .disabled(state.isBusy)

                            HudButton("Cancel", icon: "xmark", style: .ghost) {
                                state.cancelRecording()
                            }
                            .disabled(state.isBusy)
                        } else {
                            HudButton("Record", icon: "mic.fill", style: .primary(.cyan)) {
                                state.startRecording(inputDeviceId: speechPreferences.preferredInputDeviceId)
                            }
                            .disabled(state.isBusy)
                        }

                        Spacer()
                    }

                    HudInset {
                        VoxBodyText(state.status, tint: state.isRecording ? HudPalette.statusError : HudPalette.muted)
                    }

                    if state.transcriptText.isEmpty {
                        VoxEmptyList(
                            title: "No transcript yet",
                            subtitle: "Record a short phrase to validate local transcription.",
                            icon: "text.alignleft"
                        )
                    } else {
                        HudInset {
                            ScrollView {
                                Text(state.transcriptText)
                                    .font(HudFont.ui(13))
                                    .foregroundStyle(HudPalette.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 120)
                        }
                    }

                    if let metrics = state.lastTranscriptionMetrics {
                        MetricsPanel(title: "Transcription Metrics") {
                            HudKVRow("Duration", value: "\(metrics.audioDurationMs)ms")
                            HudKVRow("Load", value: "\(metrics.modelLoadMs)ms")
                            HudKVRow("Infer", value: "\(metrics.inferenceMs)ms")
                            HudKVRow("Total", value: "\(metrics.totalMs)ms", valueColor: HudPalette.muted)
                        }
                    }
                }
            }
        }
        .task {
            state.refreshInputDevices(speechPreferences)
        }
    }

    private var selectedTranscriptionModelLabel: String {
        speechPreferences.preferredTranscriptionModelId.isEmpty
            ? "parakeet:v3"
            : speechPreferences.preferredTranscriptionModelId
    }

    private var microphoneTint: Color {
        speechPreferences.microphonePermissionStatus == "authorized" ? HudPalette.statusOk : HudPalette.statusWarn
    }

    private var microphonePermissionIcon: String {
        speechPreferences.microphonePermissionStatus == "authorized"
            ? "checkmark.circle.fill"
            : "exclamationmark.triangle.fill"
    }

    private var microphonePermissionLabel: String {
        speechPreferences.microphonePermissionStatus == "authorized"
            ? "Authorized"
            : speechPreferences.microphonePermissionStatus
    }

    private var micPermissionRow: some View {
        VoxIconKVRow(
            label: "Mic Permission",
            value: microphonePermissionLabel,
            icon: microphonePermissionIcon,
            tint: microphoneTint
        )
    }
}

private struct MetricsPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HudInset {
            VStack(alignment: .leading, spacing: HudSpacing.md) {
                HudSectionLabel(title, tint: HudPalette.muted)
                content
            }
        }
    }
}
