using System.Text.Json;

namespace ClaudeUsageWatcher.Core;

public sealed class CredentialsReader
{
    private readonly string _path;

    public CredentialsReader(string? path = null)
    {
        _path = path ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".claude",
            ".credentials.json");
    }

    public ClaudeCredentials? TryRead()
    {
        try
        {
            if (!File.Exists(_path))
            {
                return null;
            }

            string json = File.ReadAllText(_path);
            using JsonDocument doc = JsonDocument.Parse(json);

            if (!doc.RootElement.TryGetProperty("claudeAiOauth", out JsonElement oauth) ||
                oauth.ValueKind != JsonValueKind.Object)
            {
                return null;
            }

            if (!oauth.TryGetProperty("accessToken", out JsonElement tokenElement) ||
                tokenElement.ValueKind != JsonValueKind.String)
            {
                return null;
            }

            string? token = tokenElement.GetString();
            if (string.IsNullOrEmpty(token))
            {
                return null;
            }

            DateTimeOffset expiresAt = DateTimeOffset.MinValue;
            if (oauth.TryGetProperty("expiresAt", out JsonElement expElement) &&
                expElement.ValueKind == JsonValueKind.Number &&
                expElement.TryGetInt64(out long ms))
            {
                expiresAt = DateTimeOffset.FromUnixTimeMilliseconds(ms);
            }

            return new ClaudeCredentials(token, expiresAt);
        }
        catch (Exception)
        {
            return null;
        }
    }
}
