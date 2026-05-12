import SwiftUI
import HudsonUI
import HudsonShell

func voxPortString(_ port: UInt16) -> String {
    String(Int(port))
}

func voxProcessIDString(_ pid: Int32) -> String {
    String(pid)
}

struct VoxRuntimeStatusSummary {
    let label: String
    let detail: String
    let tint: Color

    var badge: String {
        label.uppercased()
    }

    @MainActor
    init(
        monitor: DaemonMonitor,
        bridgeState: BridgeState,
        speechPreferences: SpeechPreferencesState
    ) {
        if monitor.isRecording {
            label = "Recording"
            detail = Self.sessionDetail(
                fallback: "live transcription",
                clientId: monitor.liveSession?.clientId,
                modelId: monitor.liveSession?.modelId
            )
            tint = HudPalette.statusError
        } else if monitor.isSpeaking {
            label = "Speaking"
            detail = Self.sessionDetail(
                fallback: "speech synthesis",
                clientId: monitor.synthesisSession?.clientId,
                modelId: monitor.synthesisSession?.modelId
            )
            tint = HudPalette.muted
        } else if !monitor.isRunning {
            label = "Stopped"
            detail = "daemon offline"
            tint = HudPalette.statusError
        } else if !bridgeState.isRunning {
            label = "Degraded"
            detail = "WebSocket \(Self.portLabel(monitor.port)) · HTTP stopped"
            tint = HudPalette.statusWarn
        } else if speechPreferences.effectiveSynthesisNeedsAPIKey {
            label = "Needs setup"
            detail = "speech key required · APIs ready"
            tint = HudPalette.statusWarn
        } else {
            label = "Ready"
            detail = "WebSocket \(Self.portLabel(monitor.port)) · HTTP \(voxPortString(bridgeState.port))"
            tint = HudPalette.muted
        }
    }

    private static func portLabel(_ port: UInt16?) -> String {
        guard let port else { return "unknown" }
        return voxPortString(port)
    }

    private static func sessionDetail(fallback: String, clientId: String?, modelId: String?) -> String {
        let parts = [clientId, modelId]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return parts.isEmpty ? fallback : parts.joined(separator: " · ")
    }
}

struct VoxScreen<Content: View>: View {
    let title: String
    let badge: String
    let summary: String
    var showGrid = false
    @ViewBuilder var content: Content

    var body: some View {
        HudCanvas(showGrid: showGrid) {
            VStack(alignment: .leading, spacing: HudSpacing.huge) {
                VoxScreenHeader(title: title, badge: badge, summary: summary)
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct VoxScreenHeader: View {
    let title: String
    let badge: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: HudSpacing.md) {
            HStack(spacing: HudSpacing.md) {
                HudSectionLabel(title)
                Text(badge)
                    .font(HudFont.mono(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(HudPalette.dim)
            }

            Text(summary)
                .font(HudFont.ui(HudTextSize.xs))
                .foregroundStyle(HudPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 760, alignment: .leading)
        }
    }
}

struct VoxMetricCard: View {
    let label: String
    let value: String
    let detail: String
    let tint: Color
    var pulses = false

    var body: some View {
        HudCard {
            HStack(spacing: HudSpacing.lg) {
                Rectangle()
                    .fill(pulses ? tint : HudHairline.subtle)
                    .frame(width: 2, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(HudFont.mono(9, weight: .semibold))
                        .foregroundStyle(HudPalette.dim)
                    Text(value)
                        .font(HudFont.mono(HudTextSize.sm, weight: .semibold))
                        .foregroundStyle(HudPalette.ink)
                    Text(detail)
                        .font(HudFont.mono(HudTextSize.xxs))
                        .foregroundStyle(HudPalette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct VoxBodyText: View {
    let text: String
    var tint: Color = HudPalette.muted

    init(_ text: String, tint: Color = HudPalette.muted) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(HudFont.ui(HudTextSize.xs))
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct VoxCodeText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(HudFont.mono(HudTextSize.xxs))
            .foregroundStyle(HudPalette.ink)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }
}

struct VoxStatusText: View {
    let text: String
    var tint: Color = HudPalette.muted

    init(_ text: String, tint: Color = HudPalette.muted) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(HudFont.mono(9, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(tint)
    }
}

struct VoxIconKVRow: View {
    let label: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: HudSpacing.md) {
            Text(label.uppercased())
                .font(HudFont.mono(9))
                .tracking(0.8)
                .foregroundStyle(HudPalette.dim)

            Spacer(minLength: HudSpacing.md)

            HStack(spacing: HudSpacing.xs) {
                Image(systemName: icon)
                    .font(HudFont.ui(11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(HudFont.mono(11))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

struct VoxEmptyList: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HudEmptyState(title: title, subtitle: subtitle, icon: icon)
    }
}
