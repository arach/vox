import SwiftUI
import HudsonUI
import HudsonShell

func voxPortString(_ port: UInt16) -> String {
    String(Int(port))
}

func voxProcessIDString(_ pid: Int32) -> String {
    String(pid)
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
                HudBadge(badge, tint: HudPalette.statusInfo)
            }

            Text(summary)
                .font(HudFont.ui(12))
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
                HudStatusDot(color: tint, pulses: pulses)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(HudFont.mono(9, weight: .semibold))
                        .foregroundStyle(HudPalette.dim)
                    Text(value)
                        .font(HudFont.mono(13, weight: .semibold))
                        .foregroundStyle(HudPalette.ink)
                    Text(detail)
                        .font(HudFont.mono(10))
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
            .font(HudFont.ui(12))
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
            .font(HudFont.mono(11))
            .foregroundStyle(HudPalette.ink)
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
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
