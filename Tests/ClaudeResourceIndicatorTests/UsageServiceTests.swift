import XCTest
@testable import ClaudeResourceIndicator

final class UsageServiceTests: XCTestCase {

    // D3 — Retry-After: integer delta-seconds and RFC 7231 HTTP-date.
    func testRetryAfterInteger() {
        XCTAssertEqual(UsageService.retryAfterSeconds("30"), 30)
    }

    func testRetryAfterTrimsWhitespace() {
        XCTAssertEqual(UsageService.retryAfterSeconds("  30 "), 30)
    }

    func testRetryAfterNilAndEmpty() {
        XCTAssertNil(UsageService.retryAfterSeconds(nil))
        XCTAssertNil(UsageService.retryAfterSeconds(""))
        XCTAssertNil(UsageService.retryAfterSeconds("not-a-date"))
    }

    func testRetryAfterHTTPDateInFuture() {
        let fmt = Self.imfFormatter
        let now = fmt.date(from: "Sun, 06 Nov 1994 08:49:07 GMT")!
        let seconds = UsageService.retryAfterSeconds("Sun, 06 Nov 1994 08:49:37 GMT", now: now)
        XCTAssertEqual(seconds ?? -1, 30, accuracy: 0.5)
    }

    func testRetryAfterHTTPDateInPastClampsToZero() {
        let fmt = Self.imfFormatter
        let now = fmt.date(from: "Sun, 06 Nov 1994 08:50:00 GMT")!
        let seconds = UsageService.retryAfterSeconds("Sun, 06 Nov 1994 08:49:37 GMT", now: now)
        XCTAssertEqual(seconds, 0)
    }

    // D4 — only decode a 200 whose body is plausibly the JSON we expect.
    func testEmptyBodyRejected() {
        XCTAssertFalse(UsageService.looksLikeJSONBody(contentType: "application/json", data: Data()))
    }

    func testJSONContentTypeAccepted() {
        let data = Data("{}".utf8)
        XCTAssertTrue(UsageService.looksLikeJSONBody(contentType: "application/json; charset=utf-8", data: data))
        XCTAssertTrue(UsageService.looksLikeJSONBody(contentType: "APPLICATION/JSON", data: data))
    }

    func testHTMLContentTypeRejected() {
        let data = Data("<html>captive portal</html>".utf8)
        XCTAssertFalse(UsageService.looksLikeJSONBody(contentType: "text/html", data: data))
    }

    func testAbsentContentTypeIsLenient() {
        let data = Data("{}".utf8)
        XCTAssertTrue(UsageService.looksLikeJSONBody(contentType: nil, data: data))
    }

    // Existing ISO-8601 parsing the endpoint relies on.
    func testISO8601ParsingShapes() {
        XCTAssertNotNil(ISO8601Parsing.date(from: "2026-05-28T11:20:00.428641+00:00"))
        XCTAssertNotNil(ISO8601Parsing.date(from: "2026-05-28T11:20:00+00:00"))
        XCTAssertNil(ISO8601Parsing.date(from: "garbage"))
    }

    private static let imfFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}
