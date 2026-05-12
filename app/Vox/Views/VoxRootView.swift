import SwiftUI
import HudsonUI
import HudsonShell
import VoxCore

// MARK: - Navigation Sections

enum VoxSection: String, CaseIterable, Identifiable {
    case welcome
    case general
    case speechCheck
    case bridge
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .general: return "General"
        case .speechCheck: return "Speech Check"
        case .bridge: return "HTTP API"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "sparkles"
        case .general: return "gearshape"
        case .speechCheck: return "waveform.and.mic"
        case .bridge: return "network"
        case .about: return "info.circle"
        }
    }

    var navItem: HudRailItem {
        HudRailItem(id: rawValue, label: title, icon: icon)
    }
}

// MARK: - Root View

struct VoxRootView: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @EnvironmentObject var bridgeState: BridgeState
    @EnvironmentObject var onboarding: OnboardingState

    @StateObject private var speechPreferences = SpeechPreferencesState()
    @State private var section: VoxSection
    @State private var railExpanded = true
    @State private var inspectorCollapsed = false
    @State private var stopFeedback: String?
    @State private var stopFeedbackIsError = false
    @State private var stopInFlight = false
    @State private var stopFeedbackTask: Task<Void, Never>?

    private let manifest = HudAppManifest(
        name: "vox",
        version: VoxVersion.current,
        tint: .cyan,
        targetLabel: "Runtime"
    )

    init(initialSection: VoxSection = .about) {
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        HudAppShell {
            HudNavigationRail(
                selection: Binding(
                    get: { section.rawValue },
                    set: { next in
                        if let value = VoxSection(rawValue: next) {
                            section = value
                        }
                    }
                ),
                items: navigationSections.map(\.navItem),
                isExpanded: $railExpanded,
                showsHeaderStatusDot: false
            )
        } trailing: {
            HudInspector(isCollapsed: $inspectorCollapsed) {
                HStack {
                    HudSectionLabel("Status")
                    Spacer()
                    VoxStatusText(runtimeSummary.badge, tint: runtimeSummary.tint)
                }
            } content: {
                inspectorContent
            }
        } content: {
            sectionContent
        } statusBar: {
            statusBar
        }
        .hudsonAppManifest(manifest)
        .hudTheme(.default)
        .preferredColorScheme(.dark)
        .background(HudWindowChrome(colorScheme: .dark))
        .task(id: monitor.isRunning) {
            await speechPreferences.load()
        }
        .onChange(of: onboarding.requestToken) { _, _ in
            section = .welcome
        }
    }

    private var navigationSections: [VoxSection] {
        var sections: [VoxSection] = [.about, .general, .speechCheck, .bridge]
        if shouldShowWelcome {
            sections.insert(.welcome, at: 0)
        }
        return sections
    }

    private var shouldShowWelcome: Bool {
        if section == .welcome { return true }
        if case .unknown = onboarding.trust { return false }
        return true
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .welcome:
            WelcomeTab(speechPreferences: speechPreferences, onNavigate: { section = $0 })
        case .general:
            GeneralTab(speechPreferences: speechPreferences)
        case .speechCheck:
            SpeechCheckTab(speechPreferences: speechPreferences)
        case .bridge:
            BridgeTab()
        case .about:
            AboutTab(speechPreferences: speechPreferences, onNavigate: { section = $0 })
        }
    }

    // MARK: - Inspector

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: HudSpacing.xl) {
            connectionCard

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.md) {
                    HudKVRow("State", value: runtimeSummary.label, valueColor: runtimeSummary.tint)
                    HudKVRow(
                        "Detail",
                        value: runtimeSummary.detail,
                        valueColor: runtimeSummary.tint,
                        valueLineLimit: 1
                    )
                    if let port = monitor.port {
                        HudKVRow("WebSocket API", value: voxPortString(port))
                    }
                    if let pid = monitor.pid {
                        HudKVRow("PID", value: voxProcessIDString(pid))
                    }
                    HudKVRow("HTTP Port", value: voxPortString(bridgeState.port))
                }
            }

            speechStatusCard

            activeSessionCard

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.md) {
                    HudSectionLabel("Version", tint: HudPalette.muted)
                    HudKVRow("Vox", value: VoxVersion.current)
                    HudKVRow("Runtime", value: "macOS")
                }
            }
        }
    }

    private var speechStatusCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.md) {
                HudSectionLabel("Speech")
                HudKVRow("TTS", value: speechPreferences.effectiveSynthesisModelId, valueColor: HudPalette.ink)
                HudKVRow("Backend", value: speechPreferences.effectiveSynthesisBackendLabel, valueColor: HudPalette.muted)
                HudKVRow("Voice", value: speechPreferences.effectiveSynthesisVoiceLabel, valueColor: HudPalette.muted)
                HudKVRow("Input", value: speechPreferences.effectiveInputDeviceLabel, valueColor: HudPalette.muted)
                HudKVRow(
                    "State",
                    value: speechPreferences.effectiveSynthesisAvailabilityLabel,
                    valueColor: speechPreferences.effectiveSynthesisNeedsAPIKey ? HudPalette.statusWarn : HudPalette.muted
                )

                if speechPreferences.effectiveSynthesisNeedsAPIKey {
                    HudButton("Add OpenAI Key", icon: "key.fill", style: .secondary) {
                        section = .general
                    }
                }
            }
        }
    }

    // MARK: - Connection Card

    @ViewBuilder
    private var connectionCard: some View {
        if hasActiveCaller {
            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.md) {
                    HStack {
                        HudSectionLabel("Caller")
                        Spacer()
                        connectionTrustBadge
                    }

                    if let name = callerName {
                        HudKVRow("App", value: name, valueColor: HudPalette.ink)
                    }
                    if let host = callerHost {
                        HudKVRow("Origin", value: host, valueColor: HudPalette.muted)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var connectionTrustBadge: some View {
        switch onboarding.trust {
        case .verified:
            VoxStatusText("VERIFIED", tint: HudPalette.muted)
        case .unverified:
            VoxStatusText("UNVERIFIED", tint: HudPalette.statusError)
        case .noOrigin:
            VoxStatusText("NO ORIGIN", tint: HudPalette.statusWarn)
        case .unknown:
            EmptyView()
        }
    }

    private var hasActiveCaller: Bool {
        if case .unknown = onboarding.trust { return false }
        return true
    }

    private var callerName: String? {
        onboarding.context.productName ?? onboarding.context.sourceName
    }

    private var callerHost: String? {
        guard let origin = onboarding.returnToOrigin else { return nil }
        return URL(string: origin)?.host ?? origin
    }

    // MARK: - Active Session Card

    @ViewBuilder
    private var activeSessionCard: some View {
        if monitor.isRecording {
            sessionCard(
                title: "Active Session",
                badge: "RECORDING",
                tint: HudPalette.statusError,
                clientId: monitor.liveSession?.clientId,
                modelId: monitor.liveSession?.modelId,
                startedAt: monitor.liveSession?.startedAt,
                extras: nil,
                onStop: { await monitor.cancelLiveSession() }
            )
        } else if monitor.isSpeaking {
            sessionCard(
                title: "Active Session",
                badge: "SPEAKING",
                tint: HudPalette.muted,
                clientId: monitor.synthesisSession?.clientId,
                modelId: monitor.synthesisSession?.modelId,
                startedAt: monitor.synthesisSession?.startedAt,
                extras: synthesisExtras,
                onStop: { await monitor.cancelSynthesis() }
            )
        }
    }

    private var synthesisExtras: [(String, String)]? {
        guard let session = monitor.synthesisSession else { return nil }
        var rows: [(String, String)] = []
        if let voiceId = session.voiceId, !voiceId.isEmpty {
            rows.append(("Voice", voiceId))
        }
        if session.textLength > 0 {
            rows.append(("Chars", "\(session.textLength)"))
        }
        return rows.isEmpty ? nil : rows
    }

    private func sessionCard(
        title: String,
        badge: String,
        tint: Color,
        clientId: String?,
        modelId: String?,
        startedAt: Date?,
        extras: [(String, String)]?,
        onStop: @escaping () async -> String?
    ) -> some View {
        HudCard(stroke: HudSurface.tintBorder(tint)) {
            VStack(alignment: .leading, spacing: HudSpacing.md) {
                HStack {
                    HudSectionLabel(title, tint: tint)
                    Spacer()
                    VoxStatusText(badge, tint: tint)
                }

                if let clientId, !clientId.isEmpty {
                    HudKVRow("Client", value: clientId, valueColor: HudPalette.ink)
                }
                if let modelId, !modelId.isEmpty {
                    HudKVRow("Model", value: modelId, valueColor: HudPalette.muted)
                }
                if let extras {
                    ForEach(Array(extras.enumerated()), id: \.offset) { _, row in
                        HudKVRow(row.0, value: row.1, valueColor: HudPalette.muted)
                    }
                }
                if let startedAt {
                    HStack {
                        Text("ELAPSED")
                            .font(HudFont.mono(9))
                            .tracking(0.8)
                            .foregroundStyle(HudPalette.dim)
                        Spacer()
                        ElapsedText(startedAt: startedAt)
                            .font(HudFont.mono(11))
                            .foregroundStyle(HudPalette.ink)
                    }
                }

                if let stopFeedback {
                    HudInset {
                        VoxBodyText(
                            stopFeedback,
                            tint: stopFeedbackIsError ? HudPalette.statusError : HudPalette.muted
                        )
                    }
                }

                HudButton("Stop", icon: "stop.fill", style: .primary(.red)) {
                    runStop(onStop)
                }
                .disabled(stopInFlight)
            }
        }
    }

    private func runStop(_ action: @escaping () async -> String?) {
        guard !stopInFlight else { return }
        stopInFlight = true
        stopFeedbackTask?.cancel()
        stopFeedbackTask = nil

        Task {
            let errorMessage = await action()
            stopInFlight = false
            if let errorMessage {
                stopFeedback = errorMessage
                stopFeedbackIsError = true
            } else {
                stopFeedback = "Session stopped."
                stopFeedbackIsError = false
            }
            stopFeedbackTask = Task { [weak monitor] in
                _ = monitor
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled else { return }
                stopFeedback = nil
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: HudSpacing.xl) {
            Text("vox")
                .font(HudFont.mono(10, weight: .bold))
                .tracking(0)
                .foregroundStyle(HudPalette.muted)
            Text("·")
                .font(HudFont.mono(10))
                .foregroundStyle(HudPalette.dim)
            VoxStatusText(runtimeSummary.badge, tint: runtimeSummary.tint)
            Text(runtimeSummary.detail)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 520, alignment: .leading)
            .font(HudFont.mono(10))
            .foregroundStyle(HudPalette.muted)

            Spacer()

            HudInspectorToggle(isCollapsed: $inspectorCollapsed)
        }
        .padding(.horizontal, HudSpacing.xxl)
        .frame(height: HudLayout.statusBarHeight)
    }

    private var runtimeSummary: VoxRuntimeStatusSummary {
        VoxRuntimeStatusSummary(
            monitor: monitor,
            bridgeState: bridgeState,
            speechPreferences: speechPreferences
        )
    }
}

private struct ElapsedText: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(format(context.date.timeIntervalSince(startedAt)))
                .monospacedDigit()
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
