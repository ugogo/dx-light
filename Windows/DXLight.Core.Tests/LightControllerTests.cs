using DXLight.Core;

namespace DXLight.Core.Tests;

public sealed class LightControllerTests
{
    [Fact]
    public async Task SystemSleepOffDoesNotPersistPowerOff()
    {
        var store = CreateStore();
        store.Save(new LightSettings
        {
            IsOn = true,
            Brightness = 0.42,
            Color = RgbColor.LightBlue,
            SmoothTransitions = true
        });
        var requests = new List<PowerCommandRequest>();
        using var controller = new LightController(store, request =>
        {
            requests.Add(request);
            return Task.FromResult(DeviceSession.DefaultDeviceInfo());
        });

        await controller.PrepareForSystemSleepAsync();

        var settings = store.Load();
        Assert.True(controller.IsOn);
        Assert.True(settings.IsOn);
        Assert.Equal(0.42, settings.Brightness);
        Assert.Equal(RgbColor.LightBlue, settings.Color);
        Assert.Single(requests);
        Assert.False(requests[0].TargetOn);
        Assert.False(requests[0].Animated);
        Assert.False(requests[0].ReadsDeviceInfo);
    }

    [Fact]
    public async Task WakeSetsAndPersistsPowerOn()
    {
        var store = CreateStore();
        store.Save(new LightSettings { IsOn = false });
        var requests = new List<PowerCommandRequest>();
        using var controller = new LightController(store, request =>
        {
            requests.Add(request);
            return Task.FromResult(DeviceSession.DefaultDeviceInfo());
        });

        await controller.RestoreAfterSystemWakeAsync();

        Assert.True(controller.IsOn);
        Assert.True(store.Load().IsOn);
        Assert.Single(requests);
        Assert.True(requests[0].TargetOn);
        Assert.True(requests[0].Animated);
        Assert.True(requests[0].ReadsDeviceInfo);
    }

    [Fact]
    public async Task SystemSleepPreservesLightSettings()
    {
        var store = CreateStore();
        var savedPreset = new ColorPreset(ColorPreset.SavedName, RgbColor.SoftPurple);
        store.Save(new LightSettings
        {
            IsOn = true,
            Brightness = 0.67,
            Color = RgbColor.WarmOrange,
            SmoothTransitions = false,
            TurnOnWhenUsbConnects = false,
            SavedPreset = savedPreset
        });
        using var controller = new LightController(store, _ => Task.FromResult(DeviceSession.DefaultDeviceInfo()));

        await controller.PrepareForSystemSleepAsync();

        var settings = store.Load();
        Assert.True(settings.IsOn);
        Assert.Equal(0.67, settings.Brightness);
        Assert.Equal(RgbColor.WarmOrange, settings.Color);
        Assert.False(settings.SmoothTransitions);
        Assert.False(settings.TurnOnWhenUsbConnects);
        Assert.Equal(savedPreset, settings.SavedPreset);
    }

    private static LightSettingsStore CreateStore()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        return new LightSettingsStore(Path.Combine(directory, "settings.json"));
    }
}
