import AppKit
import UserNotifications
import UsageCore

/// Wraps UNUserNotificationCenter. Only operates when running from a real bundle;
/// calling UNUserNotificationCenter from a bare `swift run` executable crashes.
final class Notifier {
    private var authorized = false
    private var requested = false

    var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorizationIfNeeded() {
        guard isAvailable, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    /// Posts a threshold notification with Windows-identical text.
    func post(event: ThresholdEvent, snapshot: UsageSnapshot?, now: Date) {
        guard isAvailable, let five = snapshot?.fiveHour else { return }
        requestAuthorizationIfNeeded()

        let pct = Int(five.utilization.rounded())
        let title = "Claude usage"
        let body: String

        switch event {
        case .reset:
            body = "5-hour window reset \u{2014} usage at \(pct)%"
        case .warning, .critical:
            let cd = UsageFormatting.formatCountdown(five.resetsAt, now: now)
            body = cd.isEmpty
                ? "5-hour window at \(pct)%"
                : "5-hour window at \(pct)% \u{2014} resets in \(cd)"
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
