import XCTest
@testable import ClaudeResourceIndicator

// D1 (clamp at source) + Q2 (single fraction property).
final class ModelsTests: XCTestCase {
    func testUtilizationClampsHighToHundred() {
        let v = MetricValue(metric: .session, utilization: 150, resetsAt: nil)
        XCTAssertEqual(v.utilization, 100)
        XCTAssertEqual(v.fraction, 1.0)
    }

    func testUtilizationClampsNegativeToZero() {
        let v = MetricValue(metric: .weekly, utilization: -5, resetsAt: nil)
        XCTAssertEqual(v.utilization, 0)
        XCTAssertEqual(v.fraction, 0.0)
    }

    func testFractionIsUtilizationOverHundred() {
        let v = MetricValue(metric: .opus, utilization: 42, resetsAt: nil)
        XCTAssertEqual(v.utilization, 42)
        XCTAssertEqual(v.fraction, 0.42, accuracy: 1e-9)
    }

    // Q1 — window length lives in the model, not a stringly-typed view special case.
    func testWindowLabels() {
        XCTAssertEqual(Metric.session.windowLabel, "5h")
        XCTAssertEqual(Metric.weekly.windowLabel, "7d")
        XCTAssertEqual(Metric.opus.windowLabel, "7d")
    }
}
