using System.Net.Http;
using ClaudeUsageWatcher.Core;

namespace ClaudeUsageWatcher;

public enum FetchOutcome
{
    Success,
    NoCredentials,
    AuthFailed,
    RateLimited,
    Error
}

public sealed record FetchResult(
    FetchOutcome Outcome,
    UsageSnapshot? Snapshot,
    string? Message,
    ThresholdEvent? Notification)
{
    public static FetchResult Success(UsageSnapshot snapshot, ThresholdEvent? notification = null) =>
        new(FetchOutcome.Success, snapshot, null, notification);

    public static FetchResult NoCredentials() =>
        new(FetchOutcome.NoCredentials, null, null, null);

    public static FetchResult AuthFailed() =>
        new(FetchOutcome.AuthFailed, null, null, null);

    public static FetchResult RateLimited() =>
        new(FetchOutcome.RateLimited, null, null, null);

    public static FetchResult Error(string message) =>
        new(FetchOutcome.Error, null, message, null);
}

public sealed class UsageService : IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly UsageClient _usageClient;
    private readonly CredentialsReader _credentialsReader;
    private readonly ThresholdTracker _thresholdTracker;
    private readonly BurnRateEstimator _burnRate = new();

    public UsageSnapshot? LastGood { get; private set; }
    public bool IsStale { get; private set; }
    public bool HasCredentials { get; private set; } = true;

    public UsageService(double notifyWarnAt = 80, double notifyCriticalAt = 95)
    {
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(30)
        };
        _usageClient = new UsageClient(_httpClient);
        _credentialsReader = new CredentialsReader();
        _thresholdTracker = new ThresholdTracker(notifyWarnAt, notifyCriticalAt);
    }

    public TimeSpan? ProjectTimeToCap(DateTimeOffset now) => _burnRate.ProjectTimeToCap(now);

    public async Task<FetchResult> PollAsync(CancellationToken ct = default)
    {
        ClaudeCredentials? creds = _credentialsReader.TryRead();
        if (creds is null || string.IsNullOrEmpty(creds.AccessToken))
        {
            HasCredentials = false;
            IsStale = LastGood is not null;
            return FetchResult.NoCredentials();
        }

        HasCredentials = true;

        try
        {
            UsageSnapshot snapshot = await _usageClient
                .FetchAsync(creds.AccessToken, ct)
                .ConfigureAwait(false);

            LastGood = snapshot;
            IsStale = false;

            ThresholdEvent? notification = null;
            if (snapshot.FiveHour is UsageWindow five)
            {
                notification = _thresholdTracker.Observe(five.Utilization);
                _burnRate.Add(snapshot.FetchedAt, five.Utilization);
            }

            return FetchResult.Success(snapshot, notification);
        }
        catch (UsageAuthException)
        {
            IsStale = LastGood is not null;
            return FetchResult.AuthFailed();
        }
        catch (UsageRateLimitException)
        {
            IsStale = LastGood is not null;
            return FetchResult.RateLimited();
        }
        catch (OperationCanceledException)
        {
            IsStale = LastGood is not null;
            return FetchResult.Error("cancelled");
        }
        catch (Exception ex)
        {
            IsStale = LastGood is not null;
            return FetchResult.Error(ex.Message);
        }
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }
}
