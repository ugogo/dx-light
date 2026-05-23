import XCTest
@testable import DXLightCore

final class RobobloqProtocolTests: XCTestCase {
    func testTransportPacketNormalizeRemovesHIDReportPrefix() {
        let normalized = TransportPacket.normalize(Data([0x00, 0x52, 0x42, 0x06, 0x11, 0x82, 0x2D]))

        XCTAssertEqual([UInt8](normalized), [0x52, 0x42, 0x06, 0x11, 0x82, 0x2D])
        XCTAssertEqual(TransportPacket.messageID(in: normalized), 0x11)
    }

    func testParseDeviceInfoFromReadResponse() {
        let response = Data([
            0x52, 0x42, 0x18, 0x01, 0x82,
            0xAA, 0xBB, 0xCC,
            0x10, 0x00, 0x00, 0x32,
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x00, 0x01, 0x02, 0x03,
        ])

        let info = RobobloqProtocol.parseDeviceInfo(from: response)

        XCTAssertEqual(info?.id, "aabbcc")
        XCTAssertEqual(info?.uuid, "0102030405060708")
        XCTAssertEqual(info?.displaySize, 16)
        XCTAssertEqual(info?.lampsAmount, 50)
        XCTAssertEqual(info?.version, "1.2.3")
    }

    func testParseDeviceEventAcceptsStatusNotificationOnly() {
        XCTAssertEqual(
            RobobloqProtocol.parseDeviceEvent(from: statusNotification(powerByte: 1)),
            .powerOn
        )
        XCTAssertEqual(
            RobobloqProtocol.parseDeviceEvent(from: statusNotification(powerByte: 0)),
            .powerOff
        )

        XCTAssertNil(RobobloqProtocol.parseDeviceEvent(from: RobobloqProtocol.turnOffLight()))
        XCTAssertNil(RobobloqProtocol.parseDeviceEvent(from: RobobloqProtocol.setBrightness(128)))
        XCTAssertNil(
            RobobloqProtocol.parseDeviceEvent(
                from: RobobloqProtocol.setSectionLED(
                    segments: RobobloqProtocol.sectionPayload(color: .warmWhite, lampsAmount: 254)
                )
            )
        )
    }

    func testParsePowerStateFromReadResponse() {
        var off = readResponse(powerByte: 0, brightnessByte: 5)
        var on = readResponse(powerByte: 1, brightnessByte: 128)
        var inferredOff = readResponse(powerByte: 9, brightnessByte: 5)
        var inferredOn = readResponse(powerByte: 9, brightnessByte: 6)

        XCTAssertEqual(RobobloqProtocol.parsePowerState(from: off), false)
        XCTAssertEqual(RobobloqProtocol.parsePowerState(from: on), true)
        XCTAssertEqual(RobobloqProtocol.parsePowerState(from: inferredOff), false)
        XCTAssertEqual(RobobloqProtocol.parsePowerState(from: inferredOn), true)

        off[0] = 0x00
        on[1] = 0x00
        inferredOff = Data([0x52, 0x42, 0x01])
        inferredOn[10] = 4

        XCTAssertNil(RobobloqProtocol.parsePowerState(from: off))
        XCTAssertNil(RobobloqProtocol.parsePowerState(from: on))
        XCTAssertNil(RobobloqProtocol.parsePowerState(from: inferredOff))
        XCTAssertEqual(RobobloqProtocol.parsePowerState(from: inferredOn), false)
    }

    func testDeviceRawBrightnessIsClampedToSupportedRange() {
        XCTAssertEqual(RobobloqDeviceSession.deviceRawBrightness(fromUIValue: -1), 5)
        XCTAssertEqual(RobobloqDeviceSession.deviceRawBrightness(fromUIValue: 0), 5)
        XCTAssertEqual(RobobloqDeviceSession.deviceRawBrightness(fromUIValue: 1), 255)
    }

    private func statusNotification(powerByte: UInt8) -> Data {
        Data([0x52, 0x42, 0x09, 0x01, RobobloqAction.statusNotification.rawValue, 0, 0, 0, powerByte, 0])
    }

    private func readResponse(powerByte: UInt8, brightnessByte: UInt8) -> Data {
        Data([0x52, 0x42, 0x0C, 0x01, RobobloqAction.readDeviceInfo.rawValue, 0, 0, 0, 0, powerByte, brightnessByte, 0])
    }
}
