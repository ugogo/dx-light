import Foundation
import IOKit
import IOKit.hid

public enum ButtonDebug {
    public static func run(duration: TimeInterval = 120, logPath: String) throws {
        let logURL = URL(fileURLWithPath: logPath)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }

        func log(_ message: String) {
            let line = "[\(timestamp())] \(message)\n"
            print(line, terminator: "")
            handle.write(Data(line.utf8))
        }

        log("=== DX Light button debug session ===")
        log("Press the PHYSICAL button on the strip now.")
        log("Logging HID reports + readDeviceInfo polling for \(Int(duration))s.")

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            pollDeviceState(log: log, until: Date().addingTimeInterval(duration))
            group.leave()
        }

        try listenAllHIDInterfaces(log: log, duration: duration)
        group.wait()

        log("=== Session complete. Log saved to \(logPath) ===")
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func pollDeviceState(log: @escaping (String) -> Void, until deadline: Date) {
        var baseline: [UInt8]?
        var failures = 0

        while Date() < deadline {
            autoreleasepool {
                do {
                    try RobobloqDeviceSession.withTransport { transport, _ in
                        if let packet = RobobloqDeviceSession.queryDeviceState(using: transport) {
                            failures = 0
                            let bytes = [UInt8](packet)
                            let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                            if let baseline {
                                var diffs: [String] = []
                                for index in 0..<max(baseline.count, bytes.count) {
                                    let old = index < baseline.count ? baseline[index] : 0
                                    let new = index < bytes.count ? bytes[index] : 0
                                    if old != new {
                                        diffs.append("[\(index)] \(old)->\(new)")
                                    }
                                }
                                if !diffs.isEmpty {
                                    log("POLL changed \(diffs.joined(separator: ", ")) | \(hex)")
                                }
                            } else {
                                log("POLL baseline: \(hex)")
                                baseline = bytes
                            }
                        } else {
                            failures += 1
                            if failures == 1 || failures % 5 == 0 {
                                log("POLL readDeviceInfo timeout (#\(failures))")
                            }
                        }
                    }
                } catch {
                    failures += 1
                    if failures == 1 || failures % 5 == 0 {
                        log("POLL error: \(error.localizedDescription)")
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private static func listenAllHIDInterfaces(log: @escaping (String) -> Void, duration: TimeInterval) throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDVendorIDKey: RobobloqConstants.lightVendorID,
                kIOHIDProductIDKey: RobobloqConstants.lightProductID,
            ] as CFDictionary
        )
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw DeviceTransportError.openFailed("Failed to open HID manager")
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !deviceSet.isEmpty else {
            throw DeviceTransportError.deviceNotFound
        }

        let runLoop = CFRunLoopGetCurrent()!
        var sessions: [ButtonDebugListenSession] = []

        for (index, device) in deviceSet.enumerated() {
            let usagePage = Int(IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0)
            let usage = Int(IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int ?? 0)
            let maxInput = max(
                Int(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 8),
                8
            )

            guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
                log("HID iface \(index) FAILED to open (usagePage=\(String(format: "%04x", usagePage)))")
                continue
            }

            let session = ButtonDebugListenSession(
                label: "iface\(index)-page\(String(format: "%04x", usagePage))-usage\(usage)",
                device: device,
                bufferSize: maxInput,
                log: log
            )
            session.start(on: runLoop)
            sessions.append(session)
            log("HID listening on iface \(index): usagePage=\(String(format: "%04x", usagePage)) usage=\(usage) in=\(maxInput)")
        }

        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, duration, false)

        for session in sessions {
            session.stop(on: runLoop)
        }
    }
}

private final class ButtonDebugListenSession {
    let label: String
    let device: IOHIDDevice
    let log: (String) -> Void
    var buffer: [UInt8]
    private var lastReport: [UInt8] = []

    init(label: String, device: IOHIDDevice, bufferSize: Int, log: @escaping (String) -> Void) {
        self.label = label
        self.device = device
        self.log = log
        self.buffer = [UInt8](repeating: 0, count: bufferSize)
    }

    func start(on runLoop: CFRunLoop) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            &buffer,
            buffer.count,
            { context, _, _, _, _, report, length in
                guard let context, length > 0 else { return }
                Unmanaged<ButtonDebugListenSession>.fromOpaque(context).takeUnretainedValue().handle(
                    report: report,
                    length: Int(length)
                )
            },
            context
        )
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
    }

    func stop(on runLoop: CFRunLoop) {
        IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func handle(report: UnsafePointer<UInt8>, length: Int) {
        let bytes = (0..<length).map { report[$0] }
        guard bytes != lastReport else { return }
        lastReport = bytes
        let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        log("HID \(label): \(hex)")
    }
}
