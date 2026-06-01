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

    @ObservedObject var speechPreferences: SpeechPreferencesState
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
            speechSetupCard

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
            return "Vox runs locally and exposes a small bridge for browser apps. Use this view to confirm setup, then inspect runtime and bridge controls from the rail."
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
                                .font(HudFont.ui(HudTextSize.xl, weight: .semibold))
                                .foregroundStyle(HudPalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            trustBadge
                        }

                        Text(hasRequester ? "powered by vox" : "local voice runtime")
                            .font(HudFont.mono(HudTextSize.micro, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(HudPalette.muted)
                            .textCase(.uppercase)
                    }

                    Spacer(minLength: 0)
                }

                if hasRequester {
                    Text(onboarding.context.headline)
                        .font(HudFont.ui(HudTextSize.md, weight: .medium))
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
            VoxStatusText("VERIFIED", tint: HudPalette.muted)
        case .unverified:
            VoxStatusText("UNVERIFIED", tint: HudPalette.statusError)
        case .noOrigin:
            VoxStatusText("UNVERIFIABLE", tint: HudPalette.statusWarn)
        case .unknown:
            VoxStatusText("LOCAL", tint: HudPalette.muted)
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
                HudButton("Manage Bridge", icon: "network", style: .secondary) {
                    onNavigate(.doctor)
                }
            }

            if hasRequester {
                HudButton("Open Bridge", icon: "network", style: .secondary) {
                    onNavigate(.doctor)
                }
            }

            if !monitor.isRunning {
                HudButton("Open Doctor", icon: "stethoscope", style: .secondary) {
                    onNavigate(.doctor)
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
                Text("Vox lives in your menu bar")
                    .font(HudFont.mono(HudTextSize.xxs))
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
                    VoxStatusText("ACTION NEEDED", tint: HudPalette.statusError)
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
                        style: .primary(.cyan)
                    ) {
                        Task { await onboarding.allowReturnOrigin() }
                    }

                    HudButton("Open Bridge tab", icon: "network", style: .secondary) {
                        onNavigate(.doctor)
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
                    VoxStatusText("INFORMATIONAL", tint: HudPalette.statusWarn)
                }

                VoxBodyText(
                    "This launch didn't include a returnTo URL, so Vox can't tie it to an allowlisted origin. Add the calling site under Bridge to enable browser requests."
                )

                HudButton("Open Bridge tab", icon: "network", style: .secondary) {
                    onNavigate(.doctor)
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
                label: "Status",
                value: runtimeSummary.label,
                detail: runtimeSummary.detail,
                tint: runtimeSummary.tint
            )
            VoxMetricCard(
                label: "Allowed Origins",
                value: "\(totalOriginCount)",
                detail: originBreakdown,
                tint: HudPalette.muted
            )
            VoxMetricCard(
                label: "TTS",
                value: speechStatusValue,
                detail: speechStatusDetail,
                tint: speechPreferences.effectiveSynthesisNeedsAPIKey ? HudPalette.statusWarn : HudPalette.muted
            )
        }
    }

    @ViewBuilder
    private var speechSetupCard: some View {
        if speechPreferences.effectiveSynthesisNeedsAPIKey {
            HudCard(stroke: HudSurface.tintBorder(HudPalette.statusWarn)) {
                VStack(alignment: .leading, spacing: HudSpacing.lg) {
                    HStack(spacing: HudSpacing.md) {
                        Image(systemName: "key.fill")
                            .font(HudFont.ui(HudTextSize.md))
                            .foregroundStyle(HudPalette.statusWarn)
                        HudSectionLabel("Speech Setup", tint: HudPalette.statusWarn)
                        Spacer()
                    }

                    VoxBodyText("The default speech provider is OpenAI TTS. Add a Vox OpenAI key here, or let a caller lend credentials explicitly with its request.")

                    HudButton("Add OpenAI Key", icon: "key.fill", style: .secondary) {
                        onNavigate(.configureTTS)
                    }
                }
            }
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
                    title: "Review Vox and daemon state",
                    subtitle: "Overview · version, launch agent, runtime",
                    icon: "info.circle",
                    iconTint: .cyan,
                    onTap: { onNavigate(.overview) }
                )
                HudListRow(
                    title: "Configure speech output",
                    subtitle: "TTS · provider credentials, model, voice, test",
                    icon: "speaker.wave.2",
                    iconTint: .cyan,
                    onTap: { onNavigate(.configureTTS) }
                )
                HudListRow(
                    title: "Configure transcription",
                    subtitle: "ASR · model, input device, dictation check",
                    icon: "waveform.and.mic",
                    iconTint: .cyan,
                    onTap: { onNavigate(.configureASR) }
                )
                HudListRow(
                    title: "Run Doctor and manage API",
                    subtitle: "Doctor · current state, sessions, HTTP API",
                    icon: "stethoscope",
                    iconTint: .cyan,
                    onTap: { onNavigate(.doctor) }
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

    private var runtimeSummary: VoxRuntimeStatusSummary {
        VoxRuntimeStatusSummary(
            monitor: monitor,
            bridgeState: bridgeState,
            speechPreferences: speechPreferences
        )
    }

    private var totalOriginCount: Int {
        bridgeState.builtinOrigins.count
            + bridgeState.userOrigins.count
            + bridgeState.integrationOrigins.count
    }

    private var originBreakdown: String {
        "\(bridgeState.userOrigins.count) user · \(bridgeState.integrationOrigins.count) integrations"
    }

    private var speechStatusValue: String {
        speechPreferences.effectiveSynthesisNeedsAPIKey
            ? "Needs API key"
            : speechPreferences.effectiveSynthesisModelId
    }

    private var speechStatusDetail: String {
        if speechPreferences.effectiveSynthesisNeedsAPIKey {
            return "Open General to add key"
        }
        return "\(speechPreferences.effectiveSynthesisBackendLabel) · \(speechPreferences.effectiveSynthesisVoiceLabel)"
    }
}

private struct BrandLogoBadge: View {
    @Environment(\.hudTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
            .fill(theme.palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                    .stroke(theme.hairline.subtle, lineWidth: 1)
            )
            .overlay {
                Image(systemName: "waveform")
                    .font(HudFont.ui(HudTextSize.xxl, weight: .semibold))
                    .foregroundStyle(theme.palette.muted)
            }
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(theme.palette.statusError)
                    .frame(width: 5, height: 5)
                    .padding(12)
            }
        .frame(width: 56, height: 56)
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
