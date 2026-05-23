using System.Globalization;

namespace DXLight.Core;

public enum RobobloqAction : byte
{
    SetSyncScreen = 128,
    WriteDeviceInfo = 129,
    ReadDeviceInfo = 130,
    ReadDeviceUuid = 131,
    SetLedEffect = 133,
    SetSectionLed = 134,
    SetBrightness = 135,
    SetAutoOff = 137,
    SetDynamicSpeed = 138,
    SetSoundSensitivity = 139,
    TurnOffLight = 151,
    StatusNotification = 241
}

public static class RobobloqConstants
{
    public const int LightVendorId = 0x1A86;
    public const int LightProductId = 0xFE07;
    public const int CdcProductId = 0xFE0C;
    public const byte MinimumBrightness = 5;
    public const byte MaximumBrightness = 255;

    public static ReadOnlySpan<byte> Header => [0x52, 0x42];
}

public static class TransportPacket
{
    public static byte[] Normalize(ReadOnlySpan<byte> data)
    {
        if (data.Length > 0 && data[0] == 0x00)
        {
            data = data[1..];
        }

        return data.ToArray();
    }

    public static byte? MessageId(ReadOnlySpan<byte> data)
    {
        var packet = Normalize(data);
        return packet.Length > 3 ? packet[3] : null;
    }
}

public static class RobobloqProtocol
{
    private static readonly object MessageIdLock = new();
    private static byte _messageId;

    public static byte Checksum(IEnumerable<byte> bytes)
    {
        return (byte)(bytes.Aggregate(0, (sum, value) => (sum + value) % 256));
    }

    public static byte[] ReadDeviceInfo() => BuildPacket(RobobloqAction.ReadDeviceInfo, []);

    public static byte[] ReadDeviceUuid() => BuildPacket(RobobloqAction.ReadDeviceUuid, []);

    public static byte[] SetBrightness(byte value)
    {
        var clamped = Math.Min(Math.Max(value, RobobloqConstants.MinimumBrightness), RobobloqConstants.MaximumBrightness);
        return BuildPacket(RobobloqAction.SetBrightness, [clamped]);
    }

    public static byte[] TurnOffLight() => BuildPacket(RobobloqAction.TurnOffLight, []);

    public static byte[] SetSectionLed(IReadOnlyList<byte> segments)
    {
        if (segments.Count % 5 != 0)
        {
            throw new ArgumentException("Segment data must be groups of 5 bytes.", nameof(segments));
        }

        var messageId = NextMessageId();
        var bytes = new List<byte>(6 + segments.Count)
        {
            0x52,
            0x42,
            (byte)(6 + segments.Count),
            messageId,
            (byte)RobobloqAction.SetSectionLed
        };
        bytes.AddRange(segments);
        bytes.Add(Checksum(bytes));
        return bytes.ToArray();
    }

    public static byte[] SectionPayload(RgbColor color, int lampsAmount)
    {
        if (lampsAmount > 1 && lampsAmount < 254)
        {
            var boundary = (byte)lampsAmount;
            return
            [
                1, color.Red, color.Green, color.Blue, boundary,
                (byte)(boundary + 1), color.Red, color.Green, color.Blue, 254
            ];
        }

        return [1, color.Red, color.Green, color.Blue, 254];
    }

    public static DeviceInfo? ParseDeviceInfo(ReadOnlySpan<byte> response)
    {
        var packet = TransportPacket.Normalize(response);
        if (packet.Length < 24 || packet[0] != 0x52 || packet[1] != 0x42)
        {
            return null;
        }

        var id = ToHex(packet.AsSpan(5, 3));
        var uuid = ToHex(packet.AsSpan(12, 8));
        var version = string.Join(".", packet[21], packet[22], packet[23]);

        return new DeviceInfo(id, uuid, version, packet[11], packet[8]);
    }

    public static bool? ParsePowerState(ReadOnlySpan<byte> response)
    {
        var packet = TransportPacket.Normalize(response);
        if (packet.Length < 12 || packet[0] != 0x52 || packet[1] != 0x42)
        {
            return null;
        }

        return packet[9] switch
        {
            0 => false,
            1 => true,
            _ when packet[10] <= RobobloqConstants.MinimumBrightness => false,
            _ when packet[10] >= RobobloqConstants.MinimumBrightness => true,
            _ => null
        };
    }

    public static RobobloqDeviceEvent? ParseDeviceEvent(ReadOnlySpan<byte> data)
    {
        var packet = TransportPacket.Normalize(data);
        if (packet.Length <= 8 ||
            packet[0] != 0x52 ||
            packet[1] != 0x42 ||
            packet[4] != (byte)RobobloqAction.StatusNotification)
        {
            return null;
        }

        return packet[8] switch
        {
            0 => RobobloqDeviceEvent.PowerOff,
            1 => RobobloqDeviceEvent.PowerOn,
            _ => null
        };
    }

    public static void ResetMessageIdsForTests()
    {
        lock (MessageIdLock)
        {
            _messageId = 0;
        }
    }

    private static byte[] BuildPacket(RobobloqAction action, IReadOnlyList<byte> payload)
    {
        var bytes = new List<byte>(6 + payload.Count)
        {
            0x52,
            0x42,
            (byte)(6 + payload.Count),
            NextMessageId(),
            (byte)action
        };
        bytes.AddRange(payload);
        bytes.Add(Checksum(bytes));
        return bytes.ToArray();
    }

    private static byte NextMessageId()
    {
        lock (MessageIdLock)
        {
            _messageId++;
            if (_messageId == 0 || _messageId >= 255)
            {
                _messageId = 1;
            }

            return _messageId;
        }
    }

    private static string ToHex(ReadOnlySpan<byte> bytes)
    {
        return string.Concat(bytes.ToArray().Select(value => value.ToString("x2", CultureInfo.InvariantCulture)));
    }
}
