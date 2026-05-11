import AppKit

enum MenuBarIcon {
    static func makeStatusImage(size: CGFloat = 18, showsRecordingBadge: Bool = false) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            let glyphRect = rect.offsetBy(dx: showsRecordingBadge ? -0.5 : 0, dy: 0)
            let strokeColor = showsRecordingBadge ? NSColor.labelColor : NSColor.black
            strokeColor.setStroke()
            Self.drawVMark(in: glyphRect)

            if showsRecordingBadge {
                Self.drawRecordingBadge(in: rect)
            }

            return true
        }
        image.isTemplate = !showsRecordingBadge
        image.accessibilityDescription = "Vox"
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

    private static func drawRecordingBadge(in rect: NSRect) {
        let outerDiameter = max(5.0, rect.width * 0.34)
        let innerDiameter = outerDiameter * 0.58
        let center = NSPoint(
            x: rect.maxX - outerDiameter * 0.54,
            y: rect.maxY - outerDiameter * 0.54
        )

        let haloRect = NSRect(
            x: center.x - outerDiameter / 2,
            y: center.y - outerDiameter / 2,
            width: outerDiameter,
            height: outerDiameter
        )
        NSColor.systemRed.withAlphaComponent(0.20).setFill()
        NSBezierPath(ovalIn: haloRect).fill()

        let dotRect = NSRect(
            x: center.x - innerDiameter / 2,
            y: center.y - innerDiameter / 2,
            width: innerDiameter,
            height: innerDiameter
        )
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}
