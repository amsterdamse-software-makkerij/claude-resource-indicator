import AppKit

// Diagnostic: renders the menu-bar ring glyph to a PNG (enlarged) so the custom
// CoreGraphics drawing can be inspected without Screen Recording permission.
// Invoked via `--render-rings <path>`. Sibling to `--selftest`.
// B1: compiled into DEBUG builds only — not shipped in release.
#if DEBUG
enum RenderTest {

    static func writeRings(to path: String) {
        let samples: [[RingSpec]] = [
            [ring(6), ring(9)],                 // current real state
            [ring(70), ring(92), ring(40)],     // 3 rings at varied fill
            []                                  // inactive / no data
        ]
        let scale: CGFloat = 8
        let images = samples.map { RingRenderer.image(for: $0, scale: scale) }
        let gap: CGFloat = 28
        let height = images.map { $0.size.height }.max() ?? 0
        let width = images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(images.count - 1)

        // Monochrome template ink is black; render on a light background to see it
        // (the system would invert it to white on a dark menu bar).
        let canvas = NSImage(size: NSSize(width: width, height: height))
        canvas.lockFocus()
        NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        var x: CGFloat = 0
        for image in images {
            image.draw(at: NSPoint(x: x, y: (height - image.size.height) / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            x += image.size.width + gap
        }
        canvas.unlockFocus()

        writePNG(canvas, to: path)
        print("Wrote rings preview to \(path)")
    }

    private static func ring(_ utilization: Double) -> RingSpec {
        RingSpec(fraction: utilization / 100)
    }

    private static func writePNG(_ image: NSImage, to path: String) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("Failed to encode PNG")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
#endif
