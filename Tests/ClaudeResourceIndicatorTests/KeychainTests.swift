import XCTest
@testable import ClaudeResourceIndicator

final class KeychainTests: XCTestCase {

    private let instant: TimeInterval = 1_750_000_000        // seconds epoch
    private var instantMillis: Double { instant * 1000 }     // same instant, ms

    // D2 — parse ms epoch, seconds epoch, ISO-8601 string, and numeric string;
    // nil for anything unrecognized.
    func testParseExpiryMillisEpoch() {
        let date = ClaudeCredentials.parseExpiry(instantMillis)
        XCTAssertEqual(date?.timeIntervalSince1970 ?? -1, instant, accuracy: 0.001)
    }

    func testParseExpirySecondsEpoch() {
        let date = ClaudeCredentials.parseExpiry(instant)
        XCTAssertEqual(date?.timeIntervalSince1970 ?? -1, instant, accuracy: 0.001)
    }

    func testParseExpiryNumericString() {
        let date = ClaudeCredentials.parseExpiry(String(Int(instantMillis)))
        XCTAssertEqual(date?.timeIntervalSince1970 ?? -1, instant, accuracy: 0.001)
    }

    func testParseExpiryISO8601String() {
        let date = ClaudeCredentials.parseExpiry("2026-05-28T11:20:00+00:00")
        XCTAssertNotNil(date)
    }

    func testParseExpiryGarbageAndNil() {
        XCTAssertNil(ClaudeCredentials.parseExpiry("nope"))
        XCTAssertNil(ClaudeCredentials.parseExpiry(nil))
    }

    // D5 — local expiry is a hint with skew tolerance; the server is authoritative.
    func testExpiryWithinLeewayNotConsideredExpired() {
        let creds = Credentials(accessToken: "t",
                                expiresAt: Date().addingTimeInterval(-60),
                                subscriptionType: nil)
        XCTAssertTrue(creds.isExpired(skew: 0))
        XCTAssertFalse(creds.isExpired(skew: 300))
    }

    func testExpiryBeyondLeewayIsExpired() {
        let creds = Credentials(accessToken: "t",
                                expiresAt: Date().addingTimeInterval(-600),
                                subscriptionType: nil)
        XCTAssertTrue(creds.isExpired(skew: 300))
    }

    func testNilExpiryNeverExpires() {
        let creds = Credentials(accessToken: "t", expiresAt: nil, subscriptionType: nil)
        XCTAssertFalse(creds.isExpired(skew: 0))
        XCTAssertFalse(creds.isExpired(skew: 300))
    }
}
