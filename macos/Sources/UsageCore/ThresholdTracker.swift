import Foundation

public enum ThresholdEvent: Sendable {
    case warning
    case critical
    case reset
}

public final class ThresholdTracker {
    private let warnAt: Double
    private let criticalAt: Double
    private var prev: Double?

    public init(warnAt: Double = 80, criticalAt: Double = 95) {
        self.warnAt = warnAt
        self.criticalAt = criticalAt
    }

    public func observe(_ utilization: Double) -> ThresholdEvent? {
        guard let prev else {
            // First observation only arms the tracker.
            self.prev = utilization
            return nil
        }

        self.prev = utilization

        if prev < criticalAt && utilization >= criticalAt {
            return .critical
        }

        if prev < warnAt && utilization >= warnAt {
            return .warning
        }

        if prev >= 50 && utilization <= 10 {
            return .reset
        }

        return nil
    }
}
