import DXLightCore
import Foundation

@main
struct DXLightCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            exit(1)
        }

        do {
            switch command {
            case "list":
                try runList()
            case "info":
                try runInfo()
            case "off":
                try runOff()
            case "on":
                let brightness = Double(arguments.dropFirst().first ?? "0.5") ?? 0.5
                try runOn(brightness: brightness)
            case "brightness":
                guard let value = Double(arguments.dropFirst().first ?? "") else {
                    fputs("Usage: dx-light-cli brightness <0-1.0>\n", stderr)
                    exit(1)
                }
                try runBrightness(value)
            case "test":
                try runTest()
            case "sniff":
                try runSniff()
            case "probe":
                try runProbe()
            case "state":
                try runState()
            case "debug-button":
                let logPath = arguments.dropFirst().first
                    ?? "/tmp/dx-light-button-debug.log"
                try ButtonDebug.run(logPath: logPath)
            default:
                printUsage()
                exit(1)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runList() throws {
        let devices = RobobloqDeviceSession.listDevices()
        if devices.isEmpty {
            print("No DX Light devices found.")
            return
        }

        for device in devices {
            print("\(device.kind.rawValue)\t\(device.path)\t\(String(format: "0x%04X", device.vendorID))/\(String(format: "0x%04X", device.productID))\t\(device.displayName)")
        }
    }

    private static func runInfo() throws {
        try RobobloqDeviceSession.withTransport { _, info in
            if info.id == "unknown" {
                print("Device info read is unavailable on this HID interface.")
                print("Using defaults for control commands.")
            }
            print("ID: \(info.id)")
            print("UUID: \(info.uuid)")
            print("Version: \(info.version)")
            print("Lamps: \(info.lampsAmount)")
            print("Display size: \(info.displaySize)")
        }
    }

    private static func runOff() throws {
        try RobobloqDeviceSession.withTransport { transport, info in
            try RobobloqDeviceSession.turnOff(using: transport, lampsAmount: info.lampsAmount)
            print("Light turned off.")
        }
    }

    private static func runOn(brightness: Double) throws {
        try RobobloqDeviceSession.withTransport { transport, info in
            try RobobloqDeviceSession.turnOn(using: transport, lampsAmount: info.lampsAmount, brightness: brightness)
            print("Light turned on at \(Int(brightness * 100))%.")
        }
    }

    private static func runBrightness(_ value: Double) throws {
        try RobobloqDeviceSession.withTransport { transport, info in
            try RobobloqDeviceSession.applyBrightness(
                value,
                color: .warmWhite,
                lampsAmount: info.lampsAmount,
                using: transport
            )
            print("Brightness set to \(Int(value * 100))%.")
        }
    }

    private static func runTest() throws {
        print("Running off → on → brightness 50% → off test...")
        try RobobloqDeviceSession.withTransport { transport, info in
            print("Connected: \(info.version), \(info.lampsAmount) lamps")
            try RobobloqDeviceSession.turnOff(using: transport, lampsAmount: info.lampsAmount)
            print("Off")
            Thread.sleep(forTimeInterval: 0.5)
            try RobobloqDeviceSession.turnOn(using: transport, lampsAmount: info.lampsAmount, brightness: 0.5)
            print("On at 50%")
            Thread.sleep(forTimeInterval: 0.5)
            try RobobloqDeviceSession.applyBrightness(
                0.25,
                color: .warmWhite,
                lampsAmount: info.lampsAmount,
                using: transport
            )
            print("Brightness 25%")
            Thread.sleep(forTimeInterval: 0.5)
            try RobobloqDeviceSession.turnOff(using: transport, lampsAmount: info.lampsAmount)
            print("Off")
        }
        print("Test complete.")
    }

    private static func runState() throws {
        try RobobloqDeviceSession.withTransport { transport, _ in
            guard let packet = RobobloqDeviceSession.queryDeviceState(using: transport) else {
                print("No state response.")
                return
            }
            let hex = [UInt8](packet).map { String(format: "%02x", $0) }.joined(separator: " ")
            print(hex)
            if let power = RobobloqProtocol.parsePowerState(from: packet) {
                print("power: \(power ? "on" : "off")")
            } else {
                print("power: unknown")
            }
        }
    }

    private static func runProbe() throws {
        try RobobloqDeviceSession.withTransport { transport, _ in
            var baseline: [UInt8]?
            print("Polling readDeviceInfo every 500ms. Toggle the physical button. Ctrl+C to stop.")
            while true {
                guard let packet = RobobloqDeviceSession.queryDeviceState(using: transport) else {
                    print("read timeout")
                    Thread.sleep(forTimeInterval: 0.5)
                    continue
                }
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
                        print("changed \(diffs.joined(separator: ", ")) | \(hex)")
                    }
                } else {
                    print("baseline: \(hex)")
                    baseline = bytes
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    private static func runSniff() throws {
        guard let device = DeviceDiscovery.discoverPreferred() else {
            throw DeviceTransportError.deviceNotFound
        }

        print("Listening for device reports on \(device.kind.rawValue). Press the strip button. Ctrl+C to stop.")
        let transport = DeviceDiscovery.makeTransport(for: device)
        transport.unsolicitedInputHandler = { data in
            let hex = [UInt8](data).map { String(format: "%02x", $0) }.joined(separator: " ")
            if let event = RobobloqProtocol.parseDeviceEvent(from: data) {
                print("report: \(hex) -> \(event)")
            } else {
                print("report: \(hex)")
            }
        }
        try transport.open()
        defer { transport.close() }

        while true {
            Thread.sleep(forTimeInterval: 1)
        }
    }

    private static func printUsage() {
        print("""
        dx-light-cli commands:
          list
          info
          on [brightness 0-1.0]
          off
          brightness <0-1.0>
          test
          sniff
          probe
          state
          debug-button [log-path]
        """)
    }
}
