import AppKit

struct RingSpec {
    let fraction: Double   // 0...1
}

enum RingRenderer {
    static let diameter: CGFloat = 15
    static let lineWidth: CGFloat = 3.5
    static let spacing: CGFloat = 4
    static let verticalPadding: CGFloat = 1.5

    private static let trackAlpha: CGFloat = 0.3
    private static let progressAlpha: CGFloat = 1.0

    // Builds the menu-bar image: one ring per spec, left-to-right. Rendered as a
    // monochrome template image so the system auto-contrasts it against the menu
    // bar (white on dark, black on light). Empty specs render one faint ring.
    static func image(for specs: [RingSpec], scale: CGFloat = 1) -> NSImage {
        let drawSpecs = specs.isEmpty ? [RingSpec(fraction: 0)] : specs
        let d = diameter * scale
        let lw = lineWidth * scale
        let gap = spacing * scale
        let count = drawSpecs.count
        let height = d + verticalPadding * 2 * scale
        let width = CGFloat(count) * d + CGFloat(count - 1) * gap

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            for (i, spec) in drawSpecs.enumerated() {
                let originX = CGFloat(i) * (d + gap)
                drawRing(spec, inCellOriginX: originX, height: height, diameter: d, lineWidth: lw)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func drawRing(_ spec: RingSpec, inCellOriginX originX: CGFloat,
                                 height: CGFloat, diameter: CGFloat, lineWidth: CGFloat) {
        let radius = diameter / 2 - lineWidth / 2
        let center = NSPoint(x: originX + diameter / 2, y: height / 2)

        // Template ink is always black; the alpha channel is what the system
        // tints — so track = faint, progress = solid.
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(trackAlpha).setStroke()
        track.stroke()

        let fraction = max(0, min(1, spec.fraction))
        guard fraction > 0 else { return }
        let endAngle = 90 - 360 * fraction
        let progress = NSBezierPath()
        progress.appendArc(withCenter: center, radius: radius,
                           startAngle: 90, endAngle: endAngle, clockwise: true)
        progress.lineWidth = lineWidth
        progress.lineCapStyle = .round
        NSColor.black.withAlphaComponent(progressAlpha).setStroke()
        progress.stroke()
    }
}
