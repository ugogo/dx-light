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

    private static func printUsage() {
        print("""
        dx-light-cli commands:
          list
          info
          on [brightness 0-1.0]
          off
          brightness <0-1.0>
          test
        """)
    }
}
