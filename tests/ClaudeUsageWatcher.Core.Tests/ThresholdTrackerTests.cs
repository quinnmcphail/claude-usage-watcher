using ClaudeUsageWatcher.Core;
using Xunit;

namespace ClaudeUsageWatcher.Core.Tests;

public class ThresholdTrackerTests
{
    [Fact]
    public void FirstObservation_NeverEmits_AndStayingAbove_DoesNotFire()
    {
        var tracker = new ThresholdTracker();
        Assert.Null(tracker.Observe(96)); // first arms only
        Assert.Null(tracker.Observe(97)); // already above critical, no re-fire
    }

    [Fact]
    public void CrossingWarn_FiresWarning_Once()
    {
        var tracker = new ThresholdTracker();
        Assert.Null(tracker.Observe(60));
        Assert.Equal(ThresholdEvent.Warning, tracker.Observe(85));
        Assert.Null(tracker.Observe(86)); // no re-fire while staying above
    }

    [Fact]
    public void CrossingDirectlyToCritical_FiresCriticalOnly()
    {
        var tracker = new ThresholdTracker();
        Assert.Null(tracker.Observe(60));
        Assert.Equal(ThresholdEvent.Critical, tracker.Observe(97));
    }

    [Fact]
    public void AboveWarnCrossingCritical_FiresCritical()
    {
        var tracker = new ThresholdTracker();
        Assert.Null(tracker.Observe(85));
        Assert.Equal(ThresholdEvent.Critical, tracker.Observe(96));
    }

    [Fact]
    public void Reset_ThenReArm_FiresWarningAgain()
    {
        var tracker = new ThresholdTracker();
        Assert.Null(tracker.Observe(90));
        Assert.Equal(ThresholdEvent.Reset, tracker.Observe(5));
        Assert.Equal(ThresholdEvent.Warning, tracker.Observe(85));
    }

    [Fact]
    public void Drop_FromBelowFifty_IsNotAReset()
    {
        var tracker = new ThresholdTracker();
        Assert.Null(tracker.Observe(30));
        Assert.Null(tracker.Observe(8)); // prev < 50, not a reset
    }
}
