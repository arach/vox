import SwiftUI
import HudsonUI
import VoxCore
import VoxEngine

// MARK: - General Tab

struct GeneralTab: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @State private var launchAgentInstalled = LaunchAgentManager.isInstalled()
    @StateObject private var speechPreferences = SpeechPreferencesState()

    var body: some View {
        VoxScreen(
            title: "Runtime",
            badge: "LOCAL FIRST",
            summary: "Manage the local daemon, inspect live capture state, and set user-level speech defaults without hiding model lifecycle."
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: HudSpacing.xl)],
                alignment: .leading,
                spacing: HudSpacing.xl
            ) {
                VoxMetricCard(
                    label: "Daemon",
                    value: monitor.isRunning ? "Running" : "Stopped",
                    detail: daemonDetail,
                    tint: monitor.isRunning ? HudPalette.statusOk : HudPalette.statusError,
                    pulses: monitor.isRunning
                )
                VoxMetricCard(
                    label: "Live Capture",
                    value: monitor.isRecording ? "Recording" : "Idle",
                    detail: monitor.liveSessionClientId ?? "No active session",
                    tint: monitor.isRecording ? HudPalette.statusError : HudPalette.dim,
                    pulses: monitor.isRecording
                )
                VoxMetricCard(
                    label: "Default ASR",
                    value: selectedTranscriptionModelLabel,
                    detail: "Explicit warm-up surface",
                    tint: HudPalette.statusInfo
                )
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack {
                        HudSectionLabel("Daemon")
                        Spacer()
                        HudBadge(
                            monitor.isRunning ? "RUNNING" : "STOPPED",
                            tint: monitor.isRunning ? HudPalette.statusOk : HudPalette.statusError,
                            dot: true
                        )
                    }

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow(
                                "Status",
                                value: monitor.isRunning ? "Running" : "Stopped",
                                valueColor: monitor.isRunning ? HudPalette.statusOk : HudPalette.statusError
                            )
                            if let port = monitor.port {
                                HudKVRow("Daemon Port", value: voxPortString(port))
                            }
                            if let pid = monitor.pid {
                                HudKVRow("PID", value: voxProcessIDString(pid))
                            }
                            if let startedAt = monitor.startedAt {
                                HStack {
                                    Text("UPTIME")
                                        .font(HudFont.mono(9))
                                        .tracking(0.8)
                                        .foregroundStyle(HudPalette.dim)
                                    Spacer()
                                    UptimeText(startedAt: startedAt)
                                        .font(HudFont.mono(11))
                                        .foregroundStyle(HudPalette.ink)
                                }
                            }
                            HudKVRow(
                                "Live Capture",
                                value: monitor.isRecording ? "Recording" : "Idle",
                                valueColor: monitor.isRecording ? HudPalette.statusError : HudPalette.muted
                            )
                            if monitor.isRecording, let clientId = monitor.liveSessionClientId {
                                HudKVRow("Recording Client", value: clientId)
                            }
                            if monitor.isRecording, let modelId = monitor.liveSessionModelId {
                                HudKVRow("Recording Model", value: modelId)
                            }
                        }
                    }

                    HStack(spacing: HudSpacing.md) {
                        HudButton("Restart", icon: "arrow.clockwise", style: .secondary) {
                            LaunchAgentManager.restart()
                        }

                        if !launchAgentInstalled {
                            HudButton("Install LaunchAgent", icon: "plus", style: .primary(.cyan)) {
                                LaunchAgentManager.install()
                                launchAgentInstalled = LaunchAgentManager.isInstalled()
                            }
                        }

                        Spacer()

                        HudBadge(
                            launchAgentInstalled ? "STARTS AT LOGIN" : "MANUAL START",
                            tint: launchAgentInstalled ? HudPalette.statusOk : HudPalette.muted
                        )
                    }
                }
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Speech Defaults")
                    VoxBodyText("These defaults are stored at the Vox user level. Apps can still override model and voice choices per request.")

                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        Picker(
                            "Transcription Default",
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
                                Text(model.id)
                                    .tag(model.id)
                            }
                        }

                        Picker(
                            "Synthesis Default",
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
                                Text(model.id)
                                    .tag(model.id)
                            }
                        }

                        Picker(
                            "Voice Default",
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

                    if let statusMessage = speechPreferences.statusMessage, !statusMessage.isEmpty {
                        HudInset {
                            VoxBodyText(statusMessage)
                        }
                    }

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow("ASR", value: selectedTranscriptionModelLabel)
                            HudKVRow("TTS", value: selectedSynthesisModelLabel)
                            HudKVRow("Voice", value: selectedVoiceLabel)
                            HudKVRow("Input Device", value: "System default", valueColor: HudPalette.muted)
                        }
                    }
                }
            }
        }
        .onAppear {
            launchAgentInstalled = LaunchAgentManager.isInstalled()
        }
        .task(id: monitor.isRunning) {
            await speechPreferences.load()
        }
    }

    private var daemonDetail: String {
        if let port = monitor.port, let pid = monitor.pid {
            return "port \(voxPortString(port)) · pid \(voxProcessIDString(pid))"
        }
        if let port = monitor.port {
            return "port \(voxPortString(port))"
        }
        return "Runtime file unavailable"
    }

    private var selectedTranscriptionModelLabel: String {
        speechPreferences.preferredTranscriptionModelId.isEmpty
            ? "parakeet:v3"
            : speechPreferences.preferredTranscriptionModelId
    }

    private var selectedSynthesisModelLabel: String {
        speechPreferences.preferredSynthesisModelId.isEmpty
            ? speechPreferences.defaultSynthesisModelId
            : speechPreferences.preferredSynthesisModelId
    }

    private var selectedVoiceLabel: String {
        speechPreferences.preferredSynthesisVoiceId.isEmpty
            ? "Provider default"
            : speechPreferences.preferredSynthesisVoiceId
    }

    private func voiceLabel(_ voice: TTSVoiceInfo) -> String {
        if let language = voice.language, !language.isEmpty {
            return voice.isDefault ? "\(voice.name) (\(language)) · default" : "\(voice.name) (\(language))"
        }
        return voice.isDefault ? "\(voice.name) · default" : voice.name
    }
}

