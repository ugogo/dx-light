using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace DXLight.Core;

internal sealed record PowerCommandRequest(
    DiscoveredDevice? Device,
    bool TargetOn,
    double Brightness,
    RgbColor Color,
    int LampsAmount,
    bool Animated,
    double FromBrightness,
    double SettleDelaySeconds,
    bool ReadsDeviceInfo);

public sealed class LightController : INotifyPropertyChanged, IDisposable
{
    private const int TransitionSteps = 5;
    private const double TransitionStepDelaySeconds = 0.025;
    private static readonly double MinimumUiBrightness = (double)RobobloqConstants.MinimumBrightness / RobobloqConstants.MaximumBrightness;

    private readonly LightSettingsStore _settingsStore;
    private readonly Func<PowerCommandRequest, Task<DeviceInfo>> _powerCommand;
    private readonly SemaphoreSlim _deviceSemaphore = new(1, 1);
    private CancellationTokenSource? _pollCancellation;
    private CancellationTokenSource? _brightnessDebounceCancellation;
    private Task? _pollTask;
    private DeviceInfo? _deviceInfo;
    private DiscoveredDevice? _connectedDevice;
    private RgbColor _appliedColor;
    private double _appliedBrightness;
    private LightSettings _settings;

    public LightController(LightSettingsStore? settingsStore = null)
        : this(settingsStore ?? new LightSettingsStore(), RunPowerCommandAsync)
    {
    }

