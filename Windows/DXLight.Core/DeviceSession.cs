namespace DXLight.Core;

public static class DeviceSession
{
    public const int DefaultLampsAmount = 254;

    public static T WithTransport<T>(Func<IDeviceTransport, DeviceInfo, T> body, DiscoveredDevice? device = null, double settleDelaySeconds = 0.5)
    {
        var discovered = device ?? DeviceDiscovery.DiscoverPreferred();
        if (discovered is null)
        {
            throw new DeviceTransportException(DeviceTransportError.DeviceNotFound);
        }

        using var transport = DeviceDiscovery.MakeTransport(discovered);
        transport.Open();
        Thread.Sleep(TimeSpan.FromSeconds(settleDelaySeconds));

        var info = ReadDeviceInfo(transport);
        return body(transport, info);
    }

    public static IReadOnlyList<DiscoveredDevice> ListDevices() => DeviceDiscovery.DiscoverAll();

    public static DeviceInfo ReadDeviceInfo(IDeviceTransport transport)
    {
        try
        {
            var response = transport.Write(RobobloqProtocol.ReadDeviceInfo(), expectResponse: true);
            return RobobloqProtocol.ParseDeviceInfo(response) ?? DefaultDeviceInfo();
        }
        catch
        {
            return DefaultDeviceInfo();
        }
    }

    public static byte[]? QueryDeviceState(IDeviceTransport transport)
    {
        try
        {
            var response = transport.Write(RobobloqProtocol.ReadDeviceInfo(), expectResponse: true);
            var packet = TransportPacket.Normalize(response);
            return packet.Length >= 6 && packet[0] == 0x52 && packet[1] == 0x42 ? packet : null;
        }
        catch
        {
            return null;
        }
    }

    public static void TurnOff(IDeviceTransport transport, int lampsAmount)
    {
        transport.WriteWithoutResponse(RobobloqProtocol.TurnOffLight());
        Thread.Sleep(100);
        transport.WriteWithoutResponse(RobobloqProtocol.TurnOffLight());

        var segments = RobobloqProtocol.SectionPayload(RgbColor.Off, lampsAmount);
        transport.WriteWithoutResponse(RobobloqProtocol.SetSectionLed(segments));
        Thread.Sleep(100);
        transport.WriteWithoutResponse(RobobloqProtocol.SetSectionLed(segments));
    }

    public static void TurnOn(IDeviceTransport transport, int lampsAmount, RgbColor? color = null, double brightness = 0.5)
    {
        var targetColor = color ?? RgbColor.WarmWhite;
        var segments = RobobloqProtocol.SectionPayload(targetColor, lampsAmount);
        transport.WriteWithoutResponse(RobobloqProtocol.SetSectionLed(segments));
        Thread.Sleep(20);
        transport.WriteWithoutResponse(RobobloqProtocol.SetSectionLed(segments));
        SetBrightness(brightness, transport);
    }

    public static void SetBrightness(double value, IDeviceTransport transport)
    {
        transport.WriteWithoutResponse(RobobloqProtocol.SetBrightness(DeviceRawBrightness(value)));
    }

    public static byte DeviceRawBrightness(double value)
    {
        var clamped = Math.Min(Math.Max(value, 0.0), 1.0);
        var raw = (int)Math.Round(clamped * RobobloqConstants.MaximumBrightness);
        return (byte)Math.Min(Math.Max(raw, RobobloqConstants.MinimumBrightness), RobobloqConstants.MaximumBrightness);
    }

    public static void ApplyBrightness(double value, RgbColor color, int lampsAmount, IDeviceTransport transport)
    {
        SetBrightness(value, transport);
        Thread.Sleep(20);
        var segments = RobobloqProtocol.SectionPayload(color, lampsAmount);
        transport.WriteWithoutResponse(RobobloqProtocol.SetSectionLed(segments));
    }

    public static DeviceInfo DefaultDeviceInfo() => new("unknown", "unknown", "unknown", DefaultLampsAmount, 0);
}
