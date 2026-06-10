using System.Text.Json;

namespace ClaudeUsageWatcher.Core;

public sealed class CredentialsReader
{
    private readonly string _path;
    private readonly Func<string, string?> _getEnv;

    /// <param name="path">Explicit credentials file path; overrides CLAUDE_CONFIG_DIR resolution.</param>
    /// <param name="getEnvironmentVariable">Environment lookup, injectable for tests.</param>
    public CredentialsReader(string? path = null, Func<string, string?>? getEnvironmentVariable = null)
    {
        _getEnv = getEnvironmentVariable ?? Environment.GetEnvironmentVariable;
        _path = path ?? DefaultPath(_getEnv);
    }

    private static string DefaultPath(Func<string, string?> getEnv)
    {
        // Claude Code honors CLAUDE_CONFIG_DIR as the home of its .credentials.json;
        // fall back to the standard ~/.claude location.
        string? configDir = getEnv("CLAUDE_CONFIG_DIR");
        string dir = !string.IsNullOrWhiteSpace(configDir)
            ? configDir
            : Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".claude");
        return Path.Combine(dir, ".credentials.json");
    }

    public ClaudeCredentials? TryRead()
    {
        // An explicit token in the environment wins over any file (CI / non-standard setups).
        // No expiry is knowable for it; the 401 path handles a dead token.
        string? envToken = _getEnv("CLAUDE_CODE_OAUTH_TOKEN");
        if (!string.IsNullOrWhiteSpace(envToken))
        {
            return new ClaudeCredentials(envToken.Trim(), DateTimeOffset.MaxValue);
        }

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
