import Foundation

/// Ring-buffer burn-rate estimator. Capacity 10; a sample that drops more than
/// 5 percentage points below the previous one is treated as a window reset and
/// clears the history (the usage window rolled over, so prior slope is moot).
public final class BurnRateEstimator {
    private static let capacity = 10
    private static let dropThreshold = 5.0
    private static let minSpanMinutes = 3.0
    private static let minRate = 0.05

    private var buffer: [(at: Date, utilization: Double)] = []
    private var count = 0
    private var head = 0

    public init() {
        buffer = Array(repeating: (Date(timeIntervalSince1970: 0), 0.0), count: Self.capacity)
    }

    public func add(at: Date, utilization: Double) {
        if count > 0 {
            let lastIndex = (head + count - 1) % Self.capacity
            let lastUtil = buffer[lastIndex].utilization
            if utilization < lastUtil - Self.dropThreshold {
                // Window reset detected: discard history and restart.
                count = 0
                head = 0
            }
        }

        if count < Self.capacity {
            let writeIndex = (head + count) % Self.capacity
            buffer[writeIndex] = (at, utilization)
            count += 1
        } else {
            buffer[head] = (at, utilization)
            head = (head + 1) % Self.capacity
        }
    }

    /// Returns time remaining until the window hits 100%, or nil when the slope
    /// is too shallow / sparse to be meaningful. Clamped at zero.
    public func projectTimeToCap(now: Date) -> TimeInterval? {
        if count < 2 {
            return nil
        }

        let first = buffer[head]
        let last = buffer[(head + count - 1) % Self.capacity]

        let spanMinutes = last.at.timeIntervalSince(first.at) / 60.0
        if spanMinutes < Self.minSpanMinutes {
            return nil
        }

        let rate = (last.utilization - first.utilization) / spanMinutes
        if rate <= Self.minRate {
            return nil
        }

        let minutesToCap = (100 - last.utilization) / rate
        let capInstant = last.at.addingTimeInterval(minutesToCap * 60.0)
        let remaining = capInstant.timeIntervalSince(now)
        return remaining < 0 ? 0 : remaining
    }
}
