import XCTest
@testable import UsageCore

final class BurnRateEstimatorTests: XCTestCase {
    // 2026-01-01T12:00:00Z
    private let t0 = Date(timeIntervalSince1970: 1_767_268_800)

    private func minutes(_ m: Double) -> TimeInterval { m * 60.0 }

    func testFewerThanTwoSamplesReturnsNull() {
        let est = BurnRateEstimator()
        XCTAssertNil(est.projectTimeToCap(now: t0))

        est.add(at: t0, utilization: 50)
        XCTAssertNil(est.projectTimeToCap(now: t0))
    }

    func testSpanBelowThreeMinutesReturnsNull() {
        let est = BurnRateEstimator()
        est.add(at: t0, utilization: 50)
        est.add(at: t0.addingTimeInterval(minutes(1)), utilization: 52)
        XCTAssertNil(est.projectTimeToCap(now: t0.addingTimeInterval(minutes(1))))
    }

    func testSteadyClimbProjectsTimeToCap() {
        let est = BurnRateEstimator()
        let last = t0.addingTimeInterval(minutes(10))
        est.add(at: t0, utilization: 50)
        est.add(at: last, utilization: 52) // 0.2 %/min -> (100-52)/0.2 = 240 min

        let projection = est.projectTimeToCap(now: last)
        XCTAssertNotNil(projection)
        XCTAssertEqual(projection! / 60.0, 240.0, accuracy: 0.01)
    }

    func testFlatUsageReturnsNull() {
        let est = BurnRateEstimator()
        est.add(at: t0, utilization: 50)
        est.add(at: t0.addingTimeInterval(minutes(10)), utilization: 50)
        XCTAssertNil(est.projectTimeToCap(now: t0.addingTimeInterval(minutes(10))))
    }

    func testDropMoreThanFivePointsClearsBuffer() {
        let est = BurnRateEstimator()
        est.add(at: t0, utilization: 50)
        est.add(at: t0.addingTimeInterval(minutes(5)), utilization: 10) // drop > 5 clears
        XCTAssertNil(est.projectTimeToCap(now: t0.addingTimeInterval(minutes(5))))
    }

    func testProjectionPastCapClampsToZero() {
        let est = BurnRateEstimator()
        let last = t0.addingTimeInterval(minutes(10))
        est.add(at: t0, utilization: 50)
        est.add(at: last, utilization: 52)

        let projection = est.projectTimeToCap(now: last.addingTimeInterval(100 * 3600))
        XCTAssertNotNil(projection)
        XCTAssertEqual(projection!, 0)
    }

    func testRingBufferTwelveIncreasingSamplesStillComputes() {
        let est = BurnRateEstimator()
        for i in 0..<12 {
            est.add(at: t0.addingTimeInterval(minutes(Double(i) * 5)), utilization: Double(30 + i))
        }

        let projection = est.projectTimeToCap(now: t0.addingTimeInterval(minutes(11 * 5)))
        XCTAssertNotNil(projection)
        XCTAssertGreaterThan(projection!, 0)
    }
}
