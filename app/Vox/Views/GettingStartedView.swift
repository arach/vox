import AppKit
import SwiftUI
import HudsonUI
import VoxCore
import VoxEngine

struct GettingStartedContext: Equatable {
    var sourceName: String?
    var productName: String?
    var headline: String
    var detail: String
    var actionLabel: String
    var logo: GettingStartedLogo?

    static let welcome = Self(
        sourceName: nil,
        productName: nil,
        headline: "Welcome to Vox",
        detail: "Vox is a local-first voice runtime for your Mac. Capture speech, synthesize it back, and keep everything on this machine.",
        actionLabel: "Open Bridge Settings",
        logo: nil
    )

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

struct WelcomeTab: View {
    @EnvironmentObject var monitor: DaemonMonitor
    @EnvironmentObject var bridgeState: BridgeState
    @EnvironmentObject var onboarding: OnboardingState

    let onNavigate: (VoxSection) -> Void

    var body: some View {
        VoxScreen(
            title: headerTitle,
            badge: headerBadge,
            summary: headerSummary
        ) {
            heroCard

            if case .unverified(let origin) = onboarding.trust {
                unverifiedCard(origin: origin)
            }

            if case .noOrigin = onboarding.trust {
                noOriginCard
            }

            statusGrid

            quickLinksCard
        }
        .task {
            await bridgeState.refreshOrigins()
        }
    }

    // MARK: - Header

    private var headerTitle: String {
        switch onboarding.trust {
        case .verified, .unverified, .noOrigin:
            return "Connection"
        case .unknown:
            return "Welcome"
        }
    }

    private var headerBadge: String {
        switch onboarding.trust {
        case .verified:    return "VERIFIED CALLER"
        case .unverified:  return "UNVERIFIED"
        case .noOrigin:    return "UNVERIFIABLE"
        case .unknown:     return "LOCAL FIRST"
        }
    }

