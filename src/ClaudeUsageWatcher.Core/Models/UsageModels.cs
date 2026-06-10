namespace ClaudeUsageWatcher.Core;

public sealed record UsageWindow(double Utilization, DateTimeOffset? ResetsAt);

public sealed record UsageSnapshot(
    UsageWindow? FiveHour,
    UsageWindow? SevenDay,
    UsageWindow? SevenDayOpus,
    UsageWindow? SevenDaySonnet,
    DateTimeOffset FetchedAt);

public sealed record ClaudeCredentials(string AccessToken, DateTimeOffset ExpiresAt);

public enum UsageLevel
{
    Normal,
    Warning,
    Critical
}
