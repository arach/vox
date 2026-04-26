import AppKit
import SwiftUI
import VoxCore

struct ContentView: View {
    @StateObject private var model = ExampleModel()

    var body: some View {
        ZStack {
            background

            Group {
                if model.conversationTurns.isEmpty {
                    onboardingLayout
                } else {
                    chatLayout
                }
            }
            .animation(.spring(response: 0.48, dampingFraction: 0.9), value: model.conversationTurns.count)
        }
        .frame(minWidth: 900, minHeight: 780)
        .task {
            model.loadIfNeeded()
        }
    }

    private var onboardingLayout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                header
                onboardingHero
                onboardingConversation
                footer
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
        }
    }

    private var chatLayout: some View {
        VStack(spacing: 18) {
            header
            chatSurface
            composer
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.55),
                    Color(nsColor: .textBackgroundColor).opacity(0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.accentColor.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
            .blendMode(.softLight)

            RadialGradient(
                colors: [Color.black.opacity(0.06), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                VoxDemoMark()

                Text("A tiny on-device call-and-response demo for macOS 26+. Speak, transcribe, answer, and listen without the clutter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: model.conversationTurns.isEmpty ? 500 : 620, alignment: .leading)

                if !model.conversationTurns.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            StatusChip(title: model.asrStateTitle, icon: asrStatusIcon, tint: asrStatusTint)
                            FeatureChip(title: model.responseEngineName, icon: "sparkles")
                            FeatureChip(title: model.microphoneStatus, icon: "mic.circle")
                        }
                        .padding(.top, 2)
                    }
                }
            }

            Spacer(minLength: 0)

            StatusChip(
                title: statusTitle,
                icon: statusIcon,
                tint: statusTint
            )
        }
    }

    private var onboardingHero: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                FeatureChip(title: model.responseEngineName, icon: "sparkles")
                StatusChip(title: model.asrStateTitle, icon: asrStatusIcon, tint: asrStatusTint)
                FeatureChip(title: model.ttsModel?.backend ?? "kokoro", icon: "speaker.wave.2.fill")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer(minLength: 0)

                Button(action: { model.toggleRecording() }) {
                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(nsColor: .controlBackgroundColor).opacity(0.95),
                                            Color(nsColor: .underPageBackgroundColor).opacity(0.75),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 140, height: 140)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.12), radius: 24, y: 14)

                            Circle()
                                .strokeBorder(heroRingColor, lineWidth: model.isRecording ? 10 : 7)
                                .frame(width: 140, height: 140)
                                .opacity(model.isRecording || model.isWorking ? 1 : 0.65)

                            if model.isWorking {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.primary)
                                    .scaleEffect(1.3)
                            } else {
                                Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }

                        VStack(spacing: 4) {
                            Text(primaryLabel)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(primaryHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)

                Spacer(minLength: 0)
            }

            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Import Audio") {
                    model.chooseAudioFile()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.isRecording || model.isWorking)

                if !model.asrReadyInMemory {
                    Button(model.isWarmingASR ? "Warming Parakeet..." : "Warm Parakeet") {
                        model.warmASR()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(asrStatusTint)
                    .disabled(model.isRecording || model.isWorking || model.isWarmingASR)
                }

                if model.hasPendingImportedClip {
                    Button("Run Imported Clip") {
                        model.transcribe()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(model.isRecording || model.isWorking)
                }

                if !model.speechText.isEmpty {
                    Button("Listen Again") {
                        model.speak()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(model.isRecording || model.isWorking)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 28, y: 16)
    }

    private var onboardingConversation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                Text(onboardingConversationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                ConversationBubble(
                    role: "You",
                    symbol: "mic.fill",
                    tint: .blue,
                    text: model.transcript.isEmpty ? "Press record, say something, then stop to send a turn through Vox." : model.transcript,
                    trailingChip: model.hasPendingImportedClip ? model.selectedAudioURL?.lastPathComponent : nil,
                    footer: AnyView(
                        VStack(alignment: .leading, spacing: 8) {
                            if let metrics = model.transcriptionMetrics {
                                MetricStrip(metrics: [
                                    ("load", "\(metrics.modelLoadMs)ms"),
                                    ("infer", "\(metrics.inferenceMs)ms"),
                                    ("total", "\(metrics.totalMs)ms"),
                                ])
                            }

                            Text(model.transcriptionStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(model.asrStateDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
                )

                ConversationBubble(
                    role: "Vox",
                    symbol: "sparkles",
                    tint: .purple,
                    text: model.replyText.isEmpty ? "The on-device reply will appear here and play back through Kokoro." : model.replyText,
                    trailingButtonTitle: model.speechText.isEmpty ? nil : "Listen",
                    trailingButtonAction: model.speechText.isEmpty ? nil : {
                        model.speak()
                    },
                    trailingButtonDisabled: model.isWorking || model.isRecording,
                    footer: AnyView(
                        VStack(alignment: .leading, spacing: 8) {
                            let replyMetrics = replyMetricItems
                            if !replyMetrics.isEmpty {
                                MetricStrip(metrics: replyMetrics)
                            }

                            Text(model.responseEngineStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(model.speechStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
                )
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private var chatSurface: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                Text(chatConversationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 18) {
                        ForEach(model.conversationTurns) { turn in
                            ChatTurnView(
                                turn: turn,
                                isBusy: model.isWorking || model.isRecording,
                                onListen: {
                                    model.playReply(for: turn.id)
                                }
                            )
                            .id(turn.id)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("conversation-bottom")
                    }
                    .padding(20)
                }
                .onAppear {
                    scrollConversationToBottom(proxy)
                }
                .onChange(of: model.conversationTurns.count) { _, _ in
                    scrollConversationToBottom(proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 24, y: 14)
    }

    private var composer: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Button(action: { model.toggleRecording() }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .controlBackgroundColor).opacity(0.96),
                                        Color(nsColor: .underPageBackgroundColor).opacity(0.82),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 74, height: 74)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                            )

                        Circle()
                            .strokeBorder(heroRingColor, lineWidth: model.isRecording ? 8 : 5)
                            .frame(width: 74, height: 74)
                            .opacity(model.isRecording || model.isWorking ? 1 : 0.65)

                        if model.isWorking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.primary)
                        } else {
                            Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)

                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryLabel)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(primaryHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    if !model.asrReadyInMemory {
                        Button(model.isWarmingASR ? "Warming Parakeet..." : "Warm Parakeet") {
                            model.warmASR()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(asrStatusTint)
                        .disabled(model.isRecording || model.isWorking || model.isWarmingASR)
                    }

                    Button("Import Audio") {
                        model.chooseAudioFile()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .disabled(model.isRecording || model.isWorking)

                    if model.hasPendingImportedClip {
                        Button("Run Imported Clip") {
                            model.transcribe()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(model.isRecording || model.isWorking)
                    }
                }
                .font(.caption.weight(.semibold))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let modelInfo = model.ttsModel {
                        FeatureChip(title: modelInfo.name, icon: "speaker.wave.2.fill")
                    }

                    if let voice = selectedVoice {
                        FeatureChip(title: voiceLabel(voice), icon: "person.crop.circle")
                    }

                    if model.hasPendingImportedClip, let selectedAudioURL = model.selectedAudioURL {
                        FeatureChip(title: selectedAudioURL.lastPathComponent, icon: "waveform")
                    }

                    FeatureChip(title: model.asrStateDetail, icon: "mic.circle")
                    FeatureChip(title: model.responseEngineStatus, icon: "sparkles")

                    if let error = model.lastErrorMessage, !error.isEmpty {
                        WarningChip(title: error)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 18, y: 10)
    }

    private var footer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let modelInfo = model.ttsModel {
                    FeatureChip(title: modelInfo.name, icon: "speaker.wave.2.fill")
                    FeatureChip(title: modelInfo.backend, icon: "cube.transparent")
                } else {
                    FeatureChip(title: "Loading voices", icon: "arrow.triangle.2.circlepath")
                }

                if let voice = selectedVoice {
                    FeatureChip(title: voiceLabel(voice), icon: "person.crop.circle")
                }

                FeatureChip(title: model.microphoneStatus, icon: "mic.circle")
                FeatureChip(title: model.responseEngineName, icon: "sparkles")
                FeatureChip(title: model.asrStateDetail, icon: "waveform")

                if let error = model.lastErrorMessage, !error.isEmpty {
                    WarningChip(title: error)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var selectedVoice: TTSVoiceInfo? {
        guard let selectedVoiceID = model.selectedVoiceID else { return model.voices.first }
        return model.voices.first(where: { $0.id == selectedVoiceID }) ?? model.voices.first
    }

    private var onboardingConversationStatus: String {
        if model.isRecording {
            return "Recording"
        }

        if model.isWorking {
            return "Processing"
        }

        if model.replyText.isEmpty {
            return "Waiting for a turn"
        }

        return "Ready for another turn"
    }

    private var chatConversationStatus: String {
        if model.isRecording {
            return "Listening"
        }

        if model.isWorking {
            return "Processing"
        }

        let count = model.conversationTurns.count
        return count == 1 ? "1 turn" : "\(count) turns"
    }

    private var primaryLabel: String {
        if model.isRecording {
            return "Stop"
        }

        if model.isWorking {
            return "Working"
        }

        return "Record"
    }

    private var primaryHint: String {
        if model.isRecording {
            return "Tap again to send this turn."
        }

        if model.isWorking {
            return "Transcribing, replying, and speaking."
        }

        if model.conversationTurns.isEmpty {
            return "Start a short on-device conversation."
        }

        return "Add the next voice turn to the chat."
    }

    private var statusTitle: String {
        if model.isRecording {
            return "Listening"
        }
        if model.isWorking {
            return "Working"
        }
        if model.didLoad {
            return "App ready"
        }
        return "Loading"
    }

    private var statusIcon: String {
        if model.isRecording {
            return "waveform.circle.fill"
        }
        if model.isWorking {
            return "hourglass"
        }
        return "checkmark.circle.fill"
    }

    private var statusTint: Color {
        if model.isRecording {
            return .red
        }
        if model.isWorking {
            return .orange
        }
        return .green
    }

    private var heroRingColor: Color {
        if model.isRecording {
            return .red.opacity(0.45)
        }
        if model.isWorking || model.isWarmingASR {
            return .accentColor.opacity(0.42)
        }
        return .white.opacity(0.12)
    }

    private var asrStatusIcon: String {
        if model.isWarmingASR {
            return "arrow.triangle.2.circlepath"
        }
        if model.asrReadyInMemory {
            return "checkmark.circle.fill"
        }
        return "mic.fill"
    }

    private var asrStatusTint: Color {
        if model.isWarmingASR {
            return .orange
        }
        if model.asrReadyInMemory {
            return .green
        }
        return .secondary
    }

    private var replyMetricItems: [(String, String)] {
        var items: [(String, String)] = []

        if let replyMs = model.responseGenerationDurationMs, replyMs > 0 {
            items.append(("reply", "\(replyMs)ms"))
        }

        if let metrics = model.synthesisMetrics {
            items.append(("load", "\(metrics.modelLoadMs)ms"))
            items.append(("synth", "\(metrics.synthesisMs)ms"))
            items.append(("total", "\(metrics.totalMs)ms"))
        }

        return items
    }

    private func voiceLabel(_ voice: TTSVoiceInfo) -> String {
        if let language = voice.language, !language.isEmpty {
            return voice.isDefault ? "\(voice.name) (\(language)) · default" : "\(voice.name) (\(language))"
        }

        return voice.isDefault ? "\(voice.name) · default" : voice.name
    }

    private func scrollConversationToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        }
    }
}

private struct WarningChip: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.red.opacity(0.18), lineWidth: 1)
            )
    }
}

private struct VoxDemoMark: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VoxBrandIcon()

            VStack(alignment: .leading, spacing: 2) {
                Text("Vox")
                    .font(.custom("Avenir Next Demi Bold", size: 30))
                    .tracking(-0.6)
                    .foregroundStyle(.primary)

                Text("DEMO")
                    .font(.custom("Avenir Next Regular", size: 11))
                    .tracking(3.6)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Vox Demo")
    }
}

private struct VoxBrandIcon: View {
    var body: some View {
        Group {
            if let icon = VoxBrandAssets.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(0.9),
                                Color.orange.opacity(0.85),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Image(systemName: "waveform")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                    )
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
    }
}

private enum VoxBrandAssets {
    static let icon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "vox-app-icon", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }()
}

