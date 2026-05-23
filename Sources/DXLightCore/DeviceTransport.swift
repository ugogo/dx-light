import Foundation

public enum TransportKind: String, Codable, Sendable {
    case hid
    case serial
}

public struct DiscoveredDevice: Equatable, Sendable {
    public let kind: TransportKind
    public let path: String
    public let vendorID: Int
    public let productID: Int
    public let manufacturer: String?
    public let product: String?

    public init(
        kind: TransportKind,
        path: String,
        vendorID: Int,
        productID: Int,
        manufacturer: String?,
        product: String?
    ) {
        self.kind = kind
        self.path = path
        self.vendorID = vendorID
        self.productID = productID
        self.manufacturer = manufacturer
        self.product = product
    }

    public var displayName: String {
        product ?? manufacturer ?? path
    }
}

public enum DeviceTransportError: LocalizedError {
    case deviceNotFound
    case openFailed(String)
    case writeFailed(String)
    case readTimeout
    case deviceBusy
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "DX Light strip not found. Check the USB connection and close any other DX Light app."
        case .openFailed(let detail):
            return "Failed to open device: \(detail)"
        case .writeFailed(let detail):
            return "Failed to write to device: \(detail)"
        case .readTimeout:
            return "Timed out waiting for a device response."
        case .deviceBusy:
            return "Device is busy. Close any other app using the strip and try again."
        case .invalidResponse:
            return "Received an invalid response from the device."
        }
    }
}

public protocol DeviceTransport: AnyObject {
    var device: DiscoveredDevice { get }
    var unsolicitedInputHandler: ((Data) -> Void)? { get set }
    func open() throws
    func close()
    func write(_ data: Data, expectResponse: Bool) throws -> Data
}

public extension DeviceTransport {
    func writeWithoutResponse(_ data: Data) throws {
        _ = try write(data, expectResponse: false)
    }

    func writeWithResponse(_ data: Data) throws -> Data {
        try write(data, expectResponse: true)
    }
}
