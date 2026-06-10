import Foundation

public enum FetchOutcome: Sendable {
    case success
    case noCredentials
    case authFailed
    case rateLimited
    case error(String)
}

public struct FetchResult: Sendable {
    public let outcome: FetchOutcome
    public let snapshot: UsageSnapshot?
    public let notification: ThresholdEvent?

    public init(outcome: FetchOutcome, snapshot: UsageSnapshot?, notification: ThresholdEvent?) {
        self.outcome = outcome
        self.snapshot = snapshot
        self.notification = notification
    }
}

/// Poll orchestration mirroring the C# UsageService: reads credentials, fetches a
/// snapshot, maps errors to outcomes, and maintains last-good / staleness state.
public final class UsageService {
    private let usageClient: UsageClient
    private let credentialsReader: CredentialsReader
    private let thresholdTracker: ThresholdTracker
    private let burnRate = BurnRateEstimator()

    public private(set) var lastGood: UsageSnapshot?
    public private(set) var isStale = false
    public private(set) var hasCredentials = true

    public init(
        notifyWarnAt: Double = 80,
        notifyCriticalAt: Double = 95,
        usageClient: UsageClient? = nil,
        credentialsReader: CredentialsReader? = nil
    ) {
        self.usageClient = usageClient ?? UsageClient(transport: URLSessionTransport())
        self.credentialsReader = credentialsReader ?? CredentialsReader()
        self.thresholdTracker = ThresholdTracker(warnAt: notifyWarnAt, criticalAt: notifyCriticalAt)
    }

    public func projectTimeToCap(now: Date) -> TimeInterval? {
        burnRate.projectTimeToCap(now: now)
    }

    public func poll() async -> FetchResult {
        guard let creds = credentialsReader.tryRead(), !creds.accessToken.isEmpty else {
            hasCredentials = false
            isStale = lastGood != nil
            return FetchResult(outcome: .noCredentials, snapshot: nil, notification: nil)
        }

        hasCredentials = true

        do {
            let snapshot = try await usageClient.fetch(accessToken: creds.accessToken)
            lastGood = snapshot
            isStale = false

            var notification: ThresholdEvent?
            if let five = snapshot.fiveHour {
                notification = thresholdTracker.observe(five.utilization)
                burnRate.add(at: snapshot.fetchedAt, utilization: five.utilization)
            }

            return FetchResult(outcome: .success, snapshot: snapshot, notification: notification)
        } catch UsageError.auth {
            isStale = lastGood != nil
            return FetchResult(outcome: .authFailed, snapshot: nil, notification: nil)
        } catch UsageError.rateLimited {
            isStale = lastGood != nil
            return FetchResult(outcome: .rateLimited, snapshot: nil, notification: nil)
        } catch {
            isStale = lastGood != nil
            return FetchResult(outcome: .error(error.localizedDescription), snapshot: nil, notification: nil)
        }
    }
}
