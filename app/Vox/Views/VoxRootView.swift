import SwiftUI
import HudsonUI
import HudsonShell
import VoxCore

// MARK: - Navigation Sections

enum VoxSection: String, CaseIterable, Identifiable {
    case welcome
    case general
    case bridge
    case embed
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .general: return "General"
        case .bridge: return "Bridge"
        case .embed: return "Embed Demo"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "sparkles"
        case .general: return "gearshape"
        case .bridge: return "network"
        case .embed: return "waveform.and.mic"
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

    @State private var section: VoxSection = .welcome
    @State private var railExpanded = true
    @State private var inspectorCollapsed = false
    @State private var stopFeedback: String?
    @State private var stopFeedbackIsError = false
    @State private var stopInFlight = false
    @State private var stopFeedbackTask: Task<Void, Never>?

    private let manifest = HudAppManifest(
        name: "Vox",
        version: VoxVersion.current,
        tint: .cyan,
        targetLabel: "Runtime"
    )

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
                items: VoxSection.allCases.map(\.navItem),
                isExpanded: $railExpanded
            ) {
                railFooter
            }
        } trailing: {
            HudInspector(isCollapsed: $inspectorCollapsed) {
                HStack {
                    HudSectionLabel("Status")
                    Spacer()
                    HudStatusDot(
                        color: monitor.isRunning ? HudPalette.statusOk : HudPalette.statusError
                    )
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
        .onChange(of: onboarding.requestToken) { _, _ in
            section = .welcome
        }
    }

    // MARK: - Rail Footer

    private var railFooter: some View {
        VStack(alignment: .leading, spacing: HudSpacing.md) {
            HudSectionLabel("Daemon")
            HudBadge(
                monitor.isRunning ? "RUNNING" : "STOPPED",
                tint: monitor.isRunning ? HudPalette.statusOk : HudPalette.statusError,
                dot: true
            )
        }
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .welcome:
            WelcomeTab(onNavigate: { section = $0 })
        case .general:
            GeneralTab()
        case .bridge:
            BridgeTab()
        case .embed:
            EmbedDemoTab()
        case .about:
            AboutTab()
        }
    }

    // MARK: - Inspector

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: HudSpacing.xl) {
            connectionCard

            HudCard {
                VStack(alignment: .leading, spacing: HudSpacing.md) {
                    HudKVRow(
                        "Daemon",
                        value: monitor.isRunning ? "Running" : "Stopped",
                        valueColor: monitor.isRunning ? HudPalette.statusOk : HudPalette.statusError
                    )
                    if let port = monitor.port {
                        HudKVRow("Port", value: voxPortString(port))
                    }
                    if let pid = monitor.pid {
                        HudKVRow("PID", value: voxProcessIDString(pid))
                    }
                    HudKVRow(
                        "Bridge",
                        value: bridgeState.isRunning ? "Listening" : "Stopped",
                        valueColor: bridgeState.isRunning ? HudPalette.statusInfo : HudPalette.statusError
                    )
                    HudKVRow("Bridge Port", value: voxPortString(bridgeState.port))
                }
            }

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
            HudBadge("VERIFIED", tint: HudPalette.statusOk, dot: true)
        case .unverified:
            HudBadge("UNVERIFIED", tint: HudPalette.statusError, dot: true)
        case .noOrigin:
            HudBadge("NO ORIGIN", tint: HudPalette.statusWarn, dot: true)
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
                tint: HudPalette.statusInfo,
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
                    HudBadge(badge, tint: tint, dot: true)
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
                            tint: stopFeedbackIsError ? HudPalette.statusError : HudPalette.statusOk
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
            HudStatusDot(color: monitor.isRunning ? HudPalette.statusOk : HudPalette.dim)
            Text("VOX")
                .font(HudFont.mono(10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(HudPalette.muted)
            Text("·")
                .font(HudFont.mono(10))
                .foregroundStyle(HudPalette.dim)
            Group {
                if let port = monitor.port, monitor.isRunning {
                    Text("port \(voxPortString(port))")
                } else {
                    Text("daemon stopped")
                }
            }
            .font(HudFont.mono(10))
            .foregroundStyle(HudPalette.muted)

            Spacer()

            if monitor.isRecording {
                HudBadge("RECORDING", tint: HudPalette.statusError, dot: true)
            } else if monitor.isSpeaking {
                HudBadge("SPEAKING", tint: HudPalette.statusInfo, dot: true)
            }

            HudBadge(section.title.uppercased(), tint: manifest.accent)
            HudInspectorToggle(isCollapsed: $inspectorCollapsed)
        }
        .padding(.horizontal, HudSpacing.xxl)
        .frame(height: HudLayout.statusBarHeight)
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
