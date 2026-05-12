import SwiftUI
import HudsonUI
import VoxCore

struct SpeechCheckTab: View {
    @ObservedObject var speechPreferences: SpeechPreferencesState
    @StateObject private var state = SpeechCheckState()

    var body: some View {
        VoxScreen(
            title: "Speech Check",
            badge: "LOCAL",
            summary: "Run a short voice and microphone check against the configured Vox runtime."
        ) {
            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Input And Permissions")

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow("ASR Model", value: selectedTranscriptionModelLabel)
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
                            .pickerStyle(.menu)
                            .disabled(state.isBusy || state.isRecording || speechPreferences.inputDevices.isEmpty)

                            micPermissionRow
                        }
                    }
                }
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Voice Check")

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
