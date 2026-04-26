import SwiftUI
import VoxCore

struct EmbedDemoTab: View {
    @StateObject private var state = EmbedDemoState()

    var body: some View {
        Form {
            Section {
                Text("This tab uses VoxEngine directly inside the macOS app. No local daemon is required for the actions below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Embed Demo")
            }

            Section {
                LabeledContent("Model") {
                    Text(state.voiceModel?.name ?? "Loading...")
                }

                LabeledContent("Backend") {
                    Text(state.voiceModel?.backend ?? "kokoro")
                }

                Picker("Voice", selection: Binding(
                    get: { state.selectedVoiceID ?? "" },
                    set: { state.selectedVoiceID = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(state.voices, id: \.id) { voice in
                        Text(voiceLabel(voice))
                            .tag(voice.id)
                    }
                }

                TextEditor(text: $state.speechText)
                    .font(.system(.body, design: .default))
                    .frame(minHeight: 110)

                HStack {
                    Button("Warm Speech") {
                        state.preloadSpeech()
                    }
                    .disabled(state.isBusy)

                    Button("Speak") {
                        state.synthesizeAndPlay()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isBusy)
                }

                Text(state.speechStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let metrics = state.lastSynthesisMetrics {
                    MetricsGrid {
                        MetricCell(label: "Load", value: "\(metrics.modelLoadMs)ms")
                        MetricCell(label: "Voice", value: "\(metrics.voiceResolveMs)ms")
                        MetricCell(label: "Synthesis", value: "\(metrics.synthesisMs)ms")
                        MetricCell(label: "Total", value: "\(metrics.totalMs)ms")
                    }
                }
            } header: {
                Text("Speech")
            } footer: {
                Text("The app synthesizes audio in process with VoxEngine and the Vox Kokoro speech path.")
            }

            Section {
                LabeledContent("Model") {
                    Text(state.asrModel?.name ?? "Loading...")
                }

                LabeledContent("Backend") {
                    Text(state.asrModel?.backend ?? "parakeet")
                }

                LabeledContent("Audio File") {
                    Text(state.selectedAudioFileURL?.lastPathComponent ?? "None")
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Button("Choose Audio") {
                        state.chooseAudioFile()
                    }
                    .disabled(state.isBusy)

                    Button("Warm ASR") {
                        state.preloadASR()
                    }
                    .disabled(state.isBusy)

                    Button("Transcribe") {
                        state.transcribeSelectedFile()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isBusy || state.selectedAudioFileURL == nil)
                }

                Text(state.transcriptionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let metrics = state.lastTranscriptionMetrics {
                    MetricsGrid {
                        MetricCell(label: "Load", value: "\(metrics.modelLoadMs)ms")
                        MetricCell(label: "Audio", value: "\(metrics.audioLoadMs)ms")
                        MetricCell(label: "Infer", value: "\(metrics.inferenceMs)ms")
                        MetricCell(label: "Total", value: "\(metrics.totalMs)ms")
                    }
                }

                if !state.transcriptText.isEmpty {
                    ScrollView {
                        Text(state.transcriptText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 130)
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text("The first transcription may download and load the local Parakeet model.")
            }
        }
        .formStyle(.grouped)
        .task {
            state.loadIfNeeded()
        }
    }

    private func voiceLabel(_ voice: TTSVoiceInfo) -> String {
        if let language = voice.language, !language.isEmpty {
            return voice.isDefault ? "\(voice.name) (\(language)) · default" : "\(voice.name) (\(language))"
        }
        return voice.isDefault ? "\(voice.name) · default" : voice.name
    }
}

private struct MetricsGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            content
        }
        .padding(.vertical, 4)
    }
}

private struct MetricCell: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}