// MARK: - Bridge Tab

struct BridgeTab: View {
    @EnvironmentObject var bridgeState: BridgeState

    var body: some View {
        VoxScreen(
            title: "Bridge",
            badge: "COMPANION",
            summary: "Control the localhost HTTP bridge and its origin allowlist. Built-in, user-managed, and integration origins stay visible."
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: HudSpacing.xl)],
                alignment: .leading,
                spacing: HudSpacing.xl
            ) {
                VoxMetricCard(
                    label: "HTTP Bridge",
                    value: bridgeState.isRunning ? "Listening" : "Stopped",
                    detail: "127.0.0.1:\(voxPortString(bridgeState.port))",
                    tint: bridgeState.isRunning ? HudPalette.statusInfo : HudPalette.statusError,
                    pulses: bridgeState.isRunning
                )
                VoxMetricCard(
                    label: "User Origins",
                    value: "\(bridgeState.userOrigins.count)",
                    detail: "~/.vox/origins.json",
                    tint: HudPalette.statusOk
                )
                VoxMetricCard(
                    label: "Integrations",
                    value: "\(bridgeState.integrationOrigins.count)",
                    detail: "~/.vox/origins.d/",
                    tint: HudPalette.statusWarn
                )
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack {
                        HudSectionLabel("HTTP Bridge")
                        Spacer()
                        HudBadge(
                            bridgeState.isRunning ? "LISTENING" : "STOPPED",
                            tint: bridgeState.isRunning ? HudPalette.statusInfo : HudPalette.statusError,
                            dot: true
                        )
                    }

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow(
                                "Status",
                                value: bridgeState.isRunning ? "Listening" : "Stopped",
                                valueColor: bridgeState.isRunning ? HudPalette.statusInfo : HudPalette.statusError
                            )
                            HudKVRow("Port", value: voxPortString(bridgeState.port))
                            HudKVRow("Address", value: "http://127.0.0.1:\(voxPortString(bridgeState.port))", valueLineLimit: 1)
                        }
                    }

                    if let statusDetail = bridgeState.statusDetail, !statusDetail.isEmpty {
                        VoxBodyText(
                            statusDetail,
                            tint: bridgeState.isRunning ? HudPalette.muted : HudPalette.statusError
                        )
                    }
                }
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Allowed Origins")
                    VoxBodyText("Origins must be full browser origins. Wildcard ports are only supported for localhost, 127.0.0.1, and ::1.")

                    HStack(spacing: HudSpacing.md) {
                        HudField(
                            "https://app.example.com or http://localhost:*",
                            text: Binding(
                                get: { bridgeState.draftOrigin },
                                set: { newValue in
                                    bridgeState.draftOrigin = newValue
                                    bridgeState.clearOriginError()
                                }
                            ),
                            icon: "link"
                        )

                        HudButton("Add", icon: "plus", style: .primary(.cyan)) {
                            bridgeState.addDraftOrigin()
                        }
                        .disabled(!bridgeState.canAddOrigin)
                    }

                    if let message = bridgeState.originsErrorMessage, !message.isEmpty {
                        HudInset {
                            VoxBodyText(message, tint: HudPalette.statusError)
                        }
                    }
                }
            }

            OriginListCard(
                title: "Added In Vox",
                origins: bridgeState.userOrigins,
                emptyTitle: "No user origins",
                emptySubtitle: "Add an origin above to allow a browser app to use the local bridge.",
                icon: "person.crop.circle.badge.plus",
                removable: true
            ) { origin in
                bridgeState.removeOrigin(origin)
            }

            OriginListCard(
                title: "Integration Registrations",
                origins: bridgeState.integrationOrigins,
                emptyTitle: "No integration registrations",
                emptySubtitle: "Apps can drop JSON origin files into ~/.vox/origins.d/.",
                icon: "square.stack.3d.up"
            )

            OriginListCard(
                title: "Built-In Origins",
                origins: bridgeState.builtinOrigins,
                emptyTitle: "No built-in origins",
                emptySubtitle: "Bridge startup will populate the built-in allowlist.",
                icon: "checkmark.seal"
            )

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Configuration")
                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow("User File", value: "~/.vox/origins.json")
                            HudKVRow("Integration Drop-Ins", value: "~/.vox/origins.d/")
                        }
                    }
                    VoxBodyText("Integrations register origins by writing JSON such as {\"origins\":[\"https://app.example.com\"]}. Vox merges those entries with built-in and user-managed origins.")
                }
            }
        }
        .task {
            await bridgeState.refreshOrigins()
        }
    }
}

