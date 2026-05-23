import XCTest
@testable import DXLightCore

@MainActor
final class LightControllerTests: XCTestCase {
    func testInitialStateLoadsPersistedValues() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "dxlight.isOn")
        defaults.set(0.42, forKey: "dxlight.brightness")
        defaults.set(try JSONEncoder().encode(RGBColor.lightBlue), forKey: "dxlight.color")

        let controller = LightController(defaults: defaults)

        XCTAssertTrue(controller.isOn)
        XCTAssertEqual(controller.brightness, 0.42)
        XCTAssertEqual(controller.color, .lightBlue)
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

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "DXLightCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
