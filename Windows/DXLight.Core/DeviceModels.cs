namespace DXLight.Core;

public enum TransportKind
{
    Hid,
    Serial
}

public sealed record DiscoveredDevice(
    TransportKind Kind,
    string Path,
    int VendorId,
    int ProductId,
    string? Manufacturer,
    string? Product)
{
    public string DisplayName => Product ?? Manufacturer ?? Path;
}

public enum ConnectionState
{
    Searching,
    Connected,
    Error
}

public sealed record ConnectionStatus(ConnectionState State, DiscoveredDevice? Device = null, string? Message = null)
{
    public static ConnectionStatus Searching() => new(ConnectionState.Searching);
    public static ConnectionStatus Connected(DiscoveredDevice device) => new(ConnectionState.Connected, device);
    public static ConnectionStatus Error(string message) => new(ConnectionState.Error, null, message);
}

public sealed record RgbColor(byte Red, byte Green, byte Blue)
{
    public static RgbColor WarmWhite { get; } = new(255, 200, 150);
    public static RgbColor Off { get; } = new(0, 0, 0);
    public static RgbColor WarmOrange { get; } = new(255, 150, 60);
    public static RgbColor LightBlue { get; } = new(140, 200, 255);
    public static RgbColor SoftPurple { get; } = new(190, 140, 255);
}

public sealed record ColorPreset(string Name, RgbColor Color)
{
    public const string SavedName = "Saved";

    public static IReadOnlyList<ColorPreset> Defaults { get; } =
    [
        new("Warm Orange", RgbColor.WarmOrange),
        new("Light Blue", RgbColor.LightBlue),
        new("Soft Purple", RgbColor.SoftPurple)
    ];
}

public sealed record DeviceInfo(
    string Id,
    string Uuid,
    string Version,
    int LampsAmount,
    int DisplaySize);

public enum RobobloqDeviceEvent
{
    PowerOn,
    PowerOff
}

public sealed class DeviceTransportException : Exception
{
    public DeviceTransportException(DeviceTransportError error, string? detail = null, Exception? innerException = null)
        : base(BuildMessage(error, detail), innerException)
    {
        Error = error;
        Detail = detail;
    }

    public DeviceTransportError Error { get; }
    public string? Detail { get; }

    private static string BuildMessage(DeviceTransportError error, string? detail)
    {
        return error switch
        {
            DeviceTransportError.DeviceNotFound => "DX Light strip not found. Check the USB connection and close any other DX Light app.",
            DeviceTransportError.OpenFailed => $"Failed to open device: {detail}",
            DeviceTransportError.WriteFailed => $"Failed to write to device: {detail}",
            DeviceTransportError.ReadTimeout => "Timed out waiting for a device response.",
            DeviceTransportError.DeviceBusy => "Device is busy. Close any other app using the strip and try again.",
            DeviceTransportError.InvalidResponse => "Received an invalid response from the device.",
            _ => detail ?? error.ToString()
        };
    }
}

public enum DeviceTransportError
{
    DeviceNotFound,
    OpenFailed,
    WriteFailed,
    ReadTimeout,
    DeviceBusy,
    InvalidResponse
}