private struct FeatureChip: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct StatusChip: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.20), lineWidth: 1)
        )
    }
}

private struct ConversationBubble: View {
    let role: String
    let symbol: String
    let tint: Color
    let text: String
    let trailingChip: String?
    let trailingButtonTitle: String?
    let trailingButtonAction: (() -> Void)?
    let trailingButtonDisabled: Bool
    let footer: AnyView?

    init(
        role: String,
        symbol: String,
        tint: Color,
        text: String,
        trailingChip: String? = nil,
        trailingButtonTitle: String? = nil,
        trailingButtonAction: (() -> Void)? = nil,
        trailingButtonDisabled: Bool = false,
        footer: AnyView? = nil
    ) {
        self.role = role
        self.symbol = symbol
        self.tint = tint
        self.text = text
        self.trailingChip = trailingChip
        self.trailingButtonTitle = trailingButtonTitle
        self.trailingButtonAction = trailingButtonAction
        self.trailingButtonDisabled = trailingButtonDisabled
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(role, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)

                Spacer(minLength: 0)

                if let trailingChip {
                    FeatureChip(title: trailingChip, icon: "doc.text")
                }

                if let trailingButtonTitle, let trailingButtonAction {
                    Button(trailingButtonTitle, action: trailingButtonAction)
                        .buttonStyle(.borderless)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .disabled(trailingButtonDisabled)
                }
            }

