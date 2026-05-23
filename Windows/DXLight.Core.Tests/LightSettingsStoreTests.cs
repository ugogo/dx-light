using DXLight.Core;

namespace DXLight.Core.Tests;

public sealed class LightSettingsStoreTests
{
    [Fact]
    public void MissingSettingsFileLoadsDefaults()
    {
        var store = new LightSettingsStore(Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString(), "settings.json"));

        var settings = store.Load();

        Assert.False(settings.IsOn);
        Assert.Equal(0.5, settings.Brightness);
        Assert.Equal(RgbColor.WarmWhite, settings.Color);
        Assert.True(settings.SmoothTransitions);
        Assert.True(settings.TurnOnWhenUsbConnects);
        Assert.Null(settings.SavedPreset);
    }

    [Fact]
    public void SaveAndLoadRoundTripsSettings()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var store = new LightSettingsStore(Path.Combine(directory, "settings.json"));

        store.Save(new LightSettings
        {
            IsOn = true,
            Brightness = 0.42,
            Color = RgbColor.LightBlue,
            SmoothTransitions = false,
            TurnOnWhenUsbConnects = false,
            SavedPreset = new ColorPreset(ColorPreset.SavedName, RgbColor.SoftPurple)
        });

        var settings = store.Load();

        Assert.True(settings.IsOn);
        Assert.Equal(0.42, settings.Brightness);
        Assert.Equal(RgbColor.LightBlue, settings.Color);
        Assert.False(settings.SmoothTransitions);
        Assert.False(settings.TurnOnWhenUsbConnects);
        Assert.Equal(new ColorPreset(ColorPreset.SavedName, RgbColor.SoftPurple), settings.SavedPreset);
    }

    [Fact]
    public void BrightnessIsNormalizedOnSave()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var store = new LightSettingsStore(Path.Combine(directory, "settings.json"));

        store.Save(new LightSettings { Brightness = 2.0 });

        Assert.Equal(1.0, store.Load().Brightness);
    }
}
