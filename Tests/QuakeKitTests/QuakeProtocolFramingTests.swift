import Testing
@testable import QuakeHID

/// Pins the vendor short-command frames to the exact bytes DK-Suite's frame builder
/// produces (`l(163, data, opCode)` in background.js). The device firmware validates
/// the 0xA3 header and a `sum(data) % 255` checksum and silently drops anything else,
/// so a framing regression here means a dark panel with no error anywhere.
struct QuakeProtocolFramingTests {
    @Test func shortCommandLayoutMatchesVendorBuilder() {
        // l(163, [4, 1], 1) → [0xA3, len, opCode, ...data, checksum % 255]
        #expect(QuakeProtocol.shortCommand(opCode: 0x01, data: [0x04, 0x01]) ==
                [0xA3, 0x03, 0x01, 0x04, 0x01, 0x06])
    }

    @Test func pingMatchesDKSuiteKeepAlive() {
        // DK-Suite startKeepAliveProcess sends l(163, [239], 2) every 15 s.
        #expect(QuakeProtocol.ping == [0xA3, 0x02, 0x02, 0xEF, 0xF1])
    }

    @Test func screenOnOffFrames() {
        #expect(QuakeProtocol.screenOn == [0xA3, 0x03, 0x01, 0x04, 0x01, 0x06])
        #expect(QuakeProtocol.screenOff == [0xA3, 0x03, 0x01, 0x04, 0x00, 0x05])
    }

    @Test func checksumIsModulo255NotTruncation() {
        // sum = 0x01 + 0x05 + 0xFF = 261; vendor uses % 255 (= 6), not & 0xFF (= 5).
        #expect(QuakeProtocol.setBrightness(0xFF).last == 6)
    }

    @Test func queryFrames() {
        #expect(QuakeProtocol.queryFirmware == [0xA3, 0x02, 0x02, 0x2E, 0x30])
        #expect(QuakeProtocol.queryMic == [0xA3, 0x02, 0x02, 0x03, 0x05])
        #expect(QuakeProtocol.queryLuminance == [0xA3, 0x02, 0x02, 0x05, 0x07])
    }

    @Test func keepAliveIntervalMatchesVendorGap() {
        // DK-Suite deviceKeepAliveGap is 15 s; the firmware sleeps after ~2 missed pings.
        #expect(QuakeDevice.keepAliveInterval == 15.0)
    }

    @Test func frameChecksumRoundTripsThroughDecoder() {
        // decodeControlReport applies the same header/length rules the firmware does.
        let pong: [UInt8] = [0xA3, 0x02, 0x55, 0xEF, 0xF1]
        #expect(!QuakeProtocol.decodeControlReport(pong).isEmpty)
    }
}