    private var headerSummary: String {
        switch onboarding.trust {
        case .verified:
            let name = displayName
            return "\(name) is allowed to use the local Vox bridge. Speech runs on this Mac — no audio leaves the device."
        case .unverified:
            return "Vox can't verify the app that opened this window. Allow its origin to unblock bridge requests, or dismiss this view."
        case .noOrigin:
            return "This invocation didn't include a return URL, so Vox can't tie it to an allowlisted origin. Bridge calls follow the standard policy."
        case .unknown:
            return "Vox runs locally and exposes a small bridge for browser apps. Use this view to confirm setup, then dive into the rail for daemon, bridge, and embed controls."
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: HudSpacing.xl) {
                HStack(alignment: .top, spacing: HudSpacing.xl) {
                    if hasRequester {
                        RequesterLogoBadge(
                            logo: onboarding.context.logo,
                            fallbackName: displayName,
                            isMuted: !isVerified
                        )
                    } else {
                        BrandLogoBadge()
                    }

                    VStack(alignment: .leading, spacing: HudSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: HudSpacing.md) {
                            Text(displayName)
                                .font(HudFont.ui(HudTextSize.xxl, weight: .semibold))
                                .foregroundStyle(HudPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            trustBadge
                        }

                        Text(hasRequester ? "powered by vox" : "local voice runtime")
                            .font(HudFont.mono(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(HudPalette.muted)
                            .textCase(.uppercase)
                    }

                    Spacer(minLength: 0)
                }

                if hasRequester {
                    Text(onboarding.context.headline)
                        .font(HudFont.ui(HudTextSize.lg, weight: .medium))
                        .foregroundStyle(HudPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VoxBodyText(onboarding.context.detail)

                heroActions

                if shouldShowMenuBarHint {
                    menuBarHint
                }
            }
        }
    }

    @ViewBuilder
    private var trustBadge: some View {
        switch onboarding.trust {
        case .verified:
            HudBadge("VERIFIED", tint: HudPalette.statusOk, dot: true)
        case .unverified:
            HudBadge("UNVERIFIED", tint: HudPalette.statusError, dot: true)
        case .noOrigin:
            HudBadge("UNVERIFIABLE", tint: HudPalette.statusWarn, dot: true)
        case .unknown:
            HudBadge("LOCAL", tint: HudPalette.statusInfo, dot: true)
        }
    }

    @ViewBuilder
    private var heroActions: some View {
        HStack(spacing: HudSpacing.md) {
            if isVerified, let url = returnURL {
                HudButton(
                    onboarding.context.actionLabel,
                    icon: "arrow.up.right",
                    style: .primary(.cyan)
                ) {
                    NSWorkspace.shared.open(url)
                }
            } else if !hasRequester {
                HudButton("Manage Bridge", icon: "network", style: .primary(.cyan)) {
                    onNavigate(.bridge)
                }
            }

            if hasRequester {
                HudButton("Open Bridge", icon: "network", style: .secondary) {
                    onNavigate(.bridge)
                }
            }

            if !monitor.isRunning {
                HudButton("Restart Daemon", icon: "arrow.clockwise", style: .secondary) {
                    LaunchAgentManager.restart()
                    monitor.checkNow()
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var menuBarHint: some View {
        HudInset {
            HStack(spacing: HudSpacing.lg) {
                Image(systemName: "menubar.dock.rectangle")
                    .font(HudFont.ui(HudTextSize.sm))
                    .foregroundStyle(HudPalette.muted)
                Text("Vox lives in your menu bar — look for the V mark")
                    .font(HudFont.mono(11))
                    .foregroundStyle(HudPalette.muted)
                Spacer(minLength: HudSpacing.md)
                Image(nsImage: MenuBarIcon.makeStatusImage(size: 16, showsRecordingBadge: false))
                    .renderingMode(.template)
                    .foregroundStyle(HudPalette.ink)
                    .frame(width: 16, height: 16)
            }
        }
    }

    // MARK: - Trust treatments

    private func unverifiedCard(origin: String) -> some View {
        HudCard(stroke: HudSurface.tintBorder(HudPalette.statusError)) {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack(spacing: HudSpacing.md) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(HudFont.ui(HudTextSize.lg))
                        .foregroundStyle(HudPalette.statusError)
                    Text("Can't verify this app")
                        .font(HudFont.ui(HudTextSize.md, weight: .semibold))
                        .foregroundStyle(HudPalette.ink)
                    Spacer()
                    HudBadge("ACTION NEEDED", tint: HudPalette.statusError, dot: true)
                }

                VoxBodyText(
                    "Bridge calls from this site will return 403 until you allow its origin. Only trust apps you launched yourself."
                )

                HudInset {
                    VStack(alignment: .leading, spacing: HudSpacing.md) {
                        HudKVRow("Origin", value: origin, valueColor: HudPalette.ink)
                        if let host = URL(string: origin)?.host {
                            HudKVRow("Host", value: host, valueColor: HudPalette.muted)
                        }
                    }
                }

                if let message = onboarding.trustErrorMessage, !message.isEmpty {
                    HudInset {
                        VoxBodyText(message, tint: HudPalette.statusError)
                    }
                }

                HStack(spacing: HudSpacing.md) {
                    HudButton(
                        "Allow \(displayHost(origin))",
                        icon: "checkmark.shield",
                        style: .primary(.green)
                    ) {
                        Task { await onboarding.allowReturnOrigin() }
                    }

                    HudButton("Open Bridge tab", icon: "network", style: .secondary) {
                        onNavigate(.bridge)
                    }

                    Spacer()
                }
            }
        }
    }

    private var noOriginCard: some View {
        HudCard(stroke: HudSurface.tintBorder(HudPalette.statusWarn)) {
            VStack(alignment: .leading, spacing: HudSpacing.lg) {
                HStack(spacing: HudSpacing.md) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(HudFont.ui(HudTextSize.lg))
                        .foregroundStyle(HudPalette.statusWarn)
                    Text("No return URL provided")
                        .font(HudFont.ui(HudTextSize.md, weight: .semibold))
                        .foregroundStyle(HudPalette.ink)
                    Spacer()
                    HudBadge("INFORMATIONAL", tint: HudPalette.statusWarn, dot: true)
                }

                VoxBodyText(
                    "This launch didn't include a returnTo URL, so Vox can't tie it to an allowlisted origin. Add the calling site under Bridge to enable browser requests."
                )

                HudButton("Open Bridge tab", icon: "network", style: .secondary) {
                    onNavigate(.bridge)
                }
            }
        }
    }

    // MARK: - Status grid

    private var statusGrid: some View {
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
                label: "HTTP Bridge",
                value: bridgeState.isRunning ? "Listening" : "Stopped",
                detail: "127.0.0.1:\(voxPortString(bridgeState.port))",
                tint: bridgeState.isRunning ? HudPalette.statusInfo : HudPalette.statusError,
                pulses: bridgeState.isRunning
            )
            VoxMetricCard(
                label: "Allowed Origins",
                value: "\(totalOriginCount)",
                detail: originBreakdown,
                tint: HudPalette.statusOk
            )
        }
    }

    // MARK: - Quick links

    private var quickLinksCard: some View {
        HudCard(padding: HudSpacing.md) {
            VStack(alignment: .leading, spacing: HudSpacing.md) {
                HStack {
                    HudSectionLabel("Where To Next")
                        .padding(.horizontal, HudSpacing.md)
                    Spacer()
                }
                .padding(.top, HudSpacing.xs)

                HudListRow(
                    title: "Inspect daemon and speech defaults",
                    subtitle: "General · runtime, models, voices",
                    icon: "gearshape",
                    iconTint: .cyan,
                    onTap: { onNavigate(.general) }
                )
                HudListRow(
                    title: "Manage allowed origins",
                    subtitle: "Bridge · add or remove sites that may call Vox",
                    icon: "network",
                    iconTint: .blue,
                    onTap: { onNavigate(.bridge) }
                )
                HudListRow(
                    title: "Try the embed demo",
                    subtitle: "Embed · exercise ASR + TTS in-process",
                    icon: "waveform.and.mic",
                    iconTint: .green,
                    onTap: { onNavigate(.embed) }
                )
                HudListRow(
                    title: "About Vox",
                    subtitle: "About · version and runtime contract",
                    icon: "info.circle",
                    iconTint: .teal,
                    onTap: { onNavigate(.about) }
                )
            }
        }
    }

    // MARK: - Derived

    private var displayName: String {
        if let product = onboarding.context.productName, !product.isEmpty { return product }
        if let source = onboarding.context.sourceName, !source.isEmpty { return source }
        return "Vox"
    }

    private var hasRequester: Bool {
        onboarding.context.sourceName != nil || onboarding.context.productName != nil
    }

    private var isVerified: Bool {
        if case .verified = onboarding.trust { return true }
        return false
    }

    private var shouldShowMenuBarHint: Bool {
        if case .unknown = onboarding.trust { return true }
        return false
    }

    private var returnURL: URL? {
        guard let raw = onboarding.returnToOrigin, let url = URL(string: raw) else { return nil }
        return url
    }

    private func displayHost(_ origin: String) -> String {
        URL(string: origin)?.host ?? origin
    }

    private var daemonDetail: String {
        if monitor.isRunning, let port = monitor.port {
            return "port \(voxPortString(port))"
        }
        if monitor.isRunning {
            return "running"
        }
        return "Restart from General tab"
    }

    private var totalOriginCount: Int {
        bridgeState.builtinOrigins.count
            + bridgeState.userOrigins.count
            + bridgeState.integrationOrigins.count
    }

    private var originBreakdown: String {
        "\(bridgeState.userOrigins.count) user · \(bridgeState.integrationOrigins.count) integrations"
    }
}

private struct BrandLogoBadge: View {
    private static let logo: NSImage? = {
        guard let url = Bundle.module.url(forResource: "vox-logo", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let logo = Self.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: HudRadius.card, style: .continuous)
                    .fill(HudPalette.surface)
                    .overlay(
                        Image(systemName: "waveform")
                            .font(HudFont.ui(HudTextSize.xxl, weight: .semibold))
                            .foregroundStyle(HudPalette.muted)
                    )
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: HudRadius.card, style: .continuous))
        .accessibilityLabel("Vox")
    }
}

private struct RequesterLogoBadge: View {
    let logo: GettingStartedLogo?
    let fallbackName: String?
    var isMuted: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HudRadius.card, style: .continuous)
                .fill(backgroundFill)
                .overlay(
                    RoundedRectangle(cornerRadius: HudRadius.card, style: .continuous)
                        .stroke(borderStroke, lineWidth: 1)
                )