    internal LightController(LightSettingsStore settingsStore, Func<PowerCommandRequest, Task<DeviceInfo>> powerCommand)
    {
        _settingsStore = settingsStore;
        _powerCommand = powerCommand;
        _settings = _settingsStore.Load();
        _appliedColor = _settings.Color;
        _appliedBrightness = _settings.Brightness;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ConnectionStatus Status { get; private set; } = ConnectionStatus.Searching();
    public bool IsBusy { get; private set; }
    public bool IsOn => _settings.IsOn;
    public double Brightness => _settings.Brightness;
    public RgbColor Color => _settings.Color;
    public bool SmoothTransitions => _settings.SmoothTransitions;
    public bool TurnOnWhenUsbConnects => _settings.TurnOnWhenUsbConnects;
    public ColorPreset? SavedPreset => _settings.SavedPreset;
    public IReadOnlyList<ColorPreset> ColorPresets => _settings.SavedPreset is null
        ? ColorPreset.Defaults
        : ColorPreset.Defaults.Concat([_settings.SavedPreset]).ToArray();

    public void Start()
    {
        Stop();
        _pollCancellation = new CancellationTokenSource();
        _pollTask = Task.Run(() => PollLoopAsync(_pollCancellation.Token));
    }

    public void Stop()
    {
        _pollCancellation?.Cancel();
        CancelPendingAdjustments();
        try
        {
            _pollTask?.Wait(TimeSpan.FromSeconds(1));
        }
        catch
        {
        }

        _pollTask = null;
        _pollCancellation?.Dispose();
        _pollCancellation = null;
    }

    public async Task RefreshConnectionAsync()
    {
        await RefreshDevicePresenceAsync(force: true).ConfigureAwait(false);
    }

    public async Task PrepareForSystemSleepAsync()
    {
        CancelPendingAdjustments();
        await SendPowerCommandAsync(CreatePowerCommandRequest(
            targetOn: false,
            animated: false,
            settleDelaySeconds: 0.05,
            readsDeviceInfo: false)).ConfigureAwait(false);
    }

    public async Task RestoreAfterSystemWakeAsync()
    {
        CancelPendingAdjustments();
        if (!_settings.IsOn)
        {
            _settings.IsOn = true;
            OnPropertyChanged(nameof(IsOn));
        }

        PersistState();
        await ApplyPowerStateAsync().ConfigureAwait(false);
    }

    public async Task SetPowerAsync(bool enabled)
    {
        if (_settings.IsOn == enabled)
        {
            return;
        }

        _settings.IsOn = enabled;
        PersistState();
        OnPropertyChanged(nameof(IsOn));
        await ApplyPowerStateAsync().ConfigureAwait(false);
    }

    public Task TogglePowerAsync() => SetPowerAsync(!IsOn);

    public void SetBrightness(double value)
    {
        var clamped = Math.Min(Math.Max(value, 0.0), 1.0);
        if (Math.Abs(_settings.Brightness - clamped) < 0.001)
        {
            return;
        }

        _settings.Brightness = clamped;
        PersistState();
        OnPropertyChanged(nameof(Brightness));

        if (_settings.IsOn)
        {
            DebounceBrightness(clamped);
        }
    }

    public void SetColor(RgbColor color)
    {
        if (_settings.Color == color)
        {
            return;
        }

        _settings.Color = color;
        PersistState();
        OnPropertyChanged(nameof(Color));

        if (_settings.IsOn)
        {
            _ = Task.Run(SendColorAsync);
        }
    }

    public void SaveColorAsPreset(RgbColor? colorToSave = null)
    {
        _settings.SavedPreset = new ColorPreset(ColorPreset.SavedName, colorToSave ?? _settings.Color);
        PersistState();
        OnPropertyChanged(nameof(SavedPreset));
        OnPropertyChanged(nameof(ColorPresets));
    }

    public void SetSmoothTransitions(bool enabled)
    {
        if (_settings.SmoothTransitions == enabled)
        {
            return;
        }

        _settings.SmoothTransitions = enabled;
        PersistState();
        OnPropertyChanged(nameof(SmoothTransitions));
    }

    public void SetTurnOnWhenUsbConnects(bool enabled)
    {
        if (_settings.TurnOnWhenUsbConnects == enabled)
        {
            return;
        }

        _settings.TurnOnWhenUsbConnects = enabled;
        PersistState();
        OnPropertyChanged(nameof(TurnOnWhenUsbConnects));
    }

    public void Dispose()
    {
        Stop();
        _deviceSemaphore.Dispose();
    }

    private async Task PollLoopAsync(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            await RefreshDevicePresenceAsync(force: false).ConfigureAwait(false);
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(1), token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }

    private async Task RefreshDevicePresenceAsync(bool force)
    {
        var wasConnected = Status.State == ConnectionState.Connected;
        var discovered = DeviceDiscovery.DiscoverPreferred();
        if (discovered is null)
        {
            _connectedDevice = null;
            _deviceInfo = null;
            SetStatus(ConnectionStatus.Error(new DeviceTransportException(DeviceTransportError.DeviceNotFound).Message));
            return;
        }

        if (!force && _connectedDevice == discovered && Status.State == ConnectionState.Connected)
        {
            SetStatus(ConnectionStatus.Connected(discovered));
            return;
        }

        if (_connectedDevice is null || _connectedDevice != discovered || force)
        {
            SetStatus(ConnectionStatus.Searching());
        }

        _connectedDevice = discovered;
        _deviceInfo = DeviceSession.DefaultDeviceInfo();
        SetStatus(ConnectionStatus.Connected(discovered));

        if (wasConnected && !force)
        {
            return;
        }

        if (_settings.TurnOnWhenUsbConnects)
        {
            if (!_settings.IsOn)
            {
                _settings.IsOn = true;
                PersistState();
                OnPropertyChanged(nameof(IsOn));
            }

            await ApplyPowerStateAsync().ConfigureAwait(false);
        }
        else if (_settings.IsOn)
        {
            await ApplyPowerStateAsync().ConfigureAwait(false);
        }
    }

    private async Task ApplyPowerStateAsync()
    {
        await SendPowerCommandAsync(CreatePowerCommandRequest(
            targetOn: _settings.IsOn,
            animated: _settings.SmoothTransitions,
            settleDelaySeconds: 0.5,
            readsDeviceInfo: true)).ConfigureAwait(false);
    }

    private Task SendPowerCommandAsync(PowerCommandRequest request)
    {
        return RunDeviceCommandAsync(async () =>
        {
            var info = await _powerCommand(request).ConfigureAwait(false);
            _deviceInfo = info;
            _appliedBrightness = request.Brightness;
            _appliedColor = request.Color;
        });
    }

    private PowerCommandRequest CreatePowerCommandRequest(
        bool targetOn,
        bool animated,
        double settleDelaySeconds,
        bool readsDeviceInfo)
    {
        return new PowerCommandRequest(
            _connectedDevice,
            targetOn,
            _settings.Brightness,
            _settings.Color,
            _deviceInfo?.LampsAmount ?? DeviceSession.DefaultLampsAmount,
            animated,
            _appliedBrightness,
            settleDelaySeconds,
            readsDeviceInfo);
    }

    private Task SendColorAsync()
    {
        var device = _connectedDevice;
        var currentColor = _settings.Color;
        var brightness = _settings.Brightness;
        var lampsAmount = _deviceInfo?.LampsAmount ?? DeviceSession.DefaultLampsAmount;
        var animated = _settings.SmoothTransitions;
        var fromColor = _appliedColor;

        return RunDeviceCommandAsync(() =>
        {
            DeviceSession.WithTransport((transport, _) =>
            {
                if (animated)
                {
                    TransitionColor(fromColor, currentColor, brightness, lampsAmount, transport);
                }
                else
                {
                    DeviceSession.ApplyBrightness(brightness, currentColor, lampsAmount, transport);
                }

                return true;
            }, device, settleDelaySeconds: 0.05);

            _appliedColor = currentColor;
            _appliedBrightness = brightness;
        });
    }

    private Task SendBrightnessAsync(double value)
    {
        var device = _connectedDevice;
        var color = _settings.Color;
        var lampsAmount = _deviceInfo?.LampsAmount ?? DeviceSession.DefaultLampsAmount;
        var animated = _settings.SmoothTransitions;
        var fromBrightness = _appliedBrightness;

        return RunDeviceCommandAsync(() =>
        {
            DeviceSession.WithTransport((transport, _) =>
            {
                if (animated)
                {
                    TransitionBrightness(fromBrightness, value, color, lampsAmount, transport);
                }
                else
                {
                    DeviceSession.ApplyBrightness(value, color, lampsAmount, transport);
                }

                return true;
            }, device, settleDelaySeconds: 0.05);

            _appliedBrightness = value;
            _appliedColor = color;
        });
    }

    private void DebounceBrightness(double value)
    {
        CancelPendingAdjustments();
        var cancellation = new CancellationTokenSource();
        _brightnessDebounceCancellation = cancellation;

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(150, cancellation.Token).ConfigureAwait(false);
                await SendBrightnessAsync(value).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
            }
        }, cancellation.Token);
    }

    private void CancelPendingAdjustments()
    {
        var cancellation = _brightnessDebounceCancellation;
        _brightnessDebounceCancellation = null;
        cancellation?.Cancel();
        cancellation?.Dispose();
    }

    private Task RunDeviceCommandAsync(Action command)
    {
        return RunDeviceCommandAsync(() => Task.Run(command));
    }

    private async Task RunDeviceCommandAsync(Func<Task> command)
    {
        await _deviceSemaphore.WaitAsync().ConfigureAwait(false);
        SetBusy(true);
        try
        {
            await command().ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            SetStatus(ConnectionStatus.Error(exception.Message));
            _connectedDevice = null;
        }
        finally
        {
            SetBusy(false);
            _deviceSemaphore.Release();
        }
    }

    private static Task<DeviceInfo> RunPowerCommandAsync(PowerCommandRequest request)
    {
        return Task.Run(() =>
        {
            if (request.ReadsDeviceInfo)
            {
                return DeviceSession.WithTransport((transport, info) =>
                {
                    RunPowerCommand(request, transport);
                    return info;
                }, request.Device, settleDelaySeconds: request.SettleDelaySeconds);
            }

            var discovered = request.Device ?? DeviceDiscovery.DiscoverPreferred();
            if (discovered is null)
            {
                throw new DeviceTransportException(DeviceTransportError.DeviceNotFound);
            }

            using var transport = DeviceDiscovery.MakeTransport(discovered);
            transport.Open();
            if (request.SettleDelaySeconds > 0)
            {
                Thread.Sleep(TimeSpan.FromSeconds(request.SettleDelaySeconds));
            }

            RunPowerCommand(request, transport);
            return DeviceSession.DefaultDeviceInfo();
        });
    }

    private static void RunPowerCommand(PowerCommandRequest request, IDeviceTransport transport)
    {
        if (request.TargetOn)
        {
            if (request.Animated)
            {
                TurnOnSmoothly(transport, request.LampsAmount, request.Color, request.Brightness);
            }
            else
            {
                DeviceSession.TurnOn(transport, request.LampsAmount, request.Color, request.Brightness);
            }
        }
        else if (request.Animated)
        {
            TurnOffSmoothly(transport, request.LampsAmount, request.Color, request.FromBrightness);
        }
        else
        {
            DeviceSession.TurnOff(transport, request.LampsAmount);
        }
    }

    private static void TurnOnSmoothly(IDeviceTransport transport, int lampsAmount, RgbColor color, double brightness)
    {
        DeviceSession.ApplyBrightness(MinimumUiBrightness, color, lampsAmount, transport);
        TransitionBrightness(MinimumUiBrightness, brightness, color, lampsAmount, transport);
    }

    private static void TurnOffSmoothly(IDeviceTransport transport, int lampsAmount, RgbColor color, double fromBrightness)
    {
        TransitionBrightness(fromBrightness, MinimumUiBrightness, color, lampsAmount, transport);
        DeviceSession.TurnOff(transport, lampsAmount);
    }

    private static void TransitionBrightness(double start, double end, RgbColor color, int lampsAmount, IDeviceTransport transport)
    {
        if (Math.Abs(start - end) < 0.001)
        {
            DeviceSession.ApplyBrightness(end, color, lampsAmount, transport);
            return;
        }

        for (var step = 1; step <= TransitionSteps; step++)
        {
            var progress = (double)step / TransitionSteps;
            var value = start + ((end - start) * progress);
            DeviceSession.ApplyBrightness(value, color, lampsAmount, transport);
            SleepBetweenTransitionSteps(step);
        }
    }

    private static void TransitionColor(RgbColor start, RgbColor end, double brightness, int lampsAmount, IDeviceTransport transport)
    {
        if (start == end)
        {
            DeviceSession.ApplyBrightness(brightness, end, lampsAmount, transport);
            return;
        }

        for (var step = 1; step <= TransitionSteps; step++)
        {
            var progress = (double)step / TransitionSteps;
            var color = InterpolatedColor(start, end, progress);
            DeviceSession.ApplyBrightness(brightness, color, lampsAmount, transport);
            SleepBetweenTransitionSteps(step);
        }
    }

    private static RgbColor InterpolatedColor(RgbColor start, RgbColor end, double progress)
    {
        return new RgbColor(
            InterpolatedChannel(start.Red, end.Red, progress),
            InterpolatedChannel(start.Green, end.Green, progress),
            InterpolatedChannel(start.Blue, end.Blue, progress));
    }

    private static byte InterpolatedChannel(byte start, byte end, double progress)
    {
        var value = start + ((end - start) * progress);
        return (byte)Math.Min(Math.Max((int)Math.Round(value), 0), 255);
    }

    private static void SleepBetweenTransitionSteps(int step)
    {
        if (step < TransitionSteps)
        {
            Thread.Sleep(TimeSpan.FromSeconds(TransitionStepDelaySeconds));
        }
    }

    private void PersistState() => _settingsStore.Save(_settings);

    private void SetStatus(ConnectionStatus status)
    {
        if (Status == status)
        {
            return;
        }

        Status = status;
        OnPropertyChanged(nameof(Status));
    }

    private void SetBusy(bool busy)
    {
        if (IsBusy == busy)
        {
            return;
        }

        IsBusy = busy;
        OnPropertyChanged(nameof(IsBusy));
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
