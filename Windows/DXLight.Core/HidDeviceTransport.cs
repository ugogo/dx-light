using HidSharp;

namespace DXLight.Core;

public sealed class HidDeviceTransport : IDeviceTransport
{
    private readonly object _writeLock = new();
    private readonly object _responseLock = new();
    private readonly HashSet<byte> _pendingResponseMessageIds = [];
    private readonly List<byte[]> _responseQueue = [];
    private HidDevice? _hidDevice;
    private HidStream? _stream;
    private CancellationTokenSource? _readerCancellation;
    private Task? _readerTask;
    private int _inputReportLength = 64;
    private int _outputReportLength = 65;

    public HidDeviceTransport(DiscoveredDevice device)
    {
        Device = device;
    }

    public DiscoveredDevice Device { get; }
    public Action<byte[]>? UnsolicitedInputHandler { get; set; }

    public void Open()
    {
        _hidDevice = DeviceDiscovery.FindHidDevice(Device);
        _inputReportLength = Math.Max(_hidDevice.GetMaxInputReportLength(), 64);
        _outputReportLength = Math.Max(_hidDevice.GetMaxOutputReportLength(), 65);

        try
        {
            if (!_hidDevice.TryOpen(out var stream))
            {
                throw new DeviceTransportException(DeviceTransportError.DeviceBusy);
            }

            _stream = stream;
            _stream.ReadTimeout = 100;
            _stream.WriteTimeout = 1000;
            StartReader();
        }
        catch (DeviceTransportException)
        {
            throw;
        }
        catch (UnauthorizedAccessException exception)
        {
            throw new DeviceTransportException(DeviceTransportError.DeviceBusy, exception.Message, exception);
        }
        catch (Exception exception)
        {
            throw new DeviceTransportException(DeviceTransportError.OpenFailed, exception.Message, exception);
        }
    }

    public void Close()
    {
        _readerCancellation?.Cancel();
        try
        {
            _readerTask?.Wait(TimeSpan.FromMilliseconds(300));
        }
        catch
        {
            // The stream is being torn down; queued read exceptions are not actionable here.
        }

        _readerTask = null;
        _readerCancellation?.Dispose();
        _readerCancellation = null;
        _stream?.Dispose();
        _stream = null;

        lock (_responseLock)
        {
            _responseQueue.Clear();
            _pendingResponseMessageIds.Clear();
        }
    }

    public byte[] Write(byte[] data, bool expectResponse)
    {
        if (_stream is null)
        {
            throw new DeviceTransportException(DeviceTransportError.OpenFailed, "Device is not open.");
        }

        var messageId = data.Length > 3 ? data[3] : (byte)0;
        if (expectResponse)
        {
            lock (_responseLock)
            {
                _pendingResponseMessageIds.Add(messageId);
            }
        }

        try
        {
            lock (_writeLock)
            {
                foreach (var report in ToOutputReports(data))
                {
                    _stream.Write(report);
                }
            }

            if (!expectResponse)
            {
                Thread.Sleep(2);
                return [];
            }

            Thread.Sleep(200);
            return WaitForResponse(messageId);
        }
        catch (TimeoutException exception)
        {
            throw new DeviceTransportException(DeviceTransportError.WriteFailed, exception.Message, exception);
        }
        catch (IOException exception)
        {
            throw new DeviceTransportException(DeviceTransportError.WriteFailed, exception.Message, exception);
        }
        finally
        {
            if (expectResponse)
            {
                lock (_responseLock)
                {
                    _pendingResponseMessageIds.Remove(messageId);
                }
            }
        }
    }

    public void Dispose()
    {
        Close();
    }

    private void StartReader()
    {
        _readerCancellation = new CancellationTokenSource();
        var token = _readerCancellation.Token;
        _readerTask = Task.Run(() => ReadLoop(token), token);
    }

    private void ReadLoop(CancellationToken token)
    {
        var buffer = new byte[_inputReportLength];
        while (!token.IsCancellationRequested)
        {
            try
            {
                if (_stream is null)
                {
                    return;
                }

                var count = _stream.Read(buffer);
                if (count > 0)
                {
                    RouteInput(buffer.AsSpan(0, count).ToArray());
                }
            }
            catch (TimeoutException)
            {
            }
            catch (IOException) when (token.IsCancellationRequested)
            {
                return;
            }
            catch (ObjectDisposedException)
            {
                return;
            }
            catch
            {
                Thread.Sleep(100);
            }
        }
    }

    private IEnumerable<byte[]> ToOutputReports(byte[] data)
    {
        var payloadSize = Math.Max(_outputReportLength - 1, 1);
        for (var offset = 0; offset < data.Length; offset += payloadSize)
        {
            var report = new byte[_outputReportLength];
            var count = Math.Min(payloadSize, data.Length - offset);
            Buffer.BlockCopy(data, offset, report, 1, count);
            yield return report;
        }
    }

    private byte[] WaitForResponse(byte messageId)
    {
        var deadline = DateTimeOffset.UtcNow.AddSeconds(1);
        while (DateTimeOffset.UtcNow < deadline)
        {
            lock (_responseLock)
            {
                var index = _responseQueue.FindIndex(packet => TransportPacket.MessageId(packet) == messageId);
                if (index >= 0)
                {
                    var response = _responseQueue[index];
                    _responseQueue.RemoveAt(index);
                    return TransportPacket.Normalize(response);
                }
            }

            Thread.Sleep(10);
        }

        throw new DeviceTransportException(DeviceTransportError.ReadTimeout);
    }

    private void RouteInput(byte[] data)
    {
        var packet = TransportPacket.Normalize(data);
        if (packet.Length >= 5 && packet[4] == (byte)RobobloqAction.StatusNotification)
        {
            UnsolicitedInputHandler?.Invoke(data);
            return;
        }

        var messageId = TransportPacket.MessageId(data);
        lock (_responseLock)
        {
            if (messageId is not null && _pendingResponseMessageIds.Contains(messageId.Value))
            {
                _responseQueue.Add(data);
                return;
            }
        }

        UnsolicitedInputHandler?.Invoke(data);
    }
}
