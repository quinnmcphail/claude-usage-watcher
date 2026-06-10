using ClaudeUsageWatcher.Core;
using Xunit;

namespace ClaudeUsageWatcher.Core.Tests;

public class UsageFormattingTests
{
    [Theory]
    [InlineData(0.0, UsageLevel.Normal)]
    [InlineData(69.99, UsageLevel.Normal)]
    [InlineData(70.0, UsageLevel.Warning)]
    [InlineData(89.99, UsageLevel.Warning)]
    [InlineData(90.0, UsageLevel.Critical)]
    [InlineData(100.0, UsageLevel.Critical)]
    public void GetLevel_ReturnsExpected(double utilization, UsageLevel expected)
    {
        Assert.Equal(expected, UsageFormatting.GetLevel(utilization));
    }

    [Fact]
    public void FormatCountdown_Null_ReturnsEmpty()
    {
        Assert.Equal("", UsageFormatting.FormatCountdown(null, DateTimeOffset.UtcNow));
    }

    [Fact]
    public void FormatCountdown_Negative_ReturnsNow()
    {
        var now = DateTimeOffset.UtcNow;
        Assert.Equal("now", UsageFormatting.FormatCountdown(now.AddMinutes(-5), now));
    }

    [Fact]
    public void FormatCountdown_ThirtySeconds_ReturnsLessThanMinute()
    {
        var now = DateTimeOffset.UtcNow;
        Assert.Equal("<1m", UsageFormatting.FormatCountdown(now.AddSeconds(30), now));
    }

    [Fact]
    public void FormatCountdown_FiftyNineMinFiftyNineSec_Returns59m()
    {
        var now = DateTimeOffset.UtcNow;
        var resets = now.AddMinutes(59).AddSeconds(59);
        Assert.Equal("59m", UsageFormatting.FormatCountdown(resets, now));
    }

    [Fact]
    public void FormatCountdown_ExactlyOneHour_Returns1h0m()
    {
        var now = DateTimeOffset.UtcNow;
        Assert.Equal("1h 0m", UsageFormatting.FormatCountdown(now.AddHours(1), now));
    }

    [Fact]
    public void FormatCountdown_TwoHoursThirteenMin_Returns2h13m()
    {
        var now = DateTimeOffset.UtcNow;
        var resets = now.AddHours(2).AddMinutes(13);
        Assert.Equal("2h 13m", UsageFormatting.FormatCountdown(resets, now));
    }

    [Fact]
    public void FormatCountdown_SeventyOneHoursFiveMin_Returns71h5m()
    {
        var now = DateTimeOffset.UtcNow;
        var resets = now.AddHours(71).AddMinutes(5);
        Assert.Equal("71h 5m", UsageFormatting.FormatCountdown(resets, now));
    }
}
