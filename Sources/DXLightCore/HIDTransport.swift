import Foundation
import IOKit
import IOKit.hid

public final class HIDTransport: DeviceTransport {
    public let device: DiscoveredDevice
    private var manager: IOHIDManager?
    private var hidDevice: IOHIDDevice?
    private var responseQueue: [Data] = []
    private let responseLock = NSLock()
    private var inputReport = [UInt8](repeating: 0, count: 64)
    private var maxOutputReportSize = 64
    private let responseDelay: TimeInterval = 0.2
    private let runLoopThread = HIDRunLoopThread()

    public init(device: DiscoveredDevice) {
        self.device = device
    }

    deinit {
        close()
    }

    public func open() throws {
        try runLoopThread.perform {
            try self.openOnRunLoopThread()
        }
    }

    public func close() {
        runLoopThread.performIfRunning {
            if let hidDevice = self.hidDevice {
                IOHIDDeviceUnscheduleFromRunLoop(
                    hidDevice,
                    self.runLoopThread.runLoop,
                    CFRunLoopMode.defaultMode.rawValue
                )
                IOHIDDeviceClose(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            self.hidDevice = nil
            self.responseLock.lock()
            self.responseQueue.removeAll()
            self.responseLock.unlock()

            if let manager = self.manager {
                IOHIDManagerUnscheduleFromRunLoop(
                    manager,
                    self.runLoopThread.runLoop,
                    CFRunLoopMode.defaultMode.rawValue
                )
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            self.manager = nil
        }
    }

    public func write(_ data: Data, expectResponse: Bool) throws -> Data {
        try runLoopThread.perform {
            try self.writeOnRunLoopThread(data, expectResponse: expectResponse)
        }
    }

    private func openOnRunLoopThread() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: device.vendorID,
            kIOHIDProductIDKey: device.productID,
        ] as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerScheduleWithRunLoop(
            manager,
            runLoopThread.runLoop,
            CFRunLoopMode.defaultMode.rawValue
        )

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw DeviceTransportError.deviceNotFound
        }

        let candidates = deviceSet.filter { DeviceDiscovery.isVendorLightInterface($0) }
        let selected = candidates.first { DeviceDiscovery.hidPath(for: $0) == device.path }
            ?? candidates.first

        guard let hidDevice = selected else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw DeviceTransportError.deviceNotFound
        }

        let openResult = IOHIDDeviceOpen(hidDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            if openResult == kIOReturnExclusiveAccess {
                throw DeviceTransportError.deviceBusy
            }
            throw DeviceTransportError.openFailed("IOHIDDeviceOpen returned \(openResult)")
        }

        maxOutputReportSize = max(
            Int(IOHIDDeviceGetProperty(hidDevice, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 64),
            64
        )
        inputReport = [UInt8](repeating: 0, count: maxOutputReportSize)

        IOHIDDeviceScheduleWithRunLoop(
            hidDevice,
            runLoopThread.runLoop,
            CFRunLoopMode.defaultMode.rawValue
        )
        installInputCallback(on: hidDevice)

        self.manager = manager
        self.hidDevice = hidDevice
    }

    private func writeOnRunLoopThread(_ data: Data, expectResponse: Bool) throws -> Data {
        guard let hidDevice else {
            throw DeviceTransportError.openFailed("Device is not open")
        }

        let messageID = data.count > 3 ? data[3] : 0
        let chunks = chunk(data: data, size: maxOutputReportSize)

        for chunk in chunks {
            let result = chunk.withUnsafeBytes { buffer -> IOReturn in
                IOHIDDeviceSetReport(
                    hidDevice,
                    kIOHIDReportTypeOutput,
                    0,
                    buffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    chunk.count
                )
            }

            guard result == kIOReturnSuccess else {
                if result == kIOReturnExclusiveAccess {
                    throw DeviceTransportError.deviceBusy
                }
                throw DeviceTransportError.writeFailed("IOHIDDeviceSetReport returned \(result)")
            }
        }

        if !expectResponse {
            Thread.sleep(forTimeInterval: 0.002)
            return Data()
        }

        Thread.sleep(forTimeInterval: responseDelay)
        return try waitForResponse(messageID: messageID)
    }

    private func waitForResponse(messageID: UInt8) throws -> Data {
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            responseLock.lock()
            let response = responseQueue.firstIndex { packet in
                Self.messageID(in: packet) == messageID
            }.map { responseQueue.remove(at: $0) }
            responseLock.unlock()

            if let response {
                return Self.normalizedPacket(response)
            }

            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, true)
        }
        throw DeviceTransportError.readTimeout
    }

    private func installInputCallback(on device: IOHIDDevice) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            &inputReport,
            inputReport.count,
            { context, _, _, _, _, report, reportLength in
                guard let context, reportLength > 0 else { return }
                let transport = Unmanaged<HIDTransport>.fromOpaque(context).takeUnretainedValue()
                let data = Data(bytes: report, count: reportLength)
                transport.responseLock.lock()
                transport.responseQueue.append(data)
                transport.responseLock.unlock()
            },
            context
        )
    }

    private func chunk(data: Data, size: Int) -> [Data] {
        guard data.count > size else { return [data] }
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + size, data.count)
            chunks.append(data.subdata(in: offset..<end))
            offset = end
        }
        return chunks
    }

    static func normalizedPacket(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        if bytes.first == 0x00 {
            bytes.removeFirst()
        }
        return Data(bytes)
    }

    static func messageID(in data: Data) -> UInt8? {
        let packet = normalizedPacket(data)
        guard packet.count > 3 else { return nil }
        return packet[3]
    }
}

private final class HIDRunLoopThread {
    private let queue = DispatchQueue(label: "com.dxlight.hid.runloop")
    private var runLoopStorage: CFRunLoop?
    private let started = DispatchSemaphore(value: 0)

    var runLoop: CFRunLoop {
        guard let runLoopStorage else {
            fatalError("HID run loop not ready")
        }
        return runLoopStorage
    }

    init() {
        queue.async {
            self.runLoopStorage = CFRunLoopGetCurrent()
            self.started.signal()
            CFRunLoopRun()
        }
        started.wait()
    }

    func perform<T>(_ work: @escaping () throws -> T) throws -> T {
        var output: Result<T, Error>?
        let finished = DispatchSemaphore(value: 0)

        queue.async {
            output = Result { try work() }
            finished.signal()
        }

        finished.wait()
        return try output!.get()
    }

    func performIfRunning(_ work: @escaping () -> Void) {
        let finished = DispatchSemaphore(value: 0)
        queue.async {
            work()
            finished.signal()
        }
        finished.wait()
    }
}
