import Foundation

public enum UsageFormatting {
    public static func level(for utilization: Double) -> UsageLevel {
        if utilization >= 90 {
            return .critical
        }
        if utilization >= 70 {
            return .warning
        }
        return .normal
    }

    /// Mirrors the C# FormatCountdown: invariant "Xh Ym" / "Xm" / "<1m" / "now" / "".
    public static func formatCountdown(_ resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else {
            return ""
        }

        let delta = resetsAt.timeIntervalSince(now)

        if delta <= 0 {
            return "now"
        }

        if delta >= 3600 {
            let totalHours = Int(floor(delta / 3600))
            // Minutes component of the remainder, matching TimeSpan.Minutes (0...59).
            let minutes = Int(floor(delta.truncatingRemainder(dividingBy: 3600) / 60))
            return "\(totalHours)h \(minutes)m"
        }

        if delta >= 60 {
            let minutes = Int(floor(delta / 60))
            return "\(minutes)m"
        }

        return "<1m"
    }
}
