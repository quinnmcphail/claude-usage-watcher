using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClaudeUsageWatcher;

public sealed class Settings
{
    [JsonPropertyName("left")]
    public double? Left { get; set; }

    [JsonPropertyName("top")]
    public double? Top { get; set; }

    [JsonPropertyName("hidden")]
    public bool Hidden { get; set; }

    [JsonPropertyName("expanded")]
    public bool Expanded { get; set; }

    [JsonPropertyName("notificationsEnabled")]
    public bool NotificationsEnabled { get; set; } = true;

    [JsonPropertyName("notifyWarnAt")]
    public double NotifyWarnAt { get; set; } = 80;

    [JsonPropertyName("notifyCriticalAt")]
    public double NotifyCriticalAt { get; set; } = 95;

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never
    };

    public static string FilePath
    {
        get
        {
            string dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "ClaudeUsageWatcher");
            return Path.Combine(dir, "settings.json");
        }
    }

    public static Settings Load()
    {
        try
        {
            string path = FilePath;
            if (!File.Exists(path))
            {
                return new Settings();
            }

            string json = File.ReadAllText(path);
            Settings? loaded = JsonSerializer.Deserialize<Settings>(json, Options);
            return loaded ?? new Settings();
        }
        catch (Exception)
        {
            return new Settings();
        }
    }

    public void Save()
    {
        try
        {
            string path = FilePath;
            string? dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir))
            {
                Directory.CreateDirectory(dir);
            }

            string json = JsonSerializer.Serialize(this, Options);
            File.WriteAllText(path, json);
        }
        catch (Exception)
        {
            // best-effort; ignore failures
        }
    }
}
