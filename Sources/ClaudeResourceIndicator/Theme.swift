import AppKit
import SwiftUI

// Shared visual language: traffic-light thresholds used by both the menu-bar
// rings and the popover.
enum Theme {
    static let amberThreshold: Double = 60
    static let redThreshold: Double = 85

    static func nsColor(forUtilization u: Double) -> NSColor {
        switch u {
        case ..<amberThreshold: return .systemGreen
        case ..<redThreshold:   return .systemOrange
        default:                return .systemRed
        }
    }

    static func color(forUtilization u: Double) -> Color {
        Color(nsColor: nsColor(forUtilization: u))
    }

    // Whether a metric is in the red zone — used to add a non-color (shape) cue
    // so severity isn't conveyed by hue alone (U1).
    static func isCritical(_ u: Double) -> Bool { u >= redThreshold }

    static let trackColor = Color(nsColor: .tertiaryLabelColor)
}

enum ResetFormatter {
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    private static let duration: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.day, .hour, .minute]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 2
        return f
    }()

    // `now` is passed in so SwiftUI views can re-render a live countdown.
    static func string(for metric: Metric, resetsAt: Date?, now: Date = Date()) -> String {
        guard let resetsAt else { return "no reset window" }
        switch metric.resetStyle {
        case .relative:
            let remaining = resetsAt.timeIntervalSince(now)
            if remaining <= 0 { return "resetting…" }
            let text = duration.string(from: remaining) ?? ""
            return "resets in \(text)"
        case .weekday:
            return "resets \(weekday.string(from: resetsAt))"
        }
    }
}

func percentText(_ utilization: Double) -> String {
    "\(Int(utilization.rounded()))%"
}
