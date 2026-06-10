using ClaudeUsageWatcher.Core;
using Xunit;

namespace ClaudeUsageWatcher.Core.Tests;

public class CredentialsReaderTests
{
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
            var reader = new CredentialsReader(path);
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
        var reader = new CredentialsReader(path);
        Assert.Null(reader.TryRead());
    }

    [Fact]
    public void TryRead_MalformedJson_ReturnsNull()
    {
        string path = WriteTemp("{ not valid json ");
        try
        {
            var reader = new CredentialsReader(path);
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
            var reader = new CredentialsReader(path);
            Assert.Null(reader.TryRead());
        }
        finally
        {
            File.Delete(path);
        }
    }
}