            Text(text)
                .font(.system(.body, design: .default))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let footer {
                footer
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ChatTurnView: View {
    let turn: ConversationTurn
    let isBusy: Bool
    let onListen: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ChatBubble(
                side: .trailing,
                role: "You",
                symbol: "mic.fill",
                tint: .blue,
                text: turn.transcript,
                chipTitle: turn.sourceLabel,
                footer: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        if let metrics = turn.transcriptionMetrics {
                            MetricStrip(metrics: [
                                ("load", "\(metrics.modelLoadMs)ms"),
                                ("infer", "\(metrics.inferenceMs)ms"),
                                ("total", "\(metrics.totalMs)ms"),
                            ])
                        }
                    }
                )
            )

            ChatBubble(
                side: .leading,
                role: "Vox",
                symbol: "sparkles",
                tint: .purple,
                text: turn.reply,
                chipTitle: turn.engineName,
                actionTitle: "Listen",
                action: onListen,
                actionDisabled: isBusy,
                footer: AnyView(
                    VStack(alignment: .leading, spacing: 8) {
                        if !replyMetrics.isEmpty {
                            MetricStrip(metrics: replyMetrics)
                        }
                    }
                )
            )
        }
    }

    private var replyMetrics: [(String, String)] {
        var metrics: [(String, String)] = []

        if turn.responseDurationMs > 0 {
            metrics.append(("reply", "\(turn.responseDurationMs)ms"))
        }

        if let synthesis = turn.synthesisMetrics {
            metrics.append(("load", "\(synthesis.modelLoadMs)ms"))
            metrics.append(("synth", "\(synthesis.synthesisMs)ms"))
            metrics.append(("total", "\(synthesis.totalMs)ms"))
        }

        return metrics
    }
}

