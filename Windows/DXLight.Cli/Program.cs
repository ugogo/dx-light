using DXLight.Core;
using System.Globalization;

var arguments = args.ToArray();
if (arguments.Length == 0)
{
    PrintUsage();
    return 1;
}

try
{
    switch (arguments[0].ToLowerInvariant())
    {
        case "list":
            RunList();
            break;
        case "info":
            RunInfo();
            break;
        case "off":
            RunOff();
            break;
        case "on":
            RunOn(ParseDouble(arguments.ElementAtOrDefault(1), 0.5));
            break;
        case "brightness":
            if (arguments.Length < 2 || !double.TryParse(arguments[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var brightness))
            {
                Console.Error.WriteLine("Usage: dx-light brightness <0-1.0>");
                return 1;
            }

            RunBrightness(brightness);
            break;
        case "test":
            RunTest();
            break;
        case "state":
            RunState();
            break;
        default:
            PrintUsage();
            return 1;
    }

    return 0;
}
catch (Exception exception)
{
    Console.Error.WriteLine($"Error: {exception.Message}");
    return 1;
}

static void RunList()
{
    var devices = DeviceSession.ListDevices();
    if (devices.Count == 0)
    {
        Console.WriteLine("No DX Light devices found.");
        return;
    }

    foreach (var device in devices)
    {
        Console.WriteLine(
            "{0}\t{1}\t0x{2:X4}/0x{3:X4}\t{4}",
            device.Kind.ToString().ToLowerInvariant(),
            device.Path,
            device.VendorId,
            device.ProductId,
            device.DisplayName);
    }
}

static void RunInfo()
{
    DeviceSession.WithTransport((_, info) =>
    {
        if (info.Id == "unknown")
        {
            Console.WriteLine("Device info read is unavailable on this HID interface.");
            Console.WriteLine("Using defaults for control commands.");
        }

        Console.WriteLine($"ID: {info.Id}");
        Console.WriteLine($"UUID: {info.Uuid}");
        Console.WriteLine($"Version: {info.Version}");
        Console.WriteLine($"Lamps: {info.LampsAmount}");
        Console.WriteLine($"Display size: {info.DisplaySize}");
        return true;
    });
}

static void RunOff()
{
    DeviceSession.WithTransport((transport, info) =>
    {
        DeviceSession.TurnOff(transport, info.LampsAmount);
        Console.WriteLine("Light turned off.");
        return true;
    });
}

static void RunOn(double brightness)
{
    DeviceSession.WithTransport((transport, info) =>
    {
        DeviceSession.TurnOn(transport, info.LampsAmount, brightness: brightness);
        Console.WriteLine($"Light turned on at {Math.Round(brightness * 100)}%.");
        return true;
    });
}

static void RunBrightness(double value)
{
    DeviceSession.WithTransport((transport, info) =>
    {
        DeviceSession.ApplyBrightness(value, RgbColor.WarmWhite, info.LampsAmount, transport);
        Console.WriteLine($"Brightness set to {Math.Round(value * 100)}%.");
        return true;
    });
}

static void RunTest()
{
    Console.WriteLine("Running off -> on -> brightness 25% -> off test...");
    DeviceSession.WithTransport((transport, info) =>
    {
        Console.WriteLine($"Connected: {info.Version}, {info.LampsAmount} lamps");
        DeviceSession.TurnOff(transport, info.LampsAmount);
        Console.WriteLine("Off");
        Thread.Sleep(500);
        DeviceSession.TurnOn(transport, info.LampsAmount, brightness: 0.5);
        Console.WriteLine("On at 50%");
        Thread.Sleep(500);
        DeviceSession.ApplyBrightness(0.25, RgbColor.WarmWhite, info.LampsAmount, transport);
        Console.WriteLine("Brightness 25%");
        Thread.Sleep(500);
        DeviceSession.TurnOff(transport, info.LampsAmount);
        Console.WriteLine("Off");
        return true;
    });
    Console.WriteLine("Test complete.");
}

static void RunState()
{
    DeviceSession.WithTransport((transport, _) =>
    {
        var packet = DeviceSession.QueryDeviceState(transport);
        if (packet is null)
        {
            Console.WriteLine("No state response.");
            return true;
        }

        Console.WriteLine(string.Join(" ", packet.Select(value => value.ToString("x2", CultureInfo.InvariantCulture))));
        var power = RobobloqProtocol.ParsePowerState(packet);
        Console.WriteLine(power is null ? "power: unknown" : $"power: {(power.Value ? "on" : "off")}");
        return true;
    });
}

static double ParseDouble(string? value, double fallback)
{
    return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var parsed)
        ? parsed
        : fallback;
}

static void PrintUsage()
{
    Console.WriteLine(
        """
        dx-light commands:
          list
          info
          on [brightness 0-1.0]
          off
          brightness <0-1.0>
          test
          state
        """);
}
