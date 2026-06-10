import XCTest
@testable import UsageCore

final class ThresholdTrackerTests: XCTestCase {
    func testFirstObservationNeverEmitsAndStayingAboveDoesNotFire() {
        let tracker = ThresholdTracker()
        XCTAssertNil(tracker.observe(96)) // first arms only
        XCTAssertNil(tracker.observe(97)) // already above critical, no re-fire
    }

    func testCrossingWarnFiresWarningOnce() {
        let tracker = ThresholdTracker()
        XCTAssertNil(tracker.observe(60))
        XCTAssertEqual(tracker.observe(85), .warning)
        XCTAssertNil(tracker.observe(86)) // no re-fire while staying above
    }

    func testCrossingDirectlyToCriticalFiresCriticalOnly() {
        let tracker = ThresholdTracker()
        XCTAssertNil(tracker.observe(60))
        XCTAssertEqual(tracker.observe(97), .critical)
    }

    func testAboveWarnCrossingCriticalFiresCritical() {
        let tracker = ThresholdTracker()
        XCTAssertNil(tracker.observe(85))
        XCTAssertEqual(tracker.observe(96), .critical)
    }

    func testResetThenReArmFiresWarningAgain() {
        let tracker = ThresholdTracker()
        XCTAssertNil(tracker.observe(90))
        XCTAssertEqual(tracker.observe(5), .reset)
        XCTAssertEqual(tracker.observe(85), .warning)
    }

    func testDropFromBelowFiftyIsNotAReset() {
        let tracker = ThresholdTracker()
        XCTAssertNil(tracker.observe(30))
        XCTAssertNil(tracker.observe(8)) // prev < 50, not a reset
    }
}
