import AppKit
import SwiftUI

struct MinivoxPalette {
    let colorScheme: ColorScheme

    var background: Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.055, blue: 0.052)
            : Color(red: 0.955, green: 0.947, blue: 0.925)
    }

    var strip: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.075, blue: 0.071)
            : Color(red: 0.92, green: 0.91, blue: 0.885)
    }

    var card: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.075, blue: 0.071)
            : Color(red: 0.985, green: 0.98, blue: 0.965)
    }

    var recessed: Color {
        colorScheme == .dark
            ? Color(red: 0.045, green: 0.045, blue: 0.042)
            : Color(red: 0.935, green: 0.925, blue: 0.90)
    }

    var controlSurface: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.045)
            : Color.black.opacity(0.04)
    }

    var border: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.036)
            : Color.black.opacity(0.058)
    }

    var accent: Color {
        Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    }
}

struct MinivoxLogo: View {
    let palette: MinivoxPalette
    var size: CGFloat = 27

    var body: some View {
        Group {
            if size <= 32 {
                MinivoxCompactMark(palette: palette)
            } else if let icon = MinivoxBrandAssets.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                MinivoxCompactMark(palette: palette)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(palette.colorScheme == .dark ? 0.08 : 0.14),
                    lineWidth: 0.5
                )
        }
        .accessibilityHidden(true)
    }
}

private struct MinivoxCompactMark: View {
    let palette: MinivoxPalette

    private let waveform = [1, 2, 4, 3, 7, 5, 3, 6, 4, 3, 5, 2, 3, 1]

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                Color(red: 0.045, green: 0.045, blue: 0.043)

                Canvas { context, canvasSize in
                    let dot = max(0.9, side * 0.037)
                    let dotGap = dot * 0.48
                    let step = side * 0.044
                    let width = step * CGFloat(waveform.count - 1)
                    let startX = (canvasSize.width - width) / 2

                    for (column, dots) in waveform.enumerated() {
                        let columnHeight = CGFloat(dots) * dot + CGFloat(dots - 1) * dotGap
                        let startY = (canvasSize.height - columnHeight) / 2

                        for row in 0..<dots {
                            let rect = CGRect(
                                x: startX + CGFloat(column) * step - dot / 2,
                                y: startY + CGFloat(row) * (dot + dotGap),
                                width: dot,
                                height: dot
                            )
                            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.9)))
                        }
                    }
                }

                Circle()
                    .fill(palette.accent)
                    .frame(width: side * 0.13, height: side * 0.13)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                    }
                    .offset(x: side * 0.28, y: -side * 0.28)
            }
        }
    }
}

private enum MinivoxBrandAssets {
    static let icon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "vox-app-icon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

struct MinivoxRailButtonStyle: ButtonStyle {
    let palette: MinivoxPalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .textCase(.uppercase)
            .tracking(0.7)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                palette.controlSurface.opacity(configuration.isPressed ? 1.4 : 0.72),
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(palette.border, lineWidth: 0.5)
            }
    }
}
