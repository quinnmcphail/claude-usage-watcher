namespace ClaudeUsageWatcher.Core;

public sealed class BurnRateEstimator
{
    private const int Capacity = 10;
    private const double DropThreshold = 5.0;
    private const double MinSpanMinutes = 3.0;
    private const double MinRate = 0.05;

    private readonly (DateTimeOffset At, double Utilization)[] _buffer =
        new (DateTimeOffset, double)[Capacity];
    private int _count;
    private int _head; // index of the oldest sample

    public void Add(DateTimeOffset at, double utilization)
    {
        if (_count > 0)
        {
            int lastIndex = (_head + _count - 1) % Capacity;
            double lastUtil = _buffer[lastIndex].Utilization;
            if (utilization < lastUtil - DropThreshold)
            {
                // Window reset detected: discard history and restart.
                _count = 0;
                _head = 0;
            }
        }

        if (_count < Capacity)
        {
            int writeIndex = (_head + _count) % Capacity;
            _buffer[writeIndex] = (at, utilization);
            _count++;
        }
        else
        {
            _buffer[_head] = (at, utilization);
            _head = (_head + 1) % Capacity;
        }
    }

    public TimeSpan? ProjectTimeToCap(DateTimeOffset now)
    {
        if (_count < 2)
        {
            return null;
        }

        (DateTimeOffset At, double Utilization) first = _buffer[_head];
        (DateTimeOffset At, double Utilization) last = _buffer[(_head + _count - 1) % Capacity];

        double spanMinutes = (last.At - first.At).TotalMinutes;
        if (spanMinutes < MinSpanMinutes)
        {
            return null;
        }

        double rate = (last.Utilization - first.Utilization) / spanMinutes;
        if (rate <= MinRate)
        {
            return null;
        }

        double minutesToCap = (100 - last.Utilization) / rate;
        DateTimeOffset capInstant = last.At.AddMinutes(minutesToCap);
        TimeSpan remaining = capInstant - now;
        return remaining < TimeSpan.Zero ? TimeSpan.Zero : remaining;
    }
}
