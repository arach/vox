import AppKit
import SwiftUI
import VoxCore
import VoxEngine

struct GettingStartedContext: Equatable {
    var sourceName: String?
    var productName: String?
    var headline: String
    var detail: String
    var actionLabel: String
    var logo: GettingStartedLogo?

    static func generic(sourceName: String?) -> Self {
        Self(
            sourceName: sourceName,
            productName: nil,
            headline: sourceName.map { "Use Vox with \($0)" } ?? "Use Vox",
            detail: "Local speech is ready from the Vox menu bar app.",
            actionLabel: sourceName.map { "Return to \($0)" } ?? "Close this window",
            logo: nil
        )
    }
}

struct GettingStartedLogo: Equatable {
    var url: URL?
    var symbolName: String?
}

struct GettingStartedView: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @EnvironmentObject var bridgeState: BridgeState
    @StateObject private var speechPreferences = SpeechPreferencesState()

    let context: GettingStartedContext
    let onOpenSettings: () -> Void
    let onRestartDaemon: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            MenuBarPreview(isRecording: monitor.isRecording)

            VStack(alignment: .leading, spacing: 10) {
                StatusRow(
                    title: "Companion",
                    value: monitor.isRunning ? "Running on port \(monitor.port ?? 0)" : "Not running",
                    systemImage: monitor.isRunning ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    tint: monitor.isRunning ? .green : .orange
                )

                StatusRow(
                    title: "Browser bridge",
                    value: bridgeState.isRunning ? "Listening on localhost:\(bridgeState.port)" : bridgeState.statusDetail ?? "Starting",
                    systemImage: bridgeState.isRunning ? "checkmark.circle.fill" : "hourglass.circle.fill",
                    tint: bridgeState.isRunning ? .green : .secondary
                )

                StatusRow(
                    title: "Speech",
                    value: "Parakeet transcription and system voices",
                    systemImage: "waveform.and.mic",
                    tint: .accentColor
                )
            }

            SpeechSetupPanel(speechPreferences: speechPreferences)

            VStack(alignment: .leading, spacing: 8) {
                Text(nextStepTitle)
                    .font(.headline)

                Text(nextStepDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    onRestartDaemon()
                } label: {
                    Label(monitor.isRunning ? "Restart Companion" : "Start Companion", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onOpenSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(28)
        .frame(width: 560, alignment: .leading)
        .task(id: monitor.isRunning) {
            await speechPreferences.load()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            RequesterLogoView(
                logo: context.logo,
                fallbackName: context.productName ?? context.sourceName
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(context.productName ?? context.headline)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                PoweredByVoxBadge()
            }
        }
    }

    private var nextStepTitle: String {
        if monitor.isRunning && bridgeState.isRunning {
            return context.actionLabel
        }
        return context.headline
    }

    private var nextStepDetail: String {
        if monitor.isRunning && bridgeState.isRunning {
            return context.sourceName.map { "Press Retry or Start Talking in \($0)." }
                ?? "You can close this window and leave Vox in the menu bar."
        }
        return context.detail
    }
}

private struct MenuBarPreview: View {
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("Menu bar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .leading)

            HStack(spacing: 8) {
                MenuBarIconImage(showsRecordingBadge: false)
                Divider()
                    .frame(height: 18)
                MenuBarIconImage(showsRecordingBadge: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.7), in: Capsule())

            Text(isRecording ? "Recording badge is visible" : "Badge appears while an app is recording")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }
}

private struct MenuBarIconImage: View {
    let showsRecordingBadge: Bool

    var body: some View {
        Image(nsImage: MenuBarIcon.makeStatusImage(size: 18, showsRecordingBadge: showsRecordingBadge))
            .resizable()
            .frame(width: 18, height: 18)
    }
}

private struct SpeechSetupPanel: View {
    @ObservedObject var speechPreferences: SpeechPreferencesState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Speech setup")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Mic input")
                        .font(.callout.weight(.semibold))
                        .frame(width: 116, alignment: .leading)

                    Text("System default")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Sound Settings") {
                        openSoundSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Picker(
                    "Transcription",
                    selection: Binding(
                        get: { speechPreferences.preferredTranscriptionModelId },
                        set: { speechPreferences.updatePreferredTranscriptionModelId($0) }
                    )
                ) {
                    Text("Vox Default (parakeet:v3)")
                        .tag("")
                    ForEach(speechPreferences.asrModels, id: \.id) { model in
                        Text(model.id)
                            .tag(model.id)
                    }
                }

                Picker(
                    "Synthesis",
                    selection: Binding(
                        get: { speechPreferences.preferredSynthesisModelId },
                        set: { newValue in
                            Task {
                                await speechPreferences.updatePreferredSynthesisModelId(newValue)
                            }
                        }
                    )
                ) {
                    Text("Vox Default (\(TTSDefaults.modelId))")
                        .tag("")
                    ForEach(speechPreferences.ttsModels, id: \.id) { model in
                        Text(model.id)
                            .tag(model.id)
                    }
                }

                Picker(
                    "Voice",
                    selection: Binding(
                        get: { speechPreferences.preferredSynthesisVoiceId },
                        set: { speechPreferences.updatePreferredSynthesisVoiceId($0) }
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

            Text("Apps can still override these defaults. Live capture follows the macOS input device for now.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func voiceLabel(_ voice: TTSVoiceInfo) -> String {
        if let language = voice.language, !language.isEmpty {
            return voice.isDefault ? "\(voice.name) (\(language)) · default" : "\(voice.name) (\(language))"
        }
        return voice.isDefault ? "\(voice.name) · default" : voice.name
    }

    private func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct RequesterLogoView: View {
    let logo: GettingStartedLogo?
    let fallbackName: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )

            logoContent
                .frame(width: 36, height: 36)
        }
        .frame(width: 50, height: 50)
    }

    @ViewBuilder
    private var logoContent: some View {
        if let image = localImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let url = logo?.url, url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                default:
                    fallbackLogo
                }
            }
        } else {
            fallbackLogo
        }
    }

    private var localImage: NSImage? {
        guard let url = logo?.url else { return nil }
        if url.isFileURL {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    private var fallbackLogo: some View {
        Group {
            if let symbolName = logo?.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 25, weight: .semibold))
            } else if let initial = fallbackName?.first {
                Text(String(initial).uppercased())
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 25, weight: .semibold))
            }
        }
        .foregroundStyle(.tint)
    }
}

private struct PoweredByVoxBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text("powered by Vox")
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .frame(width: 116, alignment: .leading)

            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
