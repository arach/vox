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

            if monitor.isRecording {
                HudCard {
                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        HudBadge("RECORDING", tint: HudPalette.statusError, dot: true)
                        if let clientId = monitor.liveSessionClientId {
                            HudKVRow("Client", value: clientId)
                        }
                        if let modelId = monitor.liveSessionModelId {
                            HudKVRow("Model", value: modelId)
                        }
                    }
                }
            }

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
            }

            HudBadge(section.title.uppercased(), tint: manifest.accent)
            HudInspectorToggle(isCollapsed: $inspectorCollapsed)
        }
        .padding(.horizontal, HudSpacing.xxl)
        .frame(height: HudLayout.statusBarHeight)
    }
}