private struct OriginListCard: View {
    let title: String
    let origins: [String]
    let emptyTitle: String
    let emptySubtitle: String
    let icon: String
    var removable = false
    var onRemove: (String) -> Void = { _ in }

    var body: some View {
        HudCard(padding: HudSpacing.md) {
            VStack(alignment: .leading, spacing: HudSpacing.md) {
                HStack {
                    HudSectionLabel(title)
                        .padding(.horizontal, HudSpacing.md)
                    Spacer()
                    HudBadge("\(origins.count)", tint: origins.isEmpty ? HudPalette.muted : HudPalette.statusInfo)
                        .padding(.horizontal, HudSpacing.md)
                }

                if origins.isEmpty {
                    VoxEmptyList(title: emptyTitle, subtitle: emptySubtitle, icon: icon)
                } else {
                    if removable {
                        ForEach(origins, id: \.self) { origin in
                            HudListRow(
                                title: origin,
                                subtitle: "User managed",
                                icon: icon,
                                iconTint: .cyan
                            ) {
                                HudButton("Remove", icon: "minus", style: .ghost) {
                                    onRemove(origin)
                                }
                            }
                        }
                    } else {
                        HudInset {
                            VStack(alignment: .leading, spacing: HudSpacing.md) {
                                ForEach(origins, id: \.self) { origin in
                                    HudKVRow("Origin", value: origin, valueColor: HudPalette.muted)
                                    if origin != origins.last {
                                        HudDivider()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct UptimeText: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(formatUptime(context.date.timeIntervalSince(startedAt)))
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VoxScreen(
            title: "About",
            badge: "COMPANION",
            summary: "Vox is a local-first voice runtime for Apple apps, web companions, and developer tools."
        ) {
            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack {
                        HudSectionLabel("Vox Companion")
                        Spacer()
                        HudBadge("LOCAL", tint: HudPalette.statusOk, dot: true)
                    }

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow("Version", value: VoxVersion.current)
                            HudKVRow("Runtime", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
                            HudKVRow("Data", value: "~/.vox/")
                        }
                    }
                }
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Runtime Contract")
                    VoxBodyText("Vox keeps speech local by default, exposes warm-up as a public capability, and records latency with client, route, and model dimensions.")
                    HStack(spacing: HudSpacing.md) {
                        HudBadge("LOCAL MODELS", tint: HudPalette.statusOk, dot: true)
                        HudBadge("WARM-UP", tint: HudPalette.statusInfo, dot: true)
                        HudBadge("TELEMETRY", tint: HudPalette.statusWarn, dot: true)
                    }
                }
            }
        }
    }
}
