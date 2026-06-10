import XCTest
@testable import UsageCore

final class UsageFormattingTests: XCTestCase {
    func testGetLevelReturnsExpected() {
        XCTAssertEqual(UsageFormatting.level(for: 0.0), .normal)
        XCTAssertEqual(UsageFormatting.level(for: 69.99), .normal)
        XCTAssertEqual(UsageFormatting.level(for: 70.0), .warning)
        XCTAssertEqual(UsageFormatting.level(for: 89.99), .warning)
        XCTAssertEqual(UsageFormatting.level(for: 90.0), .critical)
        XCTAssertEqual(UsageFormatting.level(for: 100.0), .critical)
    }

    func testFormatCountdownNullReturnsEmpty() {
        XCTAssertEqual(UsageFormatting.formatCountdown(nil, now: Date()), "")
    }

    func testFormatCountdownNegativeReturnsNow() {
        let now = Date()
        XCTAssertEqual(
            UsageFormatting.formatCountdown(now.addingTimeInterval(-5 * 60), now: now),
            "now"
        )
    }

    func testFormatCountdownThirtySecondsReturnsLessThanMinute() {
        let now = Date()
        XCTAssertEqual(
            UsageFormatting.formatCountdown(now.addingTimeInterval(30), now: now),
            "<1m"
        )
    }

    func testFormatCountdownFiftyNineMinFiftyNineSecReturns59m() {
        let now = Date()
        let resets = now.addingTimeInterval(59 * 60 + 59)
        XCTAssertEqual(UsageFormatting.formatCountdown(resets, now: now), "59m")
    }

    func testFormatCountdownExactlyOneHourReturns1h0m() {
        let now = Date()
        XCTAssertEqual(
            UsageFormatting.formatCountdown(now.addingTimeInterval(3600), now: now),
            "1h 0m"
        )
    }

    func testFormatCountdownTwoHoursThirteenMinReturns2h13m() {
        let now = Date()
        let resets = now.addingTimeInterval(2 * 3600 + 13 * 60)
        XCTAssertEqual(UsageFormatting.formatCountdown(resets, now: now), "2h 13m")
    }

    func testFormatCountdownSeventyOneHoursFiveMinReturns71h5m() {
        let now = Date()
        let resets = now.addingTimeInterval(71 * 3600 + 5 * 60)
        XCTAssertEqual(UsageFormatting.formatCountdown(resets, now: now), "71h 5m")
    }
}
