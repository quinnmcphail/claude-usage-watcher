using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClaudeUsageWatcher.Core;

public sealed class UsageClient
{
    public const string Endpoint = "https://api.anthropic.com/api/oauth/usage";
    public const string UserAgent = "claude-code/2.1.170";
    public const string AnthropicBeta = "oauth-2025-04-20";

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private readonly HttpClient _httpClient;

    public UsageClient(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public async Task<UsageSnapshot> FetchAsync(string accessToken, CancellationToken ct = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.TryAddWithoutValidation("anthropic-beta", AnthropicBeta);
        request.Headers.TryAddWithoutValidation("User-Agent", UserAgent);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        using HttpResponseMessage response = await _httpClient
            .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct)
            .ConfigureAwait(false);

        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
        {
            throw new UsageAuthException($"Authentication failed ({(int)response.StatusCode}).");
        }

        if (response.StatusCode == HttpStatusCode.TooManyRequests)
        {
            throw new UsageRateLimitException("Rate limited (429).");
        }

        response.EnsureSuccessStatusCode();

        await using Stream stream = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        UsageDto? dto = await JsonSerializer
            .DeserializeAsync<UsageDto>(stream, SerializerOptions, ct)
            .ConfigureAwait(false);

        return Map(dto);
    }

    private static UsageSnapshot Map(UsageDto? dto)
    {
        return new UsageSnapshot(
            MapWindow(dto?.FiveHour),
            MapWindow(dto?.SevenDay),
            MapWindow(dto?.SevenDayOpus),
            MapWindow(dto?.SevenDaySonnet),
            DateTimeOffset.UtcNow);
    }

    private static UsageWindow? MapWindow(WindowDto? dto)
    {
        if (dto is null)
        {
            return null;
        }

        return new UsageWindow(dto.Utilization, dto.ResetsAt);
    }

    private sealed class UsageDto
    {
        [JsonPropertyName("five_hour")]
        public WindowDto? FiveHour { get; set; }

        [JsonPropertyName("seven_day")]
        public WindowDto? SevenDay { get; set; }

        [JsonPropertyName("seven_day_opus")]
        public WindowDto? SevenDayOpus { get; set; }

        [JsonPropertyName("seven_day_sonnet")]
        public WindowDto? SevenDaySonnet { get; set; }
    }

    private sealed class WindowDto
    {
        [JsonPropertyName("utilization")]
        public double Utilization { get; set; }

        [JsonPropertyName("resets_at")]
        public DateTimeOffset? ResetsAt { get; set; }
    }
}
