using ClaudeUsageWatcher.Core;
using Xunit;

namespace ClaudeUsageWatcher.Core.Tests;

public class BurnRateEstimatorTests
{
    private static readonly DateTimeOffset T0 =
        new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void FewerThanTwoSamples_ReturnsNull()
    {
        var est = new BurnRateEstimator();
        Assert.Null(est.ProjectTimeToCap(T0));

        est.Add(T0, 50);
        Assert.Null(est.ProjectTimeToCap(T0));
    }

    [Fact]
    public void SpanBelowThreeMinutes_ReturnsNull()
    {
        var est = new BurnRateEstimator();
        est.Add(T0, 50);
        est.Add(T0.AddMinutes(1), 52);
        Assert.Null(est.ProjectTimeToCap(T0.AddMinutes(1)));
    }

    [Fact]
    public void SteadyClimb_ProjectsTimeToCap()
    {
        var est = new BurnRateEstimator();
        var last = T0.AddMinutes(10);
        est.Add(T0, 50);
        est.Add(last, 52); // 0.2 %/min -> (100-52)/0.2 = 240 min from last sample

        TimeSpan? projection = est.ProjectTimeToCap(last);
        Assert.NotNull(projection);
        Assert.Equal(240.0, projection!.Value.TotalMinutes, 2);
    }

    [Fact]
    public void FlatUsage_ReturnsNull()
    {
        var est = new BurnRateEstimator();
        est.Add(T0, 50);
        est.Add(T0.AddMinutes(10), 50);
        Assert.Null(est.ProjectTimeToCap(T0.AddMinutes(10)));
    }

    [Fact]
    public void DropMoreThanFivePoints_ClearsBuffer()
    {
        var est = new BurnRateEstimator();
        est.Add(T0, 50);
        est.Add(T0.AddMinutes(5), 10); // drop > 5 points clears, buffer restarts with 1 sample
        Assert.Null(est.ProjectTimeToCap(T0.AddMinutes(5)));
    }

    [Fact]
    public void ProjectionPastCap_ClampsToZero()
    {
        var est = new BurnRateEstimator();
        var last = T0.AddMinutes(10);
        est.Add(T0, 50);
        est.Add(last, 52); // caps ~240 min after last

        TimeSpan? projection = est.ProjectTimeToCap(last.AddHours(100));
        Assert.NotNull(projection);
        Assert.Equal(TimeSpan.Zero, projection!.Value);
    }

    [Fact]
    public void RingBuffer_TwelveIncreasingSamples_StillComputes()
    {
        var est = new BurnRateEstimator();
        for (int i = 0; i < 12; i++)
        {
            est.Add(T0.AddMinutes(i * 5), 30 + i); // 0.2 %/min over each step
        }

        TimeSpan? projection = est.ProjectTimeToCap(T0.AddMinutes(11 * 5));
        Assert.NotNull(projection);
        Assert.True(projection!.Value > TimeSpan.Zero);
    }
}
