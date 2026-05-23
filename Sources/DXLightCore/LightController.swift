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
    @Published public var smoothTransitions: Bool
    @Published public var turnOnWhenUSBConnects: Bool
    @Published public private(set) var savedPreset: ColorPreset?

    private let defaults: UserDefaults
    private var deviceInfo: DeviceInfo?
    private var pollTask: Task<Void, Never>?
    private var connectedDevice: DiscoveredDevice?
    private var brightnessDebounceTask: Task<Void, Never>?
    private var brightnessApplyTask: Task<Void, Never>?
    private var scheduledBrightness: Double?
    private var colorDebounceTask: Task<Void, Never>?
    private var appliedBrightness: Double
    private var appliedColor: RGBColor

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isOn = defaults.bool(forKey: Keys.isOn)
        let initialBrightness = defaults.object(forKey: Keys.brightness) as? Double ?? 0.5
        self.brightness = initialBrightness
        let initialColor: RGBColor
        if let data = defaults.data(forKey: Keys.color),
           let saved = try? JSONDecoder().decode(RGBColor.self, from: data) {
            initialColor = saved
        } else {
            initialColor = .warmWhite
        }
        self.color = initialColor
        self.smoothTransitions = defaults.object(forKey: Keys.smoothTransitions) as? Bool ?? true
        self.turnOnWhenUSBConnects = defaults.object(forKey: Keys.turnOnWhenUSBConnects) as? Bool ?? true
        self.appliedBrightness = initialBrightness
        self.appliedColor = initialColor
        if let data = defaults.data(forKey: Keys.savedPreset),
           let saved = try? JSONDecoder().decode(ColorPreset.self, from: data) {
            self.savedPreset = saved
        } else {
            self.savedPreset = nil
        }
    }

    public var colorPresets: [ColorPreset] {
        var presets = RGBColor.presets
        if let savedPreset {
            presets.append(savedPreset)
        }
        return presets
    }

    public func saveColorAsPreset(_ colorToSave: RGBColor? = nil) {
        let preset = ColorPreset(name: ColorPreset.savedName, color: colorToSave ?? color)
        savedPreset = preset
        persistState()
    }

    public func setSmoothTransitions(_ enabled: Bool) {
        guard smoothTransitions != enabled else { return }
        smoothTransitions = enabled
        persistState()
    }

    public func setTurnOnWhenUSBConnects(_ enabled: Bool) {
        guard turnOnWhenUSBConnects != enabled else { return }
        turnOnWhenUSBConnects = enabled
        persistState()
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
        colorDebounceTask?.cancel()
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

    public func setColor(_ newColor: RGBColor) {
        guard color != newColor else { return }
        color = newColor
        persistState()
        guard isOn else { return }

        colorDebounceTask?.cancel()
        colorDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await self?.sendColor()
        }
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
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func refreshDevicePresence(force: Bool) async {
        let wasConnected: Bool
        if case .connected = status {
            wasConnected = true
        } else {
            wasConnected = false
        }

        guard let discovered = DeviceDiscovery.discoverPreferred() else {
            connectedDevice = nil
            deviceInfo = nil
            status = .error(DeviceTransportError.deviceNotFound.localizedDescription)
            return
        }

        if !force,
           connectedDevice == discovered,
           case .connected = status {
            status = .connected(discovered)
            return
        }

        if connectedDevice == nil || connectedDevice != discovered || force {
            status = .searching
        }

        connectedDevice = discovered
        deviceInfo = RobobloqDeviceSession.defaultDeviceInfo()
        status = .connected(discovered)

        guard !wasConnected else { return }

        if turnOnWhenUSBConnects {
            if !isOn {
                isOn = true
                persistState()
            }
            await applyPowerState()
        } else if isOn {
            await applyPowerState()
        }
    }

    private func applyPowerState() async {
        isBusy = true
        defer { isBusy = false }

        let device = connectedDevice
        let targetOn = isOn
        let brightness = brightness
        let color = color
        let lampsAmount = deviceInfo?.lampsAmount ?? RobobloqDeviceSession.defaultLampsAmount
        let animated = smoothTransitions
        let fromBrightness = appliedBrightness

        do {
            let info = try await DeviceCommandRunner.withTransport(device: device) { transport, info in
                if targetOn {
                    if animated {
                        try Self.turnOnSmoothly(
                            using: transport,
                            lampsAmount: lampsAmount,
                            color: color,
                            brightness: brightness
                        )
                    } else {
                        try RobobloqDeviceSession.turnOn(
                            using: transport,
                            lampsAmount: lampsAmount,
                            color: color,
                            brightness: brightness
                        )
                    }
                } else {
                    if animated {
                        try Self.turnOffSmoothly(
                            using: transport,
                            lampsAmount: lampsAmount,
                            color: color,
                            fromBrightness: fromBrightness
                        )
                    } else {
                        try RobobloqDeviceSession.turnOff(using: transport, lampsAmount: lampsAmount)
                    }
                }
                return info
            }
            deviceInfo = info
            appliedBrightness = brightness
            appliedColor = color
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

    private func sendColor() async {
        let device = connectedDevice
        let currentColor = color
        let brightness = brightness
        let lampsAmount = deviceInfo?.lampsAmount ?? RobobloqDeviceSession.defaultLampsAmount
        let animated = smoothTransitions
        let fromColor = appliedColor

        isBusy = true
        defer { isBusy = false }

        do {
            try await DeviceCommandRunner.withTransport(device: device, settleDelay: 0.05) { transport, _ in
                if animated {
                    try Self.transitionColor(
                        from: fromColor,
                        to: currentColor,
                        brightness: brightness,
                        lampsAmount: lampsAmount,
                        using: transport
                    )
                } else {
                    try RobobloqDeviceSession.applyBrightness(
                        brightness,
                        color: currentColor,
                        lampsAmount: lampsAmount,
                        using: transport
                    )
                }
            }
            appliedColor = currentColor
            appliedBrightness = brightness
        } catch {
            status = .error(error.localizedDescription)
            connectedDevice = nil
        }
    }

    private func sendBrightness(to value: Double) async {
        let device = connectedDevice
        let color = color
        let lampsAmount = deviceInfo?.lampsAmount ?? RobobloqDeviceSession.defaultLampsAmount
        let animated = smoothTransitions
        let fromBrightness = appliedBrightness

        isBusy = true
        defer { isBusy = false }

        for attempt in 0..<3 {
            if Task.isCancelled { return }

            do {
                try await DeviceCommandRunner.withTransport(device: device, settleDelay: 0.05) { transport, _ in
                    if animated {
                        try Self.transitionBrightness(
                            from: fromBrightness,
                            to: value,
                            color: color,
                            lampsAmount: lampsAmount,
                            using: transport
                        )
                    } else {
                        try RobobloqDeviceSession.applyBrightness(
                            value,
                            color: color,
                            lampsAmount: lampsAmount,
                            using: transport
                        )
                    }
                }
                appliedBrightness = value
                appliedColor = color
                return
            } catch {
                if Task.isCancelled { return }
                guard attempt < 2, shouldRetryBrightness(error) else { return }
                try? await Task.sleep(nanoseconds: UInt64(150_000_000 * (attempt + 1)))
            }
        }
    }

    private static func turnOnSmoothly(
        using transport: any DeviceTransport,
        lampsAmount: Int,
        color: RGBColor,
        brightness: Double
    ) throws {
        let start = minimumUIBrightness
        try RobobloqDeviceSession.applyBrightness(
            start,
            color: color,
            lampsAmount: lampsAmount,
            using: transport
        )
        try transitionBrightness(
            from: start,
            to: brightness,
            color: color,
            lampsAmount: lampsAmount,
            using: transport
        )
    }

    private static func turnOffSmoothly(
        using transport: any DeviceTransport,
        lampsAmount: Int,
        color: RGBColor,
        fromBrightness: Double
    ) throws {
        try transitionBrightness(
            from: fromBrightness,
            to: minimumUIBrightness,
            color: color,
            lampsAmount: lampsAmount,
            using: transport
        )
        try RobobloqDeviceSession.turnOff(using: transport, lampsAmount: lampsAmount)
    }

    private static func transitionBrightness(
        from start: Double,
        to end: Double,
        color: RGBColor,
        lampsAmount: Int,
        using transport: any DeviceTransport
    ) throws {
        guard abs(start - end) > 0.001 else {
            try RobobloqDeviceSession.applyBrightness(end, color: color, lampsAmount: lampsAmount, using: transport)
            return
        }

        for step in 1...transitionSteps {
            let progress = Double(step) / Double(transitionSteps)
            let value = start + ((end - start) * progress)
            try RobobloqDeviceSession.applyBrightness(value, color: color, lampsAmount: lampsAmount, using: transport)
            sleepBetweenTransitionSteps(after: step)
        }
    }

    private static func transitionColor(
        from start: RGBColor,
        to end: RGBColor,
        brightness: Double,
        lampsAmount: Int,
        using transport: any DeviceTransport
    ) throws {
        guard start != end else {
            try RobobloqDeviceSession.applyBrightness(brightness, color: end, lampsAmount: lampsAmount, using: transport)
            return
        }

        for step in 1...transitionSteps {
            let progress = Double(step) / Double(transitionSteps)
            let color = interpolatedColor(from: start, to: end, progress: progress)
            try RobobloqDeviceSession.applyBrightness(brightness, color: color, lampsAmount: lampsAmount, using: transport)
            sleepBetweenTransitionSteps(after: step)
        }
    }

    private static func interpolatedColor(from start: RGBColor, to end: RGBColor, progress: Double) -> RGBColor {
        RGBColor(
            red: interpolatedChannel(from: start.red, to: end.red, progress: progress),
            green: interpolatedChannel(from: start.green, to: end.green, progress: progress),
            blue: interpolatedChannel(from: start.blue, to: end.blue, progress: progress)
        )
    }

    private static func interpolatedChannel(from start: UInt8, to end: UInt8, progress: Double) -> UInt8 {
        let value = Double(start) + ((Double(end) - Double(start)) * progress)
        return UInt8(min(max(Int(value.rounded()), 0), 255))
    }

    private static func sleepBetweenTransitionSteps(after step: Int) {
        guard step < transitionSteps else { return }
        Thread.sleep(forTimeInterval: transitionStepDelay)
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
        defaults.set(smoothTransitions, forKey: Keys.smoothTransitions)
        defaults.set(turnOnWhenUSBConnects, forKey: Keys.turnOnWhenUSBConnects)
        if let savedPreset, let data = try? JSONEncoder().encode(savedPreset) {
            defaults.set(data, forKey: Keys.savedPreset)
        } else {
            defaults.removeObject(forKey: Keys.savedPreset)
        }
    }

    private enum Keys {
        static let isOn = "dxlight.isOn"
        static let brightness = "dxlight.brightness"
        static let color = "dxlight.color"
        static let smoothTransitions = "dxlight.smoothTransitions"
        static let turnOnWhenUSBConnects = "dxlight.turnOnWhenUSBConnects"
        static let savedPreset = "dxlight.savedPreset"
    }

    private static let transitionSteps = 5
    private static let transitionStepDelay: TimeInterval = 0.025
    private static let minimumUIBrightness = Double(RobobloqConstants.minimumBrightness) / Double(RobobloqConstants.maximumBrightness)
}
