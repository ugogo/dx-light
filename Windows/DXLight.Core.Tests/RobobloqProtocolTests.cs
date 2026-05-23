using DXLight.Core;

namespace DXLight.Core.Tests;

public sealed class RobobloqProtocolTests
{
    [Fact]
    public void TransportPacketNormalizeRemovesHidReportPrefix()
    {
        var normalized = TransportPacket.Normalize([0x00, 0x52, 0x42, 0x06, 0x11, 0x82, 0x2D]);

        Assert.Equal([0x52, 0x42, 0x06, 0x11, 0x82, 0x2D], normalized);
        Assert.Equal((byte?)0x11, TransportPacket.MessageId(normalized));
    }

    [Fact]
    public void BuildsPacketsWithExpectedChecksumAndMessageId()
    {
        RobobloqProtocol.ResetMessageIdsForTests();

        Assert.Equal([0x52, 0x42, 0x06, 0x01, 0x82, 0x1D], RobobloqProtocol.ReadDeviceInfo());
        Assert.Equal([0x52, 0x42, 0x07, 0x02, 0x87, 0x80, 0xA4], RobobloqProtocol.SetBrightness(128));
    }

    [Fact]
    public void ParsesDeviceInfoFromReadResponse()
    {
        byte[] response =
        [
            0x52, 0x42, 0x18, 0x01, 0x82,
            0xAA, 0xBB, 0xCC,
            0x10, 0x00, 0x00, 0x32,
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x00, 0x01, 0x02, 0x03
        ];

        var info = RobobloqProtocol.ParseDeviceInfo(response);

        Assert.Equal("aabbcc", info?.Id);
        Assert.Equal("0102030405060708", info?.Uuid);
        Assert.Equal(16, info?.DisplaySize);
        Assert.Equal(50, info?.LampsAmount);
        Assert.Equal("1.2.3", info?.Version);
    }

    [Fact]
    public void ParseDeviceEventAcceptsStatusNotificationOnly()
    {
        Assert.Equal(RobobloqDeviceEvent.PowerOn, RobobloqProtocol.ParseDeviceEvent(StatusNotification(1)));
        Assert.Equal(RobobloqDeviceEvent.PowerOff, RobobloqProtocol.ParseDeviceEvent(StatusNotification(0)));

        Assert.Null(RobobloqProtocol.ParseDeviceEvent(RobobloqProtocol.TurnOffLight()));
        Assert.Null(RobobloqProtocol.ParseDeviceEvent(RobobloqProtocol.SetBrightness(128)));
        Assert.Null(RobobloqProtocol.ParseDeviceEvent(
            RobobloqProtocol.SetSectionLed(RobobloqProtocol.SectionPayload(RgbColor.WarmWhite, 254))));
    }

    [Fact]
    public void ParsePowerStateFromReadResponse()
    {
        var off = ReadResponse(0, 5);
        var on = ReadResponse(1, 128);
        var inferredOff = ReadResponse(9, 5);
        var inferredOn = ReadResponse(9, 6);

        Assert.False(RobobloqProtocol.ParsePowerState(off));
        Assert.True(RobobloqProtocol.ParsePowerState(on));
        Assert.False(RobobloqProtocol.ParsePowerState(inferredOff));
        Assert.True(RobobloqProtocol.ParsePowerState(inferredOn));

        off[0] = 0x00;
        on[1] = 0x00;
        inferredOff = [0x52, 0x42, 0x01];
        inferredOn[10] = 4;

        Assert.Null(RobobloqProtocol.ParsePowerState(off));
        Assert.Null(RobobloqProtocol.ParsePowerState(on));
        Assert.Null(RobobloqProtocol.ParsePowerState(inferredOff));
        Assert.False(RobobloqProtocol.ParsePowerState(inferredOn));
    }

    [Fact]
    public void DeviceRawBrightnessIsClampedToSupportedRange()
    {
        Assert.Equal(5, DeviceSession.DeviceRawBrightness(-1));
        Assert.Equal(5, DeviceSession.DeviceRawBrightness(0));
        Assert.Equal(255, DeviceSession.DeviceRawBrightness(1));
    }

    private static byte[] StatusNotification(byte powerByte)
    {
        return [0x52, 0x42, 0x09, 0x01, (byte)RobobloqAction.StatusNotification, 0, 0, 0, powerByte, 0];
    }

    private static byte[] ReadResponse(byte powerByte, byte brightnessByte)
    {
        return [0x52, 0x42, 0x0C, 0x01, (byte)RobobloqAction.ReadDeviceInfo, 0, 0, 0, 0, powerByte, brightnessByte, 0];
    }
}