            logoContent
                .frame(width: 36, height: 36)
                .opacity(isMuted ? 0.55 : 1)
        }
        .frame(width: 56, height: 56)
    }

    private var backgroundFill: Color {
        isMuted
            ? HudPalette.surface
            : HudSurface.tintFill(HudTint.cyan.color)
    }

    private var borderStroke: Color {
        isMuted
            ? HudHairline.standard
            : HudSurface.tintBorder(HudTint.cyan.color)
    }

    @ViewBuilder
    private var logoContent: some View {
        if let image = localImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: HudRadius.standard, style: .continuous))
        } else if let url = logo?.url, url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: HudRadius.standard, style: .continuous))
                default:
                    fallbackLogo
                }
            }
        } else {
            fallbackLogo
        }
    }

    private var localImage: NSImage? {
        guard let url = logo?.url, url.isFileURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private var fallbackLogo: some View {
        Group {
            if let symbolName = logo?.symbolName {
                Image(systemName: symbolName)
                    .font(HudFont.ui(HudTextSize.xxl, weight: .semibold))
                    .foregroundStyle(HudTint.cyan.color)
            } else if let initial = fallbackName?.first {
                Text(String(initial).uppercased())
                    .font(HudFont.ui(HudTextSize.xxl, weight: .bold))
                    .foregroundStyle(HudTint.cyan.color)
            } else {
                Image(systemName: "waveform")
                    .font(HudFont.ui(HudTextSize.xxl, weight: .semibold))
                    .foregroundStyle(HudTint.cyan.color)
            }
        }
    }
}
