using System.Text.Json;

namespace DXLight.Core;

public sealed class LightSettings
{
    public bool IsOn { get; set; }
    public double Brightness { get; set; } = 0.5;
    public RgbColor Color { get; set; } = RgbColor.WarmWhite;
    public bool SmoothTransitions { get; set; } = true;
    public bool TurnOnWhenUsbConnects { get; set; } = true;
    public ColorPreset? SavedPreset { get; set; }
}

public sealed class LightSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    public LightSettingsStore(string? path = null)
    {
        Path = path ?? System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "DXLight",
            "settings.json");
    }

    public string Path { get; }

    public LightSettings Load()
    {
        if (!File.Exists(Path))
        {
            return new LightSettings();
        }

        try
        {
            var settings = JsonSerializer.Deserialize<LightSettings>(File.ReadAllText(Path), JsonOptions);
            return Normalize(settings ?? new LightSettings());
        }
        catch
        {
            return new LightSettings();
        }
    }

    public void Save(LightSettings settings)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        File.WriteAllText(Path, JsonSerializer.Serialize(Normalize(settings), JsonOptions));
    }

    private static LightSettings Normalize(LightSettings settings)
    {
        settings.Brightness = Math.Min(Math.Max(settings.Brightness, 0.0), 1.0);
        settings.Color ??= RgbColor.WarmWhite;
        return settings;
    }
}
