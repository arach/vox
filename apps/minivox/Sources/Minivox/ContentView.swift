import AppKit
import SwiftUI
import VoxCore

struct ContentView: View {
    @ObservedObject var model: MinivoxModel
    @AppStorage("minivox.appearance") private var appearanceRawValue = MinivoxAppearance.system.rawValue
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        ZStack {
            palette.background

            VStack(spacing: 0) {
                headerStrip

                VStack(spacing: 10) {
                    recordDeck
                    transcriptDeck

                    if let message = visibleMessage {
                        Text(message)
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(model.lastErrorMessage == nil ? Color.secondary : Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(12)

                controlStrip
            }
        }
        .frame(width: 360)
        .environment(\.colorScheme, effectiveColorScheme)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .task {
            model.loadIfNeeded()
        }
        .onDisappear {
            model.cancelShortcutCapture()
        }
    }

    private var headerStrip: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.logoBackground)

                Text("M")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.logoForeground)
            }
            .frame(width: 30, height: 30)

            Text("Minivox")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(-0.2)

            Spacer(minLength: 0)

            ActivityIndicator(
                title: statusTitle,
                tint: statusTint,
                isBusy: model.isWorking || model.isWarmingASR
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(palette.strip)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.border)
                .frame(height: 0.5)
        }
    }

    private var recordDeck: some View {
        Button(action: model.toggleRecording) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(palette.controlFill)

                    if model.isWorking || model.isWarmingASR {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.controlForeground)
                    } else {
                        Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(palette.controlForeground)
                    }
                }
                .frame(width: 68, height: 68)

                Text(recordTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking || model.isWarmingASR)
        .keyboardShortcut(.space, modifiers: [])
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 0.5)
        }
        .help(model.isRecording ? "Stop and transcribe" : "Start dictation")
    }

    private var transcriptDeck: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if model.transcript.isEmpty {
                    Text("Transcription")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(showsIndicators: false) {
                        Text(model.transcript)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.trailing, 52)
                }
            }
            .font(.system(size: 15, weight: .light, design: .rounded))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 96, alignment: .topLeading)

            if !model.transcript.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        model.copyTranscript()
                    } label: {
                        Image(systemName: model.didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .help(model.didCopy ? "Copied" : "Copy")

                    Button {
                        model.clearTranscript()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .help("Clear")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 0.5)
        }
    }

    private var controlStrip: some View {
        HStack(spacing: 8) {
            Picker("Appearance", selection: $appearanceRawValue) {
                Image(systemName: "circle.lefthalf.filled")
                    .tag(MinivoxAppearance.system.rawValue)
                Image(systemName: "sun.max")
                    .tag(MinivoxAppearance.light.rawValue)
                Image(systemName: "moon")
                    .tag(MinivoxAppearance.dark.rawValue)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 98)
            .tint(palette.controlTint)
            .help("Appearance")

            Rectangle()
                .fill(palette.border)
                .frame(width: 0.5, height: 20)

            Button {
                if model.isCapturingShortcut {
                    model.cancelShortcutCapture()
                } else {
                    model.beginShortcutCapture()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "command")

                    if model.isCapturingShortcut {
                        Text("…")
                    } else if let shortcut = model.dictationShortcut {
                        Text(shortcut.title)
                    }
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .frame(minWidth: 44)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(palette.controlSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.dictationShortcut == nil ? "Set shortcut" : "Change shortcut")

            if model.dictationShortcut != nil && !model.isCapturingShortcut {
                Button {
                    model.disableShortcut()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Clear shortcut")
            }

            Spacer(minLength: 0)

            if !model.asrReadyInMemory {
                Button {
                    model.warmASR()
                } label: {
                    Image(systemName: "bolt")
                }
                .buttonStyle(.plain)
                .disabled(model.isRecording || model.isWorking || model.isWarmingASR)
                .help("Warm up Parakeet")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Minivox")
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(palette.strip)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.border)
                .frame(height: 0.5)
        }
    }

    private var visibleMessage: String? {
        if let error = model.lastErrorMessage, !error.isEmpty {
            return error
        }

        let message = model.statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? nil : message
    }

    private var statusTitle: String {
        if model.isRecording { return "listen" }
        if model.isWarmingASR { return "warm" }
        if model.isWorking { return "transcribe" }
        if model.asrReadyInMemory { return "ready" }
        return "cold"
    }

    private var statusTint: Color {
        model.isRecording ? .red : .secondary
    }

    private var recordTitle: String {
        if model.isRecording { return "Finish" }
        if model.isWarmingASR { return "Warming" }
        if model.isWorking { return "Transcribing" }
        return "Dictate"
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

private struct ActivityIndicator: View {
    let title: String
    let tint: Color
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .tint(tint)
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
            }

            Text(title.uppercased())
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MinivoxPalette {
    let colorScheme: ColorScheme

    var background: Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.055, blue: 0.052)
            : Color(red: 0.955, green: 0.947, blue: 0.925)
    }

    var strip: Color {
        colorScheme == .dark
            ? Color(red: 0.035, green: 0.035, blue: 0.033)
            : Color(red: 0.91, green: 0.90, blue: 0.875)
    }

    var card: Color {
        colorScheme == .dark
            ? Color(red: 0.082, green: 0.082, blue: 0.078)
            : Color(red: 0.985, green: 0.98, blue: 0.965)
    }

    var controlFill: Color {
        colorScheme == .dark
            ? Color(red: 0.89, green: 0.88, blue: 0.84)
            : Color(red: 0.075, green: 0.075, blue: 0.07)
    }

    var controlForeground: Color {
        colorScheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.065)
            : Color(red: 0.94, green: 0.93, blue: 0.90)
    }

    var logoBackground: Color { controlFill }
    var logoForeground: Color { controlForeground }

    var controlSurface: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.045)
    }

    var controlTint: Color {
        colorScheme == .dark
            ? Color(red: 0.82, green: 0.81, blue: 0.78)
            : Color(red: 0.12, green: 0.12, blue: 0.11)
    }

    var border: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.045)
            : Color.black.opacity(0.075)
    }
}

private struct MiniWave: View {
    let color: Color

    private let heights: [CGFloat] = [4, 8, 12, 7, 10, 5]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 2, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}
