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
        Color(red: 0.22, green: 0.72, blue: 0.45)
    }
}

struct MinivoxLogo: View {
    let palette: MinivoxPalette
    var size: CGFloat = 27

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(palette.accent)

            Text("M")
                .font(.system(size: size * 0.36, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.78))
        }
        .frame(width: size, height: size)
    }
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
