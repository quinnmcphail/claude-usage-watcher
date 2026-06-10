namespace ClaudeUsageWatcher.Core;

public sealed class UsageAuthException : Exception
{
    public UsageAuthException(string message) : base(message)
    {
    }
}

public sealed class UsageRateLimitException : Exception
{
    public UsageRateLimitException(string message) : base(message)
    {
    }
}
