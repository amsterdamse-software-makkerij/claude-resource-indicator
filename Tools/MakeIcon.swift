#!/usr/bin/env swift
import AppKit
import Foundation

// Renders a ring-motif app icon (concentric green/orange rings on a graphite
// rounded square) into an .icns. Usage: swift Tools/MakeIcon.swift <out.icns>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func renderIcon(pixels s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded-square background with a subtle vertical gradient.
    let margin = s * 0.06
    let rect = NSRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let corner = s * 0.225
    let bg = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    let gradient = NSGradient(starting: NSColor(calibratedWhite: 0.20, alpha: 1),
                              ending: NSColor(calibratedWhite: 0.11, alpha: 1))!
    gradient.draw(in: bg, angle: -90)

    let center = NSPoint(x: s / 2, y: s / 2)
    let ringWidth = s * 0.085
    drawRing(center: center, radius: s * 0.30, width: ringWidth,
             fraction: 0.70, color: .systemGreen)
    drawRing(center: center, radius: s * 0.30 - ringWidth * 1.7, width: ringWidth,
             fraction: 0.45, color: .systemOrange)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawRing(center: NSPoint, radius: CGFloat, width: CGFloat, fraction: Double, color: NSColor) {
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    track.stroke()

    let end = 90 - 360 * fraction
    let progress = NSBezierPath()
    progress.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: end, clockwise: true)
    progress.lineWidth = width
    progress.lineCapStyle = .round
    color.setStroke()
    progress.stroke()
}

// Build a temporary .iconset then convert with iconutil.
let iconset = NSTemporaryDirectory() + "AppIcon-\(getpid()).iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let entries: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for entry in entries {
    let rep = renderIcon(pixels: entry.px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(entry.name)"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", outPath]
try? task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconset)
print(task.terminationStatus == 0 ? "Wrote \(outPath)" : "iconutil failed (\(task.terminationStatus))")
