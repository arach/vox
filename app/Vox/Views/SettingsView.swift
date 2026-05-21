import SwiftUI
import HudsonUI
import VoxCore
import VoxEngine

// MARK: - Overview Tab

struct OverviewTab: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @State private var launchAgentInstalled = LaunchAgentManager.isInstalled()
    @ObservedObject var speechPreferences: SpeechPreferencesState

    var body: some View {
        VoxScreen(
            title: "Overview",
            badge: "COMPANION",
            summary: "Vox is a local-first voice runtime for Apple apps, web companions, and developer tools."
        ) {
            statusStrip
            detailCard
            controlStrip
        }
        .onAppear {
            launchAgentInstalled = LaunchAgentManager.isInstalled()
        }
        .task(id: monitor.isRunning) {
            await speechPreferences.load()
        }
    }

    // MARK: Status strip — three operational chips at a glance.

    private var statusStrip: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: HudSpacing.xl),
                GridItem(.flexible(), spacing: HudSpacing.xl),
                GridItem(.flexible(), spacing: HudSpacing.xl)
            ],
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
                label: "Speech",
                value: speechPreferences.effectiveTranscriptionModelId,
                detail: "tts · \(speechPreferences.effectiveSynthesisModelId)",
                tint: speechPreferences.effectiveSynthesisNeedsAPIKey ? HudPalette.statusWarn : HudPalette.muted
            )

            uptimeCard
        }
    }

    @ViewBuilder
    private var uptimeCard: some View {
        if let startedAt = monitor.startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VoxMetricCard(
                    label: "Uptime",
                    value: Self.formatUptime(context.date.timeIntervalSince(startedAt)),
                    detail: launchAgentInstalled ? "starts at login" : "manual start",
                    tint: HudPalette.muted
                )
            }
        } else {
            VoxMetricCard(
                label: "Uptime",
                value: "—",
                detail: monitor.isRunning ? "starting" : "runtime offline",
                tint: HudPalette.statusError
            )
        }
    }

    // MARK: Detail card — two columns share one surface to cut dark-card stacking.

    private var detailCard: some View {
        HudCard {
            HStack(alignment: .top, spacing: HudSpacing.xxxl) {
                companionColumn
                Rectangle()
                    .fill(HudHairline.subtle)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                speechColumn
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var companionColumn: some View {
        VStack(alignment: .leading, spacing: HudSpacing.md) {
            HudSectionLabel("Companion")
                .padding(.bottom, HudSpacing.xs)
            HudKVRow("Version", value: VoxVersion.current)
            HudKVRow(
                "Runtime",
                value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                valueColor: HudPalette.muted,
                valueLineLimit: 1
            )
            HudKVRow("Data", value: "~/.vox/", valueColor: HudPalette.muted)
            if let pid = monitor.pid {
                HudKVRow("PID", value: voxProcessIDString(pid), valueColor: HudPalette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var speechColumn: some View {
        VStack(alignment: .leading, spacing: HudSpacing.md) {
            HudSectionLabel("Speech Stack")
                .padding(.bottom, HudSpacing.xs)
            HudKVRow("ASR", value: speechPreferences.effectiveTranscriptionModelId)
            HudKVRow("TTS", value: speechPreferences.effectiveSynthesisModelId)
            HudKVRow(
                "Voice",
                value: speechPreferences.effectiveSynthesisVoiceLabel,
                valueColor: HudPalette.muted,
                valueLineLimit: 1
            )
            HudKVRow(
                "Input",
                value: speechPreferences.effectiveInputDeviceLabel,
                valueColor: HudPalette.muted,
                valueLineLimit: 1
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Control strip — slim action row, no nested card.

    private var controlStrip: some View {
        HStack(spacing: HudSpacing.md) {
            HudButton("Restart Daemon", icon: "arrow.clockwise", style: .secondary) {
                LaunchAgentManager.restart()
            }

            if !launchAgentInstalled {
                HudButton("Install LaunchAgent", icon: "plus", style: .primary(.cyan)) {
                    LaunchAgentManager.install()
                    launchAgentInstalled = LaunchAgentManager.isInstalled()
                }
            }

            Spacer(minLength: 0)

            if monitor.port == nil, monitor.pid == nil, monitor.startedAt == nil {
                VoxStatusText("RUNTIME FILE UNAVAILABLE", tint: HudPalette.statusError)
            } else {
                VoxStatusText(
                    launchAgentInstalled ? "STARTS AT LOGIN" : "MANUAL START",
                    tint: HudPalette.muted
                )
            }
        }
    }

    private var daemonDetail: String {
        guard let port = monitor.port else { return "runtime unavailable" }
        return "websocket \(voxPortString(port))"
    }

    private static func formatUptime(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }
}

struct GeneralTab: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @State private var launchAgentInstalled = LaunchAgentManager.isInstalled()
    @State private var liveSessionMessage: String?
    @State private var liveSessionMessageIsError = false
    @ObservedObject var speechPreferences: SpeechPreferencesState

    var body: some View {
        VoxScreen(
            title: "Runtime",
            badge: "LOCAL FIRST",
            summary: "Manage the local daemon, inspect live capture state, and set user-level speech defaults without hiding model lifecycle."
        ) {
            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Daemon")

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
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
                            if monitor.port == nil, monitor.pid == nil, monitor.startedAt == nil {
                                VoxBodyText("Runtime file unavailable.", tint: HudPalette.statusError)
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

                        VoxStatusText(
                            launchAgentInstalled ? "STARTS AT LOGIN" : "MANUAL START",
                            tint: HudPalette.muted
                        )
                    }
                }
            }

            liveCaptureCard

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Provider Credentials")

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HStack {
                                HudKVRow(
                                    "OpenAI Key",
                                    value: speechPreferences.openAIKeyConfigured
                                        ? "stored encrypted (\(speechPreferences.openAIKeyPreview))"
                                        : "not stored",
                                    valueColor: speechPreferences.openAIKeyConfigured ? HudPalette.muted : HudPalette.statusWarn
                                )
                            }

                            HudSecretField(
                                "sk-...",
                                text: $speechPreferences.openAIAPIKeyInput,
                                icon: "key.fill"
                            )

                            HStack(spacing: HudSpacing.md) {
                                HudButton("Save Key", icon: "lock", style: .secondary) {
                                    speechPreferences.saveOpenAIAPIKey()
                                }
                                .disabled(speechPreferences.openAIAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

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
            }

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Speech Defaults")
                    VoxBodyText("Defaults are stored at the Vox user level. Apps can still override model, voice, and input choices per request.")

                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        VoxPickerRow(
                            label: "Transcription",
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

                        VoxPickerRow(
                            label: "Synthesis",
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

                        VoxPickerRow(
                            label: "Voice",
                            selection: Binding(
                                get: { speechPreferences.preferredSynthesisVoiceId },
                                set: { newValue in
                                    speechPreferences.updatePreferredSynthesisVoiceId(newValue)
                                }
                            ),
                            isDisabled: speechPreferences.voices.isEmpty
                        ) {
                            Text("Provider Default")
                                .tag("")
                            ForEach(speechPreferences.voices, id: \.id) { voice in
                                Text(voiceLabel(voice))
                                    .tag(voice.id)
                            }
                        }

                        VoxPickerRow(
                            label: "Input Device",
                            selection: Binding(
                                get: { speechPreferences.preferredInputDeviceId },
                                set: { newValue in
                                    speechPreferences.updatePreferredInputDeviceId(newValue)
                                }
                            ),
                            isDisabled: speechPreferences.inputDevices.isEmpty
                        ) {
                            Text("System Default")
                                .tag("")
                            ForEach(speechPreferences.inputDevices) { device in
                                Text(device.isSystemDefault ? "\(device.name) · system default" : device.name)
                                    .tag(device.id)
                            }
                        }

                        micPermissionRow
                    }

                    if let statusMessage = speechPreferences.statusMessage, !statusMessage.isEmpty {
                        HudInset {
                            VoxBodyText(statusMessage)
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

    @ViewBuilder
    private var liveCaptureCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack {
                    HudSectionLabel("Live Capture")
                    Spacer()
                    VoxStatusText(
                        monitor.liveSession?.state.rawValue.uppercased() ?? "IDLE",
                        tint: monitor.hasLiveSession ? HudPalette.statusWarn : HudPalette.muted
                    )
                }

                HudInset {
                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        if let session = monitor.liveSession {
                            HudKVRow("Session", value: session.sessionId, valueLineLimit: 1)
                            HudKVRow("Client", value: session.clientId, valueColor: HudPalette.ink)
                            HudKVRow("Model", value: session.modelId, valueColor: HudPalette.muted)
                            HudKVRow("State", value: session.state.rawValue, valueColor: session.state == .recording ? HudPalette.statusError : HudPalette.statusWarn)
                            if let startedAt = session.startedAt {
                                HStack {
                                    Text("ACTIVE FOR")
                                        .font(HudFont.mono(9))
                                        .tracking(0.8)
                                        .foregroundStyle(HudPalette.dim)
                                    Spacer()
                                    LiveSessionAgeText(startedAt: startedAt)
                                        .font(HudFont.mono(11))
                                        .foregroundStyle(HudPalette.ink)
                                }
                            }
                        } else {
                            VoxBodyText("No active live transcription session.", tint: HudPalette.muted)
                        }
                    }
                }

                HStack(spacing: HudSpacing.md) {
                    HudButton("Refresh", icon: "arrow.clockwise", style: .secondary) {
                        Task {
                            monitor.checkNow()
                            await monitor.refreshSessionsNow()
                        }
                    }

                    if monitor.hasLiveSession {
                        HudButton("Cancel Session", icon: "xmark.circle", style: .secondary) {
                            Task {
                                if let error = await monitor.cancelLiveSession() {
                                    liveSessionMessage = error
                                    liveSessionMessageIsError = true
                                } else {
                                    liveSessionMessage = "Cancelled the active live session."
                                    liveSessionMessageIsError = false
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                if let liveSessionMessage, !liveSessionMessage.isEmpty {
                    HudInset {
                        VoxBodyText(
                            liveSessionMessage,
                            tint: liveSessionMessageIsError ? HudPalette.statusError : HudPalette.muted
                        )
                    }
                }
            }
        }
    }

    private var micPermissionRow: some View {
        VoxMicrophonePermissionRow(
            status: speechPreferences.microphonePermissionStatus,
            requestAccess: {
                Task { await speechPreferences.requestMicrophonePermission() }
            },
            openSettings: {
                speechPreferences.openMicrophonePrivacySettings()
            }
        )
    }

    private func voiceLabel(_ voice: TTSVoiceInfo) -> String {
        if let language = voice.language, !language.isEmpty {
            return voice.isDefault ? "\(voice.name) (\(language)) · default" : "\(voice.name) (\(language))"
        }
        return voice.isDefault ? "\(voice.name) · default" : voice.name
    }
}

// MARK: - Doctor Tab

struct RuntimeDoctorTab: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @EnvironmentObject var bridgeState: BridgeState
    @ObservedObject var speechPreferences: SpeechPreferencesState
    @StateObject private var doctor = RuntimeDoctorState()
    @State private var sessionMessage: String?
    @State private var sessionMessageIsError = false

    var body: some View {
        VoxScreen(
            title: "Doctor",
            badge: "CURRENT STATE",
            summary: "Inspect daemon health, active speech sessions, and the localhost HTTP API in one place."
        ) {
            runtimeGrid
            doctorCard
            sessionStateCard
            httpEndpointCard
            bridgeOriginsCard
        }
        .task {
            await bridgeState.refreshOrigins()
            await doctor.refresh()
            monitor.checkNow()
            await monitor.refreshSessionsNow()
        }
    }

    private var runtimeGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: HudSpacing.xl)],
            alignment: .leading,
            spacing: HudSpacing.xl
        ) {
            VoxMetricCard(
                label: "Daemon",
                value: monitor.isRunning ? "Running" : "Stopped",
                detail: monitor.port.map { "WebSocket \(voxPortString($0))" } ?? "runtime unavailable",
                tint: monitor.isRunning ? HudPalette.statusOk : HudPalette.statusError,
                pulses: monitor.isRunning
            )
            VoxMetricCard(
                label: "HTTP API",
                value: bridgeState.isRunning ? "Listening" : "Stopped",
                detail: "127.0.0.1:\(voxPortString(bridgeState.port))",
                tint: bridgeState.isRunning ? HudPalette.statusInfo : HudPalette.statusWarn,
                pulses: bridgeState.isRunning
            )
            VoxMetricCard(
                label: "Speech",
                value: speechPreferences.effectiveSynthesisAvailabilityLabel.capitalized,
                detail: "\(speechPreferences.effectiveSynthesisModelId) · \(speechPreferences.effectiveTranscriptionModelId)",
                tint: speechPreferences.effectiveSynthesisNeedsAPIKey ? HudPalette.statusWarn : HudPalette.muted
            )
        }
    }

    private var doctorCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack {
                    HudSectionLabel("Doctor")
                    Spacer()
                    VoxStatusText(
                        doctor.report?.ready == true ? "READY" : "CHECK",
                        tint: doctor.report?.ready == true ? HudPalette.statusOk : HudPalette.statusWarn
                    )
                }

                if let report = doctor.report {
                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            ForEach(report.checks, id: \.name) { check in
                                VStack(alignment: .leading, spacing: HudSpacing.xs) {
                                    VoxIconKVRow(
                                        label: check.name,
                                        value: check.detail,
                                        icon: doctorIcon(for: check.status),
                                        tint: doctorTint(for: check.status)
                                    )
                                    if let remediation = check.remediation {
                                        doctorRemediationRow(remediation)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    HudInset {
                        VoxBodyText(doctor.statusMessage, tint: HudPalette.muted)
                    }
                }

                HStack(spacing: HudSpacing.md) {
                    HudButton("Run Doctor", icon: "stethoscope", style: .primary(.cyan)) {
                        Task { await doctor.refresh() }
                    }
                    .disabled(doctor.isRefreshing)

                    HudButton("Refresh State", icon: "arrow.clockwise", style: .secondary) {
                        Task {
                            monitor.checkNow()
                            await monitor.refreshSessionsNow()
                            await bridgeState.refreshOrigins()
                            await speechPreferences.refreshOptions()
                        }
                    }
                    .disabled(doctor.isRefreshing)

                    Spacer(minLength: 0)
                }

                if !doctor.statusMessage.isEmpty {
                    HudInset {
                        VoxBodyText(doctor.statusMessage, tint: HudPalette.muted)
                    }
                }
            }
        }
    }

    private var sessionStateCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack {
                    HudSectionLabel("Active Sessions")
                    Spacer()
                    VoxStatusText(activeSessionBadge, tint: activeSessionTint)
                }

                HudInset {
                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        if let session = monitor.liveSession {
                            HudKVRow("Live Session", value: session.sessionId, valueLineLimit: 1)
                            HudKVRow("Client", value: session.clientId, valueColor: HudPalette.ink)
                            HudKVRow("ASR Model", value: session.modelId, valueColor: HudPalette.muted)
                            HudKVRow("State", value: session.state.rawValue, valueColor: session.state == .recording ? HudPalette.statusError : HudPalette.statusWarn)
                        } else {
                            HudKVRow("Live Session", value: "idle", valueColor: HudPalette.muted)
                        }

                        if let session = monitor.synthesisSession {
                            HudDivider()
                            HudKVRow("Synthesis", value: session.sessionId, valueLineLimit: 1)
                            HudKVRow("Client", value: session.clientId, valueColor: HudPalette.ink)
                            HudKVRow("TTS Model", value: session.modelId, valueColor: HudPalette.muted)
                            HudKVRow("Voice", value: session.voiceId ?? "provider default", valueColor: HudPalette.muted)
                            HudKVRow("State", value: session.state.rawValue, valueColor: HudPalette.statusWarn)
                        } else {
                            HudKVRow("Synthesis", value: "idle", valueColor: HudPalette.muted)
                        }
                    }
                }

                HStack(spacing: HudSpacing.md) {
                    HudButton("Refresh Sessions", icon: "arrow.clockwise", style: .secondary) {
                        Task { await monitor.refreshSessionsNow() }
                    }

                    if monitor.hasLiveSession {
                        HudButton("Cancel Capture", icon: "xmark.circle", style: .secondary) {
                            Task { await cancelSession { await monitor.cancelLiveSession() } }
                        }
                    }

                    if monitor.isSpeaking {
                        HudButton("Cancel Speech", icon: "stop.fill", style: .secondary) {
                            Task { await cancelSession { await monitor.cancelSynthesis() } }
                        }
                    }

                    Spacer(minLength: 0)
                }

                if let sessionMessage, !sessionMessage.isEmpty {
                    HudInset {
                        VoxBodyText(sessionMessage, tint: sessionMessageIsError ? HudPalette.statusError : HudPalette.muted)
                    }
                }
            }
        }
    }

    private var httpEndpointCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack {
                    HudSectionLabel("HTTP API")
                    Spacer()
                    VoxStatusText(
                        bridgeState.isRunning ? "LISTENING" : "STOPPED",
                        tint: bridgeState.isRunning ? HudPalette.statusInfo : HudPalette.statusWarn
                    )
                }

                HudInset {
                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        HudKVRow("Address", value: "http://127.0.0.1:\(voxPortString(bridgeState.port))", valueLineLimit: 1)
                        HudKVRow("User Origins", value: "\(bridgeState.userOrigins.count)")
                        HudKVRow("Integration Origins", value: "\(bridgeState.integrationOrigins.count)")
                        HudKVRow("Built-In Origins", value: "\(bridgeState.builtinOrigins.count)")
                    }
                }

                if !bridgeState.isRunning, let statusDetail = bridgeState.statusDetail, !statusDetail.isEmpty {
                    VoxBodyText(statusDetail, tint: HudPalette.statusError)
                }
            }
        }
    }

    private var bridgeOriginsCard: some View {
        VStack(alignment: .leading, spacing: HudSpacing.lg) {
            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Allowed Origins")

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
        }
    }

    private var activeSessionBadge: String {
        if monitor.isRecording { return "RECORDING" }
        if monitor.isSpeaking { return "SPEAKING" }
        if monitor.hasLiveSession { return "ACTIVE" }
        return "IDLE"
    }

    private var activeSessionTint: Color {
        if monitor.isRecording { return HudPalette.statusError }
        if monitor.isSpeaking || monitor.hasLiveSession { return HudPalette.statusWarn }
        return HudPalette.muted
    }

    private func cancelSession(_ action: () async -> String?) async {
        if let error = await action() {
            sessionMessage = error
            sessionMessageIsError = true
        } else {
            sessionMessage = "Session cancelled."
            sessionMessageIsError = false
        }
    }

    private func doctorIcon(for status: String) -> String {
        switch status {
        case "ok": return "checkmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        default: return "xmark.circle.fill"
        }
    }

    private func doctorTint(for status: String) -> Color {
        switch status {
        case "ok": return HudPalette.statusOk
        case "warning": return HudPalette.statusWarn
        default: return HudPalette.statusError
        }
    }

    private func doctorRemediationRow(_ remediation: DoctorRemediation) -> some View {
        HStack(spacing: HudSpacing.md) {
            VoxBodyText(remediation.detail, tint: HudPalette.muted)
            Spacer(minLength: 0)
            doctorRemediationButton(remediation)
        }
    }

    @ViewBuilder
    private func doctorRemediationButton(_ remediation: DoctorRemediation) -> some View {
        switch remediation.action {
        case "request_microphone_access":
            HudButton(remediation.label, icon: "mic.fill", style: .secondary) {
                Task {
                    await doctor.requestMicrophoneAccess()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        case "open_microphone_privacy_settings":
            HudButton(remediation.label, icon: "gearshape", style: .secondary) {
                speechPreferences.openMicrophonePrivacySettings()
            }
            .fixedSize(horizontal: true, vertical: false)
        default:
            EmptyView()
        }
    }
}

// MARK: - Bridge Tab

struct BridgeTab: View {
    @EnvironmentObject var bridgeState: BridgeState

    var body: some View {
        VoxScreen(
            title: "HTTP API",
            badge: "COMPANION",
            summary: "The HTTP bridge is Vox's localhost API for browser and web app calls. The daemon is the WebSocket runtime on its own port."
        ) {
            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HudSectionLabel("Endpoint")

                    HudInset {
                        VStack(alignment: .leading, spacing: HudSpacing.md) {
                            HudKVRow("HTTP Port", value: voxPortString(bridgeState.port))
                            HudKVRow("Address", value: "http://127.0.0.1:\(voxPortString(bridgeState.port))", valueLineLimit: 1)
                        }
                    }

                    if !bridgeState.isRunning, let statusDetail = bridgeState.statusDetail, !statusDetail.isEmpty {
                        VoxBodyText(
                            statusDetail,
                            tint: HudPalette.statusError
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
                    VoxStatusText("\(origins.count)", tint: HudPalette.muted)
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

private struct LiveSessionAgeText: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(formatAge(context.date.timeIntervalSince(startedAt)))
        }
    }

    private func formatAge(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VoxScreen(
            title: "About",
            badge: "COMPANION",
            summary: "Vox is a voice runtime for Apple apps, web companions, and developer tools."
        ) {
            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack {
                        HudSectionLabel("Vox Companion")
                        Spacer()
                        VoxStatusText("LOCAL", tint: HudPalette.muted)
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
                    VoxBodyText("Vox exposes warm-up as a public capability, keeps provider choice explicit, and records latency with client, route, and model dimensions.")
                }
            }
        }
    }
}
