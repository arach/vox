import SwiftUI
import HudsonUI
import VoxCore

struct EmbedDemoTab: View {
    @StateObject private var state = EmbedDemoState()

    var body: some View {
        VoxScreen(
            title: "Embed Demo",
            badge: "IN PROCESS",
            summary: "Exercise VoxEngine directly inside the macOS app. These controls bypass the companion daemon and keep warm-up cost visible.",
            showGrid: true
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: HudSpacing.xl)],
                alignment: .leading,
                spacing: HudSpacing.xl
            ) {
                VoxMetricCard(
                    label: "TTS",
                    value: state.voiceModel?.name ?? "Loading",
                    detail: state.voiceModel?.backend ?? "mlx-audio",
                    tint: HudPalette.statusInfo
                )
                VoxMetricCard(
                    label: "ASR",
                    value: state.asrModel?.name ?? "Loading",
                    detail: state.asrModel?.backend ?? "parakeet",
                    tint: HudPalette.statusOk
                )
                VoxMetricCard(
                    label: "State",
                    value: state.isBusy ? "Working" : "Ready",
                    detail: state.selectedAudioFileURL?.lastPathComponent ?? "No audio selected",
                    tint: state.isBusy ? HudPalette.statusWarn : HudPalette.muted,
                    pulses: state.isBusy
                )
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack {
                        HudSectionLabel("Speech")
                        Spacer()
                        HudBadge("MLX TTS", tint: HudPalette.statusInfo, dot: true)
                    }

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow("Model", value: state.voiceModel?.name ?? "Loading...")
                            HudKVRow("Backend", value: state.voiceModel?.backend ?? "mlx-audio")
                            HudKVRow("Voice", value: state.selectedVoiceID ?? "Provider default")
                        }
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
                    .pickerStyle(.menu)
                    .disabled(state.voices.isEmpty)

                    TextEditor(text: $state.speechText)
                        .font(HudFont.ui(13))
                        .foregroundStyle(HudPalette.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(HudSpacing.md)
                        .background(RoundedRectangle(cornerRadius: HudRadius.standard).fill(HudSurface.inset))
                        .overlay(RoundedRectangle(cornerRadius: HudRadius.standard).stroke(HudHairline.subtle, lineWidth: 1))

                    HStack(spacing: HudSpacing.md) {
                        HudButton("Warm Speech", icon: "flame", style: .secondary) {
                            state.preloadSpeech()
                        }
                        .disabled(state.isBusy)

                        HudButton("Speak", icon: "speaker.wave.2", style: .primary(.cyan)) {
                            state.synthesizeAndPlay()
                        }
                        .disabled(state.isBusy)

                        Spacer()
                    }

                    HudInset {
                        VoxBodyText(state.speechStatus)
                    }

                    if let metrics = state.lastSynthesisMetrics {
                        MetricsPanel(title: "Synthesis Metrics") {
                            HudKVRow("Load", value: "\(metrics.modelLoadMs)ms")
                            HudKVRow("Voice", value: "\(metrics.voiceResolveMs)ms")
                            HudKVRow("Synthesis", value: "\(metrics.synthesisMs)ms")
                            HudKVRow("Total", value: "\(metrics.totalMs)ms", valueColor: HudPalette.statusInfo)
                        }
                    }
                }
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack {
                        HudSectionLabel("Transcription")
                        Spacer()
                        HudBadge("PARAKEET", tint: HudPalette.statusOk, dot: true)
                    }

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow("Model", value: state.asrModel?.name ?? "Loading...")
                            HudKVRow("Backend", value: state.asrModel?.backend ?? "parakeet")
                            HudKVRow("Audio File", value: state.selectedAudioFileURL?.lastPathComponent ?? "None")
                        }
                    }

                    HStack(spacing: HudSpacing.md) {
                        HudButton("Choose Audio", icon: "waveform", style: .secondary) {
                            state.chooseAudioFile()
                        }
                        .disabled(state.isBusy)

                        HudButton("Warm ASR", icon: "flame", style: .secondary) {
                            state.preloadASR()
                        }
                        .disabled(state.isBusy)

                        HudButton("Transcribe", icon: "text.bubble", style: .primary(.cyan)) {
                            state.transcribeSelectedFile()
                        }
                        .disabled(state.isBusy || state.selectedAudioFileURL == nil)

                        Spacer()
                    }

                    HudInset {
                        VoxBodyText(state.transcriptionStatus)
                    }

                    if let metrics = state.lastTranscriptionMetrics {
                        MetricsPanel(title: "Transcription Metrics") {
                            HudKVRow("Load", value: "\(metrics.modelLoadMs)ms")
                            HudKVRow("Audio", value: "\(metrics.audioLoadMs)ms")
                            HudKVRow("Infer", value: "\(metrics.inferenceMs)ms")
                            HudKVRow("Total", value: "\(metrics.totalMs)ms", valueColor: HudPalette.statusOk)
                        }
                    }

                    if state.transcriptText.isEmpty {
                        VoxEmptyList(
                            title: "No transcript yet",
                            subtitle: "Choose an audio file and run transcription to inspect the local ASR result.",
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
                            .frame(minHeight: 130)
                        }
                    }
                }
            }
        }
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
