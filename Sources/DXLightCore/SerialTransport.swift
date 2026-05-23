import Darwin
import Foundation
import IOKit

public final class SerialTransport: DeviceTransport {
    public let device: DiscoveredDevice
    public var unsolicitedInputHandler: ((Data) -> Void)?
    private var fileDescriptor: Int32 = -1
    private var readQueue: [Data] = []
    private let readQueueLock = NSLock()
    private let readerQueue = DispatchQueue(label: "com.dxlight.serial.reader")
    private var readerSource: DispatchSourceRead?
    private let responseDelay: TimeInterval = 0.2
    private var pendingResponseMessageIDs: Set<UInt8> = []

    public init(device: DiscoveredDevice) {
        self.device = device
    }

    deinit {
        close()
    }

    public func open() throws {
        let path = device.path.hasPrefix("/dev/") ? device.path : "/dev/\(device.path)"
        let fd = path.withCString { Darwin.open($0, O_RDWR | O_NOCTTY | O_NONBLOCK) }
        guard fd >= 0 else {
            throw DeviceTransportError.openFailed(String(cString: strerror(errno)))
        }

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else {
            Darwin.close(fd)
            throw DeviceTransportError.openFailed("tcgetattr failed")
        }

        cfmakeraw(&options)
        cfsetspeed(&options, speed_t(B115200))
        options.c_cflag |= UInt(CLOCAL | CREAD)
        options.c_cflag &= ~UInt(PARENB)
        options.c_cflag &= ~UInt(CSTOPB)
        options.c_cflag &= ~UInt(CSIZE)
        options.c_cflag |= UInt(CS8)

        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            Darwin.close(fd)
            throw DeviceTransportError.openFailed("tcsetattr failed")
        }

        fileDescriptor = fd
        startReader()
    }

    public func close() {
        readerSource?.cancel()
        readerSource = nil
        if fileDescriptor >= 0 {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
        }
        readQueueLock.lock()
        readQueue.removeAll()
        readQueueLock.unlock()
    }

    public func write(_ data: Data, expectResponse: Bool) throws -> Data {
        guard fileDescriptor >= 0 else {
            throw DeviceTransportError.openFailed("Serial port is not open")
        }

        let messageID = data.count > 3 ? data[3] : 0
        if expectResponse {
            readQueueLock.lock()
            pendingResponseMessageIDs.insert(messageID)
            readQueueLock.unlock()
        }
        defer {
            if expectResponse {
                readQueueLock.lock()
                pendingResponseMessageIDs.remove(messageID)
                readQueueLock.unlock()
            }
        }

        let written = data.withUnsafeBytes { buffer -> Int in
            Darwin.write(fileDescriptor, buffer.baseAddress, data.count)
        }

        guard written == data.count else {
            throw DeviceTransportError.writeFailed("Wrote \(written) of \(data.count) bytes")
        }

        if !expectResponse {
            Thread.sleep(forTimeInterval: 0.002)
            return Data()
        }

        Thread.sleep(forTimeInterval: responseDelay)
        return try waitForResponse(messageID: messageID)
    }

    private func startReader() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: readerQueue)
        source.setEventHandler { [weak self] in
            self?.drainInput()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            Darwin.close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        source.resume()
        readerSource = source
    }

    private func drainInput() {
        var buffer = [UInt8](repeating: 0, count: 512)
        while true {
            let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
            if count <= 0 { break }
            let chunk = Data(buffer.prefix(count))
            routeInput(chunk)
        }
    }

    private func routeInput(_ data: Data) {
        let messageID = TransportPacket.messageID(in: data)
        readQueueLock.lock()
        let isPendingResponse = messageID.map { pendingResponseMessageIDs.contains($0) } ?? false
        if isPendingResponse {
            readQueue.append(data)
            readQueueLock.unlock()
            return
        }
        readQueueLock.unlock()

        unsolicitedInputHandler?(data)
    }

    private func waitForResponse(messageID: UInt8) throws -> Data {
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            readQueueLock.lock()
            if let index = readQueue.firstIndex(where: { $0.count > 3 && $0[3] == messageID }) {
                let response = readQueue.remove(at: index)
                readQueueLock.unlock()
                return response
            }
            readQueueLock.unlock()
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw DeviceTransportError.readTimeout
    }
}
