using ClaudeUsageWatcher.Core;
using Xunit;

namespace ClaudeUsageWatcher.Core.Tests;

public class CredentialsReaderTests
{
    // Hermetic env lookup so host machine variables can't affect tests.
    private static string? NoEnv(string _) => null;

    private static string WriteTemp(string content)
    {
        string path = Path.Combine(Path.GetTempPath(), $"cuw-test-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, content);
        return path;
    }

    [Fact]
    public void TryRead_ValidFile_ParsesTokenAndExpiry()
    {
        string path = WriteTemp(
            "{\"claudeAiOauth\":{\"accessToken\":\"sk-ant-oat01-abc\"," +
            "\"refreshToken\":\"r\",\"expiresAt\":1781120644269," +
            "\"scopes\":[\"a\"],\"subscriptionType\":\"max\"}}");
        try
        {
            var reader = new CredentialsReader(path, NoEnv);
            ClaudeCredentials? creds = reader.TryRead();

            Assert.NotNull(creds);
            Assert.Equal("sk-ant-oat01-abc", creds!.AccessToken);
            Assert.Equal(
                DateTimeOffset.FromUnixTimeMilliseconds(1781120644269),
                creds.ExpiresAt);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void TryRead_MissingFile_ReturnsNull()
    {
        string path = Path.Combine(Path.GetTempPath(), $"cuw-missing-{Guid.NewGuid():N}.json");
        var reader = new CredentialsReader(path, NoEnv);
        Assert.Null(reader.TryRead());
    }

    [Fact]
    public void TryRead_MalformedJson_ReturnsNull()
    {
        string path = WriteTemp("{ not valid json ");
        try
        {
            var reader = new CredentialsReader(path, NoEnv);
            Assert.Null(reader.TryRead());
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void TryRead_MissingAccessToken_ReturnsNull()
    {
        string path = WriteTemp("{\"claudeAiOauth\":{\"refreshToken\":\"r\",\"expiresAt\":123}}");
        try
        {
            var reader = new CredentialsReader(path, NoEnv);
            Assert.Null(reader.TryRead());
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void TryRead_EnvToken_WinsOverFile()
    {
        string path = WriteTemp(
            "{\"claudeAiOauth\":{\"accessToken\":\"file-token\",\"expiresAt\":123}}");
        try
        {
            var reader = new CredentialsReader(
                path,
                name => name == "CLAUDE_CODE_OAUTH_TOKEN" ? " env-token " : null);
            ClaudeCredentials? creds = reader.TryRead();

            Assert.NotNull(creds);
            Assert.Equal("env-token", creds!.AccessToken); // trimmed
            Assert.Equal(DateTimeOffset.MaxValue, creds.ExpiresAt);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void TryRead_EnvToken_WorksWithoutAnyFile()
    {
        string path = Path.Combine(Path.GetTempPath(), $"cuw-missing-{Guid.NewGuid():N}.json");
        var reader = new CredentialsReader(
            path,
            name => name == "CLAUDE_CODE_OAUTH_TOKEN" ? "env-token" : null);

        ClaudeCredentials? creds = reader.TryRead();

        Assert.NotNull(creds);
        Assert.Equal("env-token", creds!.AccessToken);
    }

    [Fact]
    public void TryRead_WhitespaceEnvToken_FallsBackToFile()
    {
        string path = WriteTemp(
            "{\"claudeAiOauth\":{\"accessToken\":\"file-token\",\"expiresAt\":123}}");
        try
        {
            var reader = new CredentialsReader(
                path,
                name => name == "CLAUDE_CODE_OAUTH_TOKEN" ? "   " : null);
            ClaudeCredentials? creds = reader.TryRead();

            Assert.NotNull(creds);
            Assert.Equal("file-token", creds!.AccessToken);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void TryRead_ClaudeConfigDir_ResolvesCredentialsFile()
    {
        string dir = Path.Combine(Path.GetTempPath(), $"cuw-cfg-{Guid.NewGuid():N}");
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, ".credentials.json");
        File.WriteAllText(
            path,
            "{\"claudeAiOauth\":{\"accessToken\":\"cfg-token\",\"expiresAt\":1781120644269}}");
        try
        {
            var reader = new CredentialsReader(
                path: null,
                name => name == "CLAUDE_CONFIG_DIR" ? dir : null);
            ClaudeCredentials? creds = reader.TryRead();

            Assert.NotNull(creds);
            Assert.Equal("cfg-token", creds!.AccessToken);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void TryRead_ExplicitPath_WinsOverClaudeConfigDir()
    {
        string explicitPath = WriteTemp(
            "{\"claudeAiOauth\":{\"accessToken\":\"explicit-token\",\"expiresAt\":123}}");
        try
        {
            var reader = new CredentialsReader(
                explicitPath,
                name => name == "CLAUDE_CONFIG_DIR" ? @"C:\nonexistent-dir" : null);
            ClaudeCredentials? creds = reader.TryRead();

            Assert.NotNull(creds);
            Assert.Equal("explicit-token", creds!.AccessToken);
        }
        finally
        {
            File.Delete(explicitPath);
        }
    }
}
