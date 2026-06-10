namespace ClaudeUsageWatcher.Core;

public enum ThresholdEvent
{
    Warning,
    Critical,
    Reset
}

public sealed class ThresholdTracker
{
    private readonly double _warnAt;
    private readonly double _criticalAt;
    private double? _prev;

    public ThresholdTracker(double warnAt = 80, double criticalAt = 95)
    {
        _warnAt = warnAt;
        _criticalAt = criticalAt;
    }

    public ThresholdEvent? Observe(double utilization)
    {
        if (_prev is not double prev)
        {
            // First observation only arms the tracker.
            _prev = utilization;
            return null;
        }

        _prev = utilization;

        if (prev < _criticalAt && utilization >= _criticalAt)
        {
            return ThresholdEvent.Critical;
        }

        if (prev < _warnAt && utilization >= _warnAt)
        {
            return ThresholdEvent.Warning;
        }

        if (prev >= 50 && utilization <= 10)
        {
            return ThresholdEvent.Reset;
        }

        return null;
    }
}
