import Foundation

public enum RobobloqAction: UInt8 {
    case setSyncScreen = 128
    case writeDeviceInfo = 129
    case readDeviceInfo = 130
    case readDeviceUUID = 131
    case setSectionLED = 134
    case setLedEffect = 133
    case setBrightness = 135
    case setAutoOff = 137
    case setDynamicSpeed = 138
    case setSoundSensitivity = 139
    case turnOffLight = 151
}

public enum RobobloqConstants {
    public static let lightVendorID: Int = 0x1A86
    public static let lightProductID: Int = 0xFE07
    public static let cdcProductID: Int = 0xFE0C
    public static let header: [UInt8] = [0x52, 0x42] // "RB"
    public static let minimumBrightness: UInt8 = 5
    public static let maximumBrightness: UInt8 = 255
}

public struct RGBColor: Codable, Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let warmWhite = RGBColor(red: 255, green: 200, blue: 150)
    public static let off = RGBColor(red: 0, green: 0, blue: 0)

    public static let warmOrange = RGBColor(red: 255, green: 150, blue: 60)
    public static let lightBlue = RGBColor(red: 140, green: 200, blue: 255)
    public static let softPurple = RGBColor(red: 190, green: 140, blue: 255)
}

public struct ColorPreset: Equatable, Sendable, Codable {
    public let name: String
    public let color: RGBColor

    public init(name: String, color: RGBColor) {
        self.name = name
        self.color = color
    }

    public static let savedName = "Saved"
}

extension RGBColor {
    public static let presets: [ColorPreset] = [
        ColorPreset(name: "Warm Orange", color: .warmOrange),
        ColorPreset(name: "Light Blue", color: .lightBlue),
        ColorPreset(name: "Soft Purple", color: .softPurple),
    ]
}

public struct DeviceInfo: Equatable, Sendable {
    public let id: String
    public let uuid: String
    public let version: String
    public let lampsAmount: Int
    public let displaySize: Int

    public init(id: String, uuid: String, version: String, lampsAmount: Int, displaySize: Int) {
        self.id = id
        self.uuid = uuid
        self.version = version
        self.lampsAmount = lampsAmount
        self.displaySize = displaySize
    }
}

enum MessageIDGenerator {
    static var shared = MessageIDGeneratorState()
}

final class MessageIDGeneratorState {
    private var current: UInt8 = 0

    func next() -> UInt8 {
        current &+= 1
        if current == 0 || current >= 255 {
            current = 1
        }
        return current
    }

    func reset() {
        current = 0
    }
}

public enum RobobloqProtocol {
    public static func checksum(_ bytes: [UInt8]) -> UInt8 {
        UInt8(bytes.reduce(0) { ($0 + Int($1)) % 256 })
    }

    public static func readDeviceInfo() -> Data {
        buildPacket(action: .readDeviceInfo, payload: [])
    }

    public static func readDeviceUUID() -> Data {
        buildPacket(action: .readDeviceUUID, payload: [])
    }

    public static func setBrightness(_ value: UInt8) -> Data {
        let clamped = min(max(value, RobobloqConstants.minimumBrightness), RobobloqConstants.maximumBrightness)
        return buildPacket(action: .setBrightness, payload: [clamped])
    }

    public static func turnOffLight() -> Data {
        buildPacket(action: .turnOffLight, payload: [])
    }

    public static func setSectionLED(segments: [UInt8]) -> Data {
        precondition(segments.count % 5 == 0, "Segment data must be groups of 5 bytes")
        let messageID = MessageIDGenerator.shared.next()
        let length = UInt8(6 + segments.count)
        var bytes: [UInt8] = RobobloqConstants.header + [length, messageID, RobobloqAction.setSectionLED.rawValue]
        bytes.append(contentsOf: segments)
        bytes.append(checksum(bytes))
        return Data(bytes)
    }

    public static func sectionPayload(color: RGBColor, lampsAmount: Int) -> [UInt8] {
        if lampsAmount > 1 && lampsAmount < 254 {
            let boundary = UInt8(lampsAmount)
            return [
                1, color.red, color.green, color.blue, boundary,
                boundary &+ 1, color.red, color.green, color.blue, 254,
            ]
        }
        return [1, color.red, color.green, color.blue, 254]
    }

    public static func parseDeviceInfo(from response: Data) -> DeviceInfo? {
        let packet = HIDTransport.normalizedPacket(response)
        guard packet.count >= 24 else { return nil }
        let bytes = [UInt8](packet)
        guard bytes[0] == 0x52, bytes[1] == 0x42 else { return nil }

        let id = packet.subdata(in: 5..<8).map { String(format: "%02x", $0) }.joined()
        let uuid = packet.subdata(in: 12..<20).map { String(format: "%02x", $0) }.joined()
        let displaySize = Int(bytes[8])
        let lampsAmount = Int(bytes[11])
        let version = [bytes[21], bytes[22], bytes[23]].map(String.init).joined(separator: ".")

        return DeviceInfo(
            id: id,
            uuid: uuid,
            version: version,
            lampsAmount: lampsAmount,
            displaySize: displaySize
        )
    }

    private static func buildPacket(action: RobobloqAction, payload: [UInt8]) -> Data {
        let messageID = MessageIDGenerator.shared.next()
        let length = UInt8(6 + payload.count)
        var bytes: [UInt8] = RobobloqConstants.header + [length, messageID, action.rawValue]
        bytes.append(contentsOf: payload)
        bytes.append(checksum(bytes))
        return Data(bytes)
    }
}