private struct ChatBubble: View {
    enum Side {
        case leading
        case trailing
    }

    let side: Side
    let role: String
    let symbol: String
    let tint: Color
    let text: String
    let chipTitle: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let actionDisabled: Bool
    let footer: AnyView?

    init(
        side: Side,
        role: String,
        symbol: String,
        tint: Color,
        text: String,
        chipTitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        actionDisabled: Bool = false,
        footer: AnyView? = nil
    ) {
        self.side = side
        self.role = role
        self.symbol = symbol
        self.tint = tint
        self.text = text
        self.chipTitle = chipTitle
        self.actionTitle = actionTitle
        self.action = action
        self.actionDisabled = actionDisabled
        self.footer = footer
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if side == .trailing {
                Spacer(minLength: 120)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label(role, systemImage: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)

                    Spacer(minLength: 0)

                    if let chipTitle {
                        FeatureChip(title: chipTitle, icon: side == .trailing ? "mic" : "sparkles")
                    }

                    if let actionTitle, let action {
                        Button(actionTitle, action: action)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .disabled(actionDisabled)
                    }
                }

                Text(text)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let footer {
                    footer
                }
            }
            .padding(18)
            .frame(maxWidth: 620, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(bubbleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(bubbleStroke, lineWidth: 1)
            )

            if side == .leading {
                Spacer(minLength: 120)
            }
        }
    }

    private var bubbleFill: Color {
        if side == .trailing {
            return tint.opacity(0.10)
        }

        return Color(nsColor: .controlBackgroundColor).opacity(0.82)
    }

    private var bubbleStroke: Color {
        if side == .trailing {
            return tint.opacity(0.18)
        }

        return Color.white.opacity(0.08)
    }
}

private struct MetricStrip: View {
    let metrics: [(String, String)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(metrics.indices, id: \.self) { index in
                let metric = metrics[index]
                HStack(spacing: 5) {
                    Text(metric.0)
                        .font(.caption2.weight(.semibold))
                    Text(metric.1)
                        .font(.caption2.weight(.medium))
                }
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.95))
                )
            }
        }
    }
}
