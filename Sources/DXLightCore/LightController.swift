import Foundation

public enum ConnectionStatus: Equatable {
    case searching
    case connected(DiscoveredDevice)
    case error(String)
}

@MainActor
public final class LightController: ObservableObject {
    @Published public private(set) var status: ConnectionStatus = .searching
    @Published public private(set) var isBusy = false
    @Published public var isOn: Bool
    @Published public var brightness: Double
    @Published public var color: RGBColor

    private let defaults: UserDefaults
    private var deviceInfo: DeviceInfo?
    private var pollTask: Task<Void, Never>?
    private var connectedDevice: DiscoveredDevice?
    private var brightnessDebounceTask: Task<Void, Never>?
    private var brightnessApplyTask: Task<Void, Never>?
    private var scheduledBrightness: Double?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isOn = defaults.bool(forKey: Keys.isOn)
        self.brightness = defaults.object(forKey: Keys.brightness) as? Double ?? 0.5
        if let data = defaults.data(forKey: Keys.color),
           let saved = try? JSONDecoder().decode(RGBColor.self, from: data) {
            self.color = saved
        } else {
            self.color = .warmWhite
        }
    }

    public func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        brightnessDebounceTask?.cancel()
        brightnessApplyTask?.cancel()
        scheduledBrightness = nil
    }

    public func setPower(_ enabled: Bool) async {
        guard isOn != enabled else { return }
        isOn = enabled
        persistState()
        await applyPowerState()
    }

    public func requestSetPower(_ enabled: Bool) {
        guard isOn != enabled else { return }
        isOn = enabled
        persistState()
        Task { await applyPowerState() }
    }

    public func togglePower() async {
        await setPower(!isOn)
    }

    public func setBrightness(_ value: Double) {
        let clamped = min(max(value, 0.0), 1.0)
        brightness = clamped
        persistState()
        guard isOn else { return }

        scheduledBrightness = clamped
        brightnessDebounceTask?.cancel()
        brightnessDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await self?.processBrightnessQueue()
        }
    }

    public func refreshConnection() async {
        await refreshDevicePresence(force: true)
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refreshDevicePresence(force: false)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func refreshDevicePresence(force: Bool) async {
        if !force,
           connectedDevice != nil,
           case .connected = status,
           DeviceDiscovery.discoverPreferred() != nil {
            return
        }

        if connectedDevice == nil || force {
            status = .searching
        }

        guard let discovered = DeviceDiscovery.discoverPreferred() else {
            connectedDevice = nil
            deviceInfo = nil
            status = .error(DeviceTransportError.deviceNotFound.localizedDescription)
            return
        }

        connectedDevice = discovered
        deviceInfo = RobobloqDeviceSession.defaultDeviceInfo()
        status = .connected(discovered)
    }

    private func applyPowerState() async {
        isBusy = true
        defer { isBusy = false }

        let device = connectedDevice
        let targetOn = isOn
        let brightness = brightness
        let color = color
        let lampsAmount = deviceInfo?.lampsAmount ?? RobobloqDeviceSession.defaultLampsAmount

        do {
            let info = try await DeviceCommandRunner.withTransport(device: device) { transport, info in
                if targetOn {
                    try RobobloqDeviceSession.turnOn(
                        using: transport,
                        lampsAmount: lampsAmount,
                        color: color,
                        brightness: brightness
                    )
                } else {
                    try RobobloqDeviceSession.turnOff(using: transport, lampsAmount: lampsAmount)
                }
                return info
            }
            deviceInfo = info
        } catch {
            status = .error(error.localizedDescription)
            connectedDevice = nil
        }
    }

    private func processBrightnessQueue() async {
        guard isOn, let target = scheduledBrightness else { return }

        if brightnessApplyTask != nil {
            return
        }

        brightnessApplyTask = Task { [weak self] in
            defer { self?.brightnessApplyTask = nil }
            await self?.drainBrightnessQueue(startingAt: target)
        }

        await brightnessApplyTask?.value
    }

    private func drainBrightnessQueue(startingAt initialTarget: Double) async {
        var target = initialTarget

        while !Task.isCancelled, isOn {
            await sendBrightness(to: target)

            guard !Task.isCancelled, isOn else { return }
            guard let pending = scheduledBrightness else { return }
            guard abs(pending - target) > 0.001 else { return }

            target = pending
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func sendBrightness(to value: Double) async {
        let device = connectedDevice
        let color = color
        let lampsAmount = deviceInfo?.lampsAmount ?? RobobloqDeviceSession.defaultLampsAmount

        isBusy = true
        defer { isBusy = false }

        for attempt in 0..<3 {
            if Task.isCancelled { return }

            do {
                try await DeviceCommandRunner.withTransport(device: device, settleDelay: 0.05) { transport, _ in
                    try RobobloqDeviceSession.applyBrightness(
                        value,
                        color: color,
                        lampsAmount: lampsAmount,
                        using: transport
                    )
                }
                return
            } catch {
                if Task.isCancelled { return }
                guard attempt < 2, shouldRetryBrightness(error) else { return }
                try? await Task.sleep(nanoseconds: UInt64(150_000_000 * (attempt + 1)))
            }
        }
    }

    private func shouldRetryBrightness(_ error: Error) -> Bool {
        if case DeviceTransportError.deviceBusy = error {
            return true
        }
        if case DeviceTransportError.openFailed = error {
            return true
        }
        if case DeviceTransportError.writeFailed = error {
            return true
        }
        return false
    }

    private func persistState() {
        defaults.set(isOn, forKey: Keys.isOn)
        defaults.set(brightness, forKey: Keys.brightness)
        if let data = try? JSONEncoder().encode(color) {
            defaults.set(data, forKey: Keys.color)
        }
    }

    private enum Keys {
        static let isOn = "dxlight.isOn"
        static let brightness = "dxlight.brightness"
        static let color = "dxlight.color"
    }
}
