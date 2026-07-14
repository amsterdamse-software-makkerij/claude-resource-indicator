import AppKit
import XCTest
@testable import ClaudeResourceIndicator

// Shared thresholds + formatters — the small pure logic behind the display.
final class ThemeTests: XCTestCase {
    func testSeverityThresholds() {
        XCTAssertEqual(Theme.nsColor(forUtilization: 59.9), .systemGreen)
        XCTAssertEqual(Theme.nsColor(forUtilization: 60), .systemOrange)   // >= amber
        XCTAssertEqual(Theme.nsColor(forUtilization: 84.9), .systemOrange)
        XCTAssertEqual(Theme.nsColor(forUtilization: 85), .systemRed)      // >= red
    }

    func testIsCriticalMatchesRedThreshold() {
        XCTAssertFalse(Theme.isCritical(84.9))
        XCTAssertTrue(Theme.isCritical(85))
        XCTAssertTrue(Theme.isCritical(100))
    }

    func testPercentTextRounds() {
        XCTAssertEqual(percentText(49.6), "50%")
        XCTAssertEqual(percentText(0), "0%")
        XCTAssertEqual(percentText(100), "100%")
    }

    func testResetFormatterNoWindow() {
        XCTAssertEqual(ResetFormatter.string(for: .session, resetsAt: nil), "no reset window")
    }

    func testResetFormatterSessionPastResetting() {
        let past = Date().addingTimeInterval(-10)
        XCTAssertEqual(ResetFormatter.string(for: .session, resetsAt: past), "resetting…")
    }

    func testResetFormatterWeeklyPrefix() {
        let future = Date().addingTimeInterval(3 * 24 * 3600)
        XCTAssertTrue(ResetFormatter.string(for: .weekly, resetsAt: future).hasPrefix("resets "))
    }
}
