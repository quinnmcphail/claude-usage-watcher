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

public sealed record FetchResult(FetchOutcome Outcome, UsageSnapshot? Snapshot, string? Message)
{
    public static FetchResult Success(UsageSnapshot snapshot) =>
        new(FetchOutcome.Success, snapshot, null);

    public static FetchResult NoCredentials() =>
        new(FetchOutcome.NoCredentials, null, null);

    public static FetchResult AuthFailed() =>
        new(FetchOutcome.AuthFailed, null, null);

    public static FetchResult RateLimited() =>
        new(FetchOutcome.RateLimited, null, null);

    public static FetchResult Error(string message) =>
        new(FetchOutcome.Error, null, message);
}

public sealed class UsageService : IDisposable
{
    private readonly HttpClient _httpClient;
    private readonly UsageClient _usageClient;
    private readonly CredentialsReader _credentialsReader;

    public UsageSnapshot? LastGood { get; private set; }
    public bool IsStale { get; private set; }
    public bool HasCredentials { get; private set; } = true;

    public UsageService()
    {
        _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(30)
        };
        _usageClient = new UsageClient(_httpClient);
        _credentialsReader = new CredentialsReader();
    }

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
            return FetchResult.Success(snapshot);
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
