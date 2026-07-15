import AppKit

enum MenuBarIcon {
    enum State {
        case idle
        case recording
        case speaking

        var pillColor: NSColor? {
            switch self {
            case .idle:      return nil
            case .recording: return .systemRed
            case .speaking:  return NSColor(red: 59.0/255, green: 130.0/255, blue: 246.0/255, alpha: 1)
            }
        }
    }

    /// Primary entry point. Returns:
    /// - For `.idle`: a native template waveform symbol that AppKit tints for the current menu-bar appearance.
    /// - For `.recording` / `.speaking`: a 38×22 colored pill with a compact waveform on the left and a
    ///   live-dot on the right. `isTemplate = false` so the tint stays.
    static func makeStatusImage(state: State = .idle, size: CGFloat = 18) -> NSImage {
        switch state {
        case .idle:
            return makeIdleImage(size: size)
        case .recording, .speaking:
            return makeActivePill(state: state)
        }
    }

    /// Legacy two-argument entry point for callers that only care about recording vs idle.
    /// Prefer the `state:`-based call site for new code.
    static func makeStatusImage(size: CGFloat = 18, showsRecordingBadge: Bool = false) -> NSImage {
        makeStatusImage(state: showsRecordingBadge ? .recording : .idle, size: size)
    }

    private static func makeIdleImage(size: CGFloat) -> NSImage {
        if let image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Vox"
        ) {
            image.size = NSSize(width: size, height: size)
            image.isTemplate = true
            return image
        }

        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSColor.black.setStroke()
            Self.drawCompactWaveformMark(in: rect.insetBy(dx: 2, dy: 3))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Vox"
        return image
    }

    private static func makeActivePill(state: State) -> NSImage {
        guard let pillColor = state.pillColor else {
            return makeIdleImage(size: 18)
        }

        let height: CGFloat = 22
        let pillWidth: CGFloat = 38

        let image = NSImage(size: NSSize(width: pillWidth, height: height), flipped: false) { rect in
            let bgRect = rect.insetBy(dx: 1, dy: 1)
            let cornerRadius = bgRect.height / 2
            let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
            pillColor.withAlphaComponent(0.92).setFill()
            bgPath.fill()

            NSColor.white.setStroke()
            let markRect = NSRect(x: 7, y: 6, width: 12, height: 10)
            Self.drawCompactWaveformMark(in: markRect)

            let dotDiameter: CGFloat = 6
            let dotX = pillWidth - dotDiameter - 7
            let dotY = (height - dotDiameter) / 2
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: dotX, y: dotY, width: dotDiameter, height: dotDiameter)).fill()

            return true
        }
        image.isTemplate = false
        let label: String
        switch state {
        case .recording: label = "Vox · recording"
        case .speaking:  label = "Vox · speaking"
        case .idle:      label = "Vox"
        }
        image.accessibilityDescription = label
        return image
    }

    private static func drawCompactWaveformMark(in rect: NSRect) {
        let bars: [CGFloat] = [0.45, 0.9, 0.45]
        let strokeWidth = max(1.6, min(rect.width, rect.height) * 0.16)
        let step = rect.width / CGFloat(max(bars.count - 1, 1))
        let midY = rect.midY

        for (index, scale) in bars.enumerated() {
            let x = rect.minX + CGFloat(index) * step
            let halfHeight = max(1.5, rect.height * scale * 0.5)
            let path = NSBezierPath()
            path.lineWidth = strokeWidth
            path.lineCapStyle = .round
            path.move(to: NSPoint(x: x, y: midY - halfHeight))
            path.line(to: NSPoint(x: x, y: midY + halfHeight))
            path.stroke()
        }
    }
}
