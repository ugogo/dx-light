namespace DXLight.Core;

public interface IDeviceTransport : IDisposable
{
    DiscoveredDevice Device { get; }
    Action<byte[]>? UnsolicitedInputHandler { get; set; }
    void Open();
    void Close();
    byte[] Write(byte[] data, bool expectResponse);
}

public static class DeviceTransportExtensions
{
    public static void WriteWithoutResponse(this IDeviceTransport transport, byte[] data)
    {
        transport.Write(data, expectResponse: false);
    }

    public static byte[] WriteWithResponse(this IDeviceTransport transport, byte[] data)
    {
        return transport.Write(data, expectResponse: true);
    }
}
