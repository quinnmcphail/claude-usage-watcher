using System.Net;
using System.Text;
using ClaudeUsageWatcher.Core;
using Xunit;

namespace ClaudeUsageWatcher.Core.Tests;

public class UsageClientTests
{
    private const string SampleJson =
        "{\"five_hour\":{\"utilization\":52.0,\"resets_at\":\"2026-06-10T16:40:00.627509+00:00\"}," +
        "\"seven_day\":{\"utilization\":27.0,\"resets_at\":\"2026-06-13T11:00:00.627529+00:00\"}," +
        "\"seven_day_oauth_apps\":null,\"seven_day_opus\":null," +
        "\"seven_day_sonnet\":{\"utilization\":0.0,\"resets_at\":null}," +
        "\"seven_day_cowork\":null,\"seven_day_omelette\":null,\"tangelo\":null," +
        "\"iguana_necktie\":null,\"omelette_promotional\":null,\"cinder_cove\":null," +
        "\"extra_usage\":{\"is_enabled\":false,\"monthly_limit\":null,\"used_credits\":null," +
        "\"utilization\":null,\"currency\":null,\"disabled_reason\":null}}";

    private sealed class FakeHandler : HttpMessageHandler
    {
        private readonly HttpStatusCode _status;
        private readonly string _body;

        public HttpRequestMessage? CapturedRequest { get; private set; }

        public FakeHandler(HttpStatusCode status, string body)
        {
            _status = status;
            _body = body;
        }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CapturedRequest = request;
            var response = new HttpResponseMessage(_status)
            {
                Content = new StringContent(_body, Encoding.UTF8, "application/json")
            };
            return Task.FromResult(response);
        }
    }

    [Fact]
    public async Task FetchAsync_ParsesSampleJson()
    {
        var handler = new FakeHandler(HttpStatusCode.OK, SampleJson);
        using var http = new HttpClient(handler);
        var client = new UsageClient(http);

        UsageSnapshot snapshot = await client.FetchAsync("tok");

        Assert.NotNull(snapshot.FiveHour);
        Assert.Equal(52.0, snapshot.FiveHour!.Utilization);
        Assert.Equal(
            DateTimeOffset.Parse("2026-06-10T16:40:00.627509+00:00"),
            snapshot.FiveHour.ResetsAt);

        Assert.NotNull(snapshot.SevenDay);
        Assert.Equal(27.0, snapshot.SevenDay!.Utilization);

        Assert.Null(snapshot.SevenDayOpus);

        Assert.NotNull(snapshot.SevenDaySonnet);
        Assert.Equal(0.0, snapshot.SevenDaySonnet!.Utilization);
        Assert.Null(snapshot.SevenDaySonnet.ResetsAt);
    }

    [Fact]
    public async Task FetchAsync_SendsRequiredHeaders()
    {
        var handler = new FakeHandler(HttpStatusCode.OK, SampleJson);
        using var http = new HttpClient(handler);
        var client = new UsageClient(http);

        await client.FetchAsync("tok");

        HttpRequestMessage req = Assert.IsType<HttpRequestMessage>(handler.CapturedRequest);
        Assert.Equal("Bearer", req.Headers.Authorization!.Scheme);
        Assert.Equal("tok", req.Headers.Authorization.Parameter);

        Assert.True(req.Headers.TryGetValues("anthropic-beta", out var beta));
        Assert.Equal("oauth-2025-04-20", Assert.Single(beta!));

        Assert.True(req.Headers.TryGetValues("User-Agent", out var ua));
        Assert.Contains(ua!, v => v.Contains("claude-code"));
    }

    [Fact]
    public async Task FetchAsync_401_ThrowsAuthException()
    {
        var handler = new FakeHandler(HttpStatusCode.Unauthorized, "{}");
        using var http = new HttpClient(handler);
        var client = new UsageClient(http);

        await Assert.ThrowsAsync<UsageAuthException>(() => client.FetchAsync("tok"));
    }

    [Fact]
    public async Task FetchAsync_429_ThrowsRateLimitException()
    {
        var handler = new FakeHandler(HttpStatusCode.TooManyRequests, "{}");
        using var http = new HttpClient(handler);
        var client = new UsageClient(http);

        await Assert.ThrowsAsync<UsageRateLimitException>(() => client.FetchAsync("tok"));
    }

    [Fact]
    public async Task FetchAsync_NullWindow_ProducesAllNullSnapshot()
    {
        var handler = new FakeHandler(HttpStatusCode.OK, "{\"five_hour\":null}");
        using var http = new HttpClient(handler);
        var client = new UsageClient(http);

        UsageSnapshot snapshot = await client.FetchAsync("tok");

        Assert.Null(snapshot.FiveHour);
        Assert.Null(snapshot.SevenDay);
        Assert.Null(snapshot.SevenDayOpus);
        Assert.Null(snapshot.SevenDaySonnet);
    }
}
