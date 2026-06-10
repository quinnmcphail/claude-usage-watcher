using System.Globalization;

namespace ClaudeUsageWatcher.Core;

public static class UsageFormatting
{
    public static UsageLevel GetLevel(double utilization)
    {
        if (utilization >= 90)
        {
            return UsageLevel.Critical;
        }

        if (utilization >= 70)
        {
            return UsageLevel.Warning;
        }

        return UsageLevel.Normal;
    }

    public static string FormatCountdown(DateTimeOffset? resetsAt, DateTimeOffset now)
    {
        if (resetsAt is null)
        {
            return "";
        }

        TimeSpan delta = resetsAt.Value - now;

        if (delta <= TimeSpan.Zero)
        {
            return "now";
        }

        if (delta >= TimeSpan.FromHours(1))
        {
            int totalHours = (int)Math.Floor(delta.TotalHours);
            int minutes = delta.Minutes;
            return string.Create(CultureInfo.InvariantCulture, $"{totalHours}h {minutes}m");
        }

        if (delta >= TimeSpan.FromMinutes(1))
        {
            int minutes = (int)Math.Floor(delta.TotalMinutes);
            return string.Create(CultureInfo.InvariantCulture, $"{minutes}m");
        }

        return "<1m";
    }
}
