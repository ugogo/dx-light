import Foundation

enum DeviceCommandRunner {
    private static let queue = DispatchQueue(label: "com.dxlight.commands")

    static func run<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func withTransport<T>(
        device: DiscoveredDevice?,
        settleDelay: TimeInterval = 0.5,
        _ body: @escaping (any DeviceTransport, DeviceInfo) throws -> T
    ) async throws -> T {
        try await run {
            guard let discovered = device ?? DeviceDiscovery.discoverPreferred() else {
                throw DeviceTransportError.deviceNotFound
            }

            let transport = DeviceDiscovery.makeTransport(for: discovered)
            try transport.open()
            defer { transport.close() }

            if settleDelay > 0 {
                Thread.sleep(forTimeInterval: settleDelay)
            }
            let info = RobobloqDeviceSession.readDeviceInfo(using: transport)
            return try body(transport, info)
        }
    }
}
