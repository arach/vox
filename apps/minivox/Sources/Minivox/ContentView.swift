import AppKit
import SwiftUI
import VoxCore

struct ContentView: View {
    @ObservedObject var model: MinivoxModel
    @AppStorage("minivox.appearance") private var appearanceRawValue = MinivoxAppearance.system.rawValue
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        ZStack {
            background

            VStack(spacing: 14) {
                header
                recordCard
                transcriptCard
                preferencesCard
                footer
            }
            .padding(18)
        }
        .frame(width: 420, height: 650)
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .task {
            model.loadIfNeeded()
        }
        .onDisappear {
            model.cancelShortcutCapture()
        }
    }

    private var background: some View {
        ZStack {
            palette.background

            LinearGradient(
                colors: [
                    palette.background,
                    palette.backgroundSecondary,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.accentColor.opacity(palette.accentGlowOpacity), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 280
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.orange.opacity(0.88)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                MiniWave(color: .white)
                    .frame(width: 24, height: 18)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Color.accentColor.opacity(0.22), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("Minivox")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .tracking(-0.4)

                Text("tiny local dictation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            ActivityPill(
                title: statusTitle,
                tint: statusTint,
                isRecording: model.isRecording,
                isBusy: model.isWorking || model.isWarmingASR,
                surface: palette.card,
                border: palette.border
            )
        }
    }

    private var preferencesCard: some View {
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Picker("Appearance", selection: $appearanceRawValue) {
                    ForEach(MinivoxAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 176)
            }

            Divider()

            HStack(spacing: 12) {
                Label("Dictation shortcut", systemImage: "command")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button {
                        if model.isCapturingShortcut {
                            model.cancelShortcutCapture()
                        } else {
                            model.beginShortcutCapture()
                        }
                    } label: {
                        Text(
                            model.isCapturingShortcut
                                ? "Press shortcut…"
                                : model.dictationShortcut?.title ?? "Set shortcut"
                        )
                        .font(.caption.monospaced())
                        .frame(minWidth: 92)
                    }
                    .buttonStyle(.bordered)
                    .tint(model.isCapturingShortcut ? .accentColor : nil)

                    if model.dictationShortcut != nil && !model.isCapturingShortcut {
                        Button {
                            model.disableShortcut()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                        .help("Turn off the global shortcut")
                    }
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    private var recordCard: some View {
        VStack(spacing: 14) {
            Button(action: model.toggleRecording) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.button,
                                    palette.buttonSecondary,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 112, height: 112)
                        .shadow(color: .black.opacity(0.12), radius: 22, y: 12)

                    Circle()
                        .strokeBorder(recordRingColor, lineWidth: model.isRecording ? 9 : 6)
                        .frame(width: 112, height: 112)

                    if model.isWorking {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.primary)
                    } else {
                        Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isWorking || model.isWarmingASR)
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isRecording ? "Stop and transcribe" : "Start dictation")

            VStack(spacing: 4) {
                Text(recordTitle)
                    .font(.headline)

                Text(recordHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if model.isRecording {
                MiniWave(color: .red)
                    .frame(width: 58, height: 18)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DICTATION")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)

                Spacer()

                if !model.transcript.isEmpty {
                    Button {
                        model.copyTranscript()
                    } label: {
                        Label(model.didCopy ? "Copied" : "Copy", systemImage: model.didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)

                    Button("Clear") {
                        model.clearTranscript()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }

            Group {
                if model.transcript.isEmpty {
                    Text("Your words will land here—and copy themselves when the dictation is ready.")
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(showsIndicators: false) {
                        Text(model.transcript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 112, alignment: .topLeading)

            if let metrics = model.transcriptionMetrics {
                HStack(spacing: 16) {
                    Metric(label: "load", value: "\(metrics.modelLoadMs)ms")
                    Metric(label: "transcribe", value: "\(metrics.inferenceMs)ms")
                    Metric(label: "total", value: "\(metrics.totalMs)ms")
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let error = model.lastErrorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if model.asrReadyInMemory {
                    Label("Parakeet ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        model.warmASR()
                    } label: {
                        Label(model.isWarmingASR ? "Warming up…" : "Warm up Parakeet", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isRecording || model.isWorking || model.isWarmingASR)
                }

                Spacer(minLength: 0)

                Text(model.microphoneStatus)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit Minivox")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(model.statusMessage)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusTitle: String {
        if model.isRecording { return "listening" }
        if model.isWarmingASR { return "warming" }
        if model.isWorking { return "transcribing" }
        if model.asrReadyInMemory { return "ready" }
        return "cold"
    }

    private var statusTint: Color {
        if model.isRecording { return .red }
        if model.isWorking || model.isWarmingASR { return .orange }
        if model.asrReadyInMemory { return .green }
        return .secondary
    }

    private var recordTitle: String {
        if model.isRecording { return "Tap to finish" }
        if model.isWarmingASR { return "Getting Parakeet ready…" }
        if model.isWorking { return "Turning speech into text…" }
        return "Tap to dictate"
    }

    private var recordHint: String {
        if model.isRecording { return "Speak naturally. Minivox is listening." }
        if model.isWarmingASR { return "The shortcut will work as soon as the model is ready." }
        if model.isWorking { return "The transcript will copy itself when it is ready." }
        return "Press Space or click the microphone."
    }

    private var recordRingColor: Color {
        if model.isRecording { return .red.opacity(0.62) }
        if model.isWorking || model.isWarmingASR { return .orange.opacity(0.4) }
        return Color.accentColor.opacity(0.34)
    }

    private var selectedAppearance: MinivoxAppearance {
        MinivoxAppearance(rawValue: appearanceRawValue) ?? .system
    }

    private var palette: MinivoxPalette {
        MinivoxPalette(colorScheme: effectiveColorScheme)
    }

    private var effectiveColorScheme: ColorScheme {
        selectedAppearance.colorScheme ?? systemColorScheme
    }
}

private struct ActivityPill: View {
    let title: String
    let tint: Color
    let isRecording: Bool
    let isBusy: Bool
    let surface: Color
    let border: Color

    var body: some View {
        HStack(spacing: 7) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
            } else {
                ZStack {
                    if isRecording {
                        Circle()
                            .fill(tint.opacity(0.2))
                            .frame(width: 13, height: 13)
                    }
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                }
                .frame(width: 13, height: 13)
            }

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(surface, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
    }
}

private struct MinivoxPalette {
    let colorScheme: ColorScheme

    var background: Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.055, blue: 0.065)
            : Color(red: 0.975, green: 0.968, blue: 0.955)
    }

    var backgroundSecondary: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.09, blue: 0.105)
            : Color(red: 0.94, green: 0.95, blue: 0.94)
    }

    var card: Color {
        colorScheme == .dark
            ? Color(red: 0.115, green: 0.115, blue: 0.13)
            : Color.white.opacity(0.94)
    }

    var button: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.16, blue: 0.18)
            : Color.white
    }

    var buttonSecondary: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.09, blue: 0.105)
            : Color(red: 0.93, green: 0.93, blue: 0.91)
    }

    var border: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.09)
    }

    var accentGlowOpacity: Double {
        colorScheme == .dark ? 0.15 : 0.08
    }
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct MiniWave: View {
    let color: Color

    private let heights: [CGFloat] = [6, 12, 18, 10, 15, 7]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 2.5, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}
