import AppKit

enum MenuBarIcon {
    static func makeStatusImage(size: CGFloat = 18, showsRecordingBadge: Bool = false) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize, flipped: false) { rect in
            let glyphRect = rect.offsetBy(dx: showsRecordingBadge ? -0.25 : 0, dy: 0)
            let fillColor = showsRecordingBadge ? NSColor.labelColor : NSColor.black
            fillColor.setFill()
            Self.drawBars(
                in: glyphRect,
                heights: [0.86, 0.64, 0.28, 0.64, 0.86]
            )

            if showsRecordingBadge {
                Self.drawRecordingBadge(in: rect)
            }

            return true
        }
        image.isTemplate = !showsRecordingBadge
        image.accessibilityDescription = "Vox"
        return image
    }

    private static func drawBars(in rect: NSRect, heights: [CGFloat]) {
        let totalWidth = rect.width * 0.72
        let gapRatio: CGFloat = 0.55
        let barWidth = totalWidth / (CGFloat(heights.count) + gapRatio * CGFloat(heights.count - 1))
        let gap = barWidth * gapRatio
        let maxHeight = rect.height * 0.78
        let cornerRadius = min(barWidth / 2, 1.8)
        let startX = rect.midX - totalWidth / 2

        for (index, relativeHeight) in heights.enumerated() {
            let barHeight = max(2, maxHeight * relativeHeight)
            let x = startX + CGFloat(index) * (barWidth + gap)
            let y = rect.midY - barHeight / 2
            let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            NSBezierPath(roundedRect: barRect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        }
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
