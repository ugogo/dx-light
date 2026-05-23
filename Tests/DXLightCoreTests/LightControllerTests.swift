import XCTest
@testable import DXLightCore

@MainActor
final class LightControllerTests: XCTestCase {
    func testInitialStateLoadsPersistedValues() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "dxlight.isOn")
        defaults.set(0.42, forKey: "dxlight.brightness")
        defaults.set(try JSONEncoder().encode(RGBColor.lightBlue), forKey: "dxlight.color")
        defaults.set(false, forKey: "dxlight.smoothTransitions")
        defaults.set(false, forKey: "dxlight.turnOnWhenUSBConnects")

        let controller = LightController(defaults: defaults)

        XCTAssertTrue(controller.isOn)
        XCTAssertEqual(controller.brightness, 0.42)
        XCTAssertEqual(controller.color, .lightBlue)
        XCTAssertFalse(controller.smoothTransitions)
        XCTAssertFalse(controller.turnOnWhenUSBConnects)
    }

    func testSmoothTransitionsDefaultOnAndPersistChanges() throws {
        let defaults = try makeDefaults()
        let controller = LightController(defaults: defaults)

        XCTAssertTrue(controller.smoothTransitions)

        controller.setSmoothTransitions(false)

        XCTAssertFalse(controller.smoothTransitions)
        XCTAssertFalse(defaults.bool(forKey: "dxlight.smoothTransitions"))
    }

    func testTurnOnWhenUSBConnectsDefaultOnAndPersistChanges() throws {
        let defaults = try makeDefaults()
        let controller = LightController(defaults: defaults)

        XCTAssertTrue(controller.turnOnWhenUSBConnects)

        controller.setTurnOnWhenUSBConnects(false)

        XCTAssertFalse(controller.turnOnWhenUSBConnects)
        XCTAssertFalse(defaults.bool(forKey: "dxlight.turnOnWhenUSBConnects"))
    }

    func testBrightnessIsClampedAndPersistedWhileOff() throws {
        let defaults = try makeDefaults()
        let controller = LightController(defaults: defaults)

        controller.setBrightness(2.0)

        XCTAssertEqual(controller.brightness, 1.0)
        XCTAssertEqual(defaults.double(forKey: "dxlight.brightness"), 1.0)
    }

    func testSaveColorAsPresetPersistsSavedPreset() throws {
        let defaults = try makeDefaults()
        let controller = LightController(defaults: defaults)

        controller.saveColorAsPreset(.softPurple)

        let data = try XCTUnwrap(defaults.data(forKey: "dxlight.savedPreset"))
        let preset = try JSONDecoder().decode(ColorPreset.self, from: data)
        XCTAssertEqual(preset.name, ColorPreset.savedName)
        XCTAssertEqual(preset.color, .softPurple)
        XCTAssertEqual(controller.colorPresets.last, preset)
    }

    func testSystemSleepOffDoesNotChangeBrightnessColorOrPersistPower() async throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "dxlight.isOn")
        defaults.set(0.42, forKey: "dxlight.brightness")
        defaults.set(try JSONEncoder().encode(RGBColor.lightBlue), forKey: "dxlight.color")
        var requests: [PowerCommandRequest] = []
        let controller = LightController(defaults: defaults) { request in
            requests.append(request)
            return RobobloqDeviceSession.defaultDeviceInfo()
        }

        await controller.prepareForSystemSleep()

        XCTAssertTrue(controller.isOn)
        XCTAssertEqual(controller.brightness, 0.42)
        XCTAssertEqual(controller.color, .lightBlue)
        XCTAssertTrue(defaults.bool(forKey: "dxlight.isOn"))
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(requests[0].targetOn)
        XCTAssertFalse(requests[0].animated)
    }

    func testWakeSetsAndPersistsPowerOn() async throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: "dxlight.isOn")
        var requests: [PowerCommandRequest] = []
        let controller = LightController(defaults: defaults) { request in
            requests.append(request)
            return RobobloqDeviceSession.defaultDeviceInfo()
        }

        await controller.restoreAfterSystemWake()

        XCTAssertTrue(controller.isOn)
        XCTAssertTrue(defaults.bool(forKey: "dxlight.isOn"))
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].targetOn)
        XCTAssertTrue(requests[0].animated)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "DXLightCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
