import Foundation

public enum RobobloqDeviceSession {
    public static let defaultLampsAmount = 254

    public static func withTransport<T>(_ body: (any DeviceTransport, DeviceInfo) throws -> T) throws -> T {
        guard let discovered = DeviceDiscovery.discoverPreferred() else {
            throw DeviceTransportError.deviceNotFound
        }

        let transport = DeviceDiscovery.makeTransport(for: discovered)
        try transport.open()
        defer { transport.close() }

        Thread.sleep(forTimeInterval: 0.5)

        let info = readDeviceInfo(using: transport)
        return try body(transport, info)
    }

    public static func listDevices() -> [DiscoveredDevice] {
        DeviceDiscovery.discoverAll()
    }

    public static func readDeviceInfo(using transport: any DeviceTransport) -> DeviceInfo {
        _ = transport
        return defaultDeviceInfo()
    }

    public static func turnOff(using transport: any DeviceTransport, lampsAmount: Int) throws {
        try transport.writeWithoutResponse(RobobloqProtocol.turnOffLight())
        Thread.sleep(forTimeInterval: 0.1)
        try transport.writeWithoutResponse(RobobloqProtocol.turnOffLight())

        let segments = RobobloqProtocol.sectionPayload(color: .off, lampsAmount: lampsAmount)
        try transport.writeWithoutResponse(RobobloqProtocol.setSectionLED(segments: segments))
        Thread.sleep(forTimeInterval: 0.1)
        try transport.writeWithoutResponse(RobobloqProtocol.setSectionLED(segments: segments))
    }

    public static func turnOn(
        using transport: any DeviceTransport,
        lampsAmount: Int,
        color: RGBColor = .warmWhite,
        brightness: Double = 0.5
    ) throws {
        let segments = RobobloqProtocol.sectionPayload(color: color, lampsAmount: lampsAmount)
        try transport.writeWithoutResponse(RobobloqProtocol.setSectionLED(segments: segments))
        Thread.sleep(forTimeInterval: 0.02)
        try transport.writeWithoutResponse(RobobloqProtocol.setSectionLED(segments: segments))
        try setBrightness(brightness, using: transport)
    }

    public static func setBrightness(_ value: Double, using transport: any DeviceTransport) throws {
        let raw = deviceRawBrightness(fromUIValue: value)
        try transport.writeWithoutResponse(RobobloqProtocol.setBrightness(raw))
    }

    public static func deviceRawBrightness(fromUIValue value: Double) -> UInt8 {
        let clamped = min(max(value, 0.0), 1.0)
        let raw = Int((clamped * Double(RobobloqConstants.maximumBrightness)).rounded())
        return UInt8(
            min(
                max(raw, Int(RobobloqConstants.minimumBrightness)),
                Int(RobobloqConstants.maximumBrightness)
            )
        )
    }

    public static func applyBrightness(
        _ value: Double,
        color: RGBColor,
        lampsAmount: Int,
        using transport: any DeviceTransport
    ) throws {
        try setBrightness(value, using: transport)
        Thread.sleep(forTimeInterval: 0.02)
        let segments = RobobloqProtocol.sectionPayload(color: color, lampsAmount: lampsAmount)
        try transport.writeWithoutResponse(RobobloqProtocol.setSectionLED(segments: segments))
    }

    public static func defaultDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            id: "unknown",
            uuid: "unknown",
            version: "unknown",
            lampsAmount: defaultLampsAmount,
            displaySize: 0
        )
    }
}
