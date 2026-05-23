using HidSharp;

namespace DXLight.Core;

public static class DeviceDiscovery
{
    public static IReadOnlyList<DiscoveredDevice> DiscoverAll()
    {
        return DeviceList.Local
            .GetHidDevices(RobobloqConstants.LightVendorId, RobobloqConstants.LightProductId)
            .OrderByDescending(IsPreferredVendorInterface)
            .ThenByDescending(device => SafeReportLength(device))
            .Select(ToDiscoveredDevice)
            .ToArray();
    }

    public static DiscoveredDevice? DiscoverPreferred()
    {
        return DiscoverAll().FirstOrDefault();
    }

    public static IDeviceTransport MakeTransport(DiscoveredDevice device)
    {
        return device.Kind switch
        {
            TransportKind.Hid => new HidDeviceTransport(device),
            _ => throw new NotSupportedException("Serial transport is not implemented on Windows v1.")
        };
    }

    internal static HidDevice FindHidDevice(DiscoveredDevice discovered)
    {
        var devices = DeviceList.Local.GetHidDevices(discovered.VendorId, discovered.ProductId);
        var selected = devices.FirstOrDefault(device =>
            string.Equals(device.DevicePath, discovered.Path, StringComparison.OrdinalIgnoreCase));

        return selected ?? throw new DeviceTransportException(DeviceTransportError.DeviceNotFound);
    }

    private static DiscoveredDevice ToDiscoveredDevice(HidDevice device)
    {
        return new DiscoveredDevice(
            TransportKind.Hid,
            device.DevicePath,
            device.VendorID,
            device.ProductID,
            SafeString(device.GetManufacturer),
            SafeString(device.GetProductName) ?? SafeString(device.GetFriendlyName));
    }

    private static bool IsPreferredVendorInterface(HidDevice device)
    {
        return device.DevicePath.Contains("mi_00", StringComparison.OrdinalIgnoreCase);
    }

    private static int SafeReportLength(HidDevice device)
    {
        try
        {
            return device.GetMaxOutputReportLength();
        }
        catch
        {
            return 0;
        }
    }

    private static string? SafeString(Func<string> read)
    {
        try
        {
            var value = read();
            return string.IsNullOrWhiteSpace(value) ? null : value;
        }
        catch
        {
            return null;
        }
    }
}
