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
    /// - For `.idle`: an 18×18 template V mark that AppKit tints for the current menu-bar appearance.
    /// - For `.recording` / `.speaking`: a 38×22 colored pill with a white V on the left and a white
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
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            NSColor.black.setStroke()
            Self.drawVMark(in: rect)
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
            let vRect = NSRect(x: 5, y: 3, width: 14, height: 16)
            Self.drawVMark(in: vRect)

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

    private static func drawVMark(in rect: NSRect) {
        let strokeWidth = max(1.6, min(rect.width, rect.height) * 0.18)
        let horizontalInset = rect.width * 0.18
        let topY = rect.minY + rect.height * 0.86
        let bottomY = rect.minY + rect.height * 0.16

        let leftTop  = NSPoint(x: rect.minX + horizontalInset, y: topY)
        let rightTop = NSPoint(x: rect.maxX - horizontalInset, y: topY)
        let apex     = NSPoint(x: rect.midX, y: bottomY)

        let path = NSBezierPath()
        path.lineWidth = strokeWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: leftTop)
        path.line(to: apex)
        path.line(to: rightTop)
        path.stroke()
    }
}
