import Foundation
import QuakeRuntime

public enum QuakeInterface: String, Sendable {
    case control
    case touch
}

public struct HIDDeviceSpec: Equatable, Sendable {
    public var vendorID: Int
    public var productID: Int
    public var usagePage: Int?
    public var interface: QuakeInterface

    public init(vendorID: Int, productID: Int, usagePage: Int?, interface: QuakeInterface) {
        self.vendorID = vendorID
        self.productID = productID
        self.usagePage = usagePage
        self.interface = interface
    }
}

public enum QuakeProtocol {
    public static let controlSpecs: [HIDDeviceSpec] = [
        HIDDeviceSpec(vendorID: 0x4158, productID: 0x514B, usagePage: 0xFF60, interface: .control),
        HIDDeviceSpec(vendorID: 0x5012, productID: 0x6817, usagePage: 0xFF60, interface: .control)
    ]

    public static let touchSpecs: [HIDDeviceSpec] = [
        HIDDeviceSpec(vendorID: 0x0712, productID: 0x0010, usagePage: 0xFF73, interface: .touch)
    ]

    public static let supportedSpecs: [HIDDeviceSpec] = controlSpecs + touchSpecs
    public static let relatedSpecs: [HIDDeviceSpec] = supportedSpecs

    public static func classify(vendorID: Int, productID: Int, usagePage: Int?) -> HIDDeviceSpec? {
        if let exact = supportedSpecs.first(where: {
            $0.vendorID == vendorID &&
            $0.productID == productID &&
            ($0.usagePage == nil || $0.usagePage == usagePage)
        }) {
            return exact
        }

        // macOS sometimes reports the touch collection without the same primary usage-page shape
        // node-hid exposes. The VID/PID is unique enough to classify it as touch for our hardware.
        if vendorID == 0x0712 && productID == 0x0010 {
            return touchSpecs[0]
        }

        return nil
    }

    public static func shortCommand(opCode: UInt8, data: [UInt8]) -> [UInt8] {
        var checksum = Int(opCode)
        data.forEach { checksum += Int($0) }
        return [0xA3, UInt8(data.count + 1), opCode] + data + [UInt8(checksum % 0xFF)]
    }

    public static let screenOn = shortCommand(opCode: 0x01, data: [0x04, 0x01])
    public static let screenOff = shortCommand(opCode: 0x01, data: [0x04, 0x00])
    public static let ping = shortCommand(opCode: 0x02, data: [0xEF])
    public static let queryFirmware = shortCommand(opCode: 0x02, data: [0x2E])
    public static let queryMic = shortCommand(opCode: 0x02, data: [0x03])
    public static let queryLuminance = shortCommand(opCode: 0x02, data: [0x05])

    public static func setMic(_ enabled: Bool) -> [UInt8] {
        shortCommand(opCode: 0x01, data: [0x03, enabled ? 1 : 0])
    }

    public static func setBrightness(_ value: UInt8) -> [UInt8] {
        shortCommand(opCode: 0x01, data: [0x05, value])
    }

    public static func setKnobLEDPower(_ enabled: Bool) -> [UInt8] {
        shortCommand(opCode: 0x01, data: [0x06, enabled ? 0 : 1])
    }

    public static func viaSet(field: UInt8, values: [UInt8], channel: UInt8 = 3) -> [UInt8] {
        var report = Array(repeating: UInt8(0), count: 33)
        report[0] = 0x00
        report[1] = 0x07
        report[2] = channel
        report[3] = field
        for (index, value) in values.prefix(29).enumerated() {
            report[4 + index] = value
        }
        return report
    }

    public static func viaSaveLighting() -> [UInt8] {
        var report = Array(repeating: UInt8(0), count: 33)
        report[0] = 0x00
        report[1] = 0x09
        return report
    }

    public static func decodeControlReport(_ bytes: [UInt8]) -> [DeviceEvent] {
        guard let first = bytes.first else { return [] }
        if first == 0x01 {
            for index in 0..<15 where bytes.indices.contains(4 + index) && bytes[4 + index] == 0x01 {
                return [.key(row: index / 5 + 1, column: index % 5 + 1, isDown: true)]
            }
            return [.key(row: 0, column: 0, isDown: false)]
        }

        guard first == 0xA3, bytes.count >= 4 else { return [] }
        let length = Int(bytes[1])
        let opCode = bytes[2]
        let command = bytes[3]
        let payloadCount = max(0, length - 2)
        let payloadEnd = min(bytes.count, 4 + payloadCount)
        let payload = Array(bytes[4..<payloadEnd])

        if opCode == 0x03 {
            if command == 0x01, let rawDirection = payload.first {
                return [.knob(.rotate(direction: rawDirection == 1 ? 1 : -1))]
            }
            if command == 0x02, let index = payload.first {
                if index == 0x05 { return [.knob(.holdStart)] }
                if index == 0xFF { return [.knob(.holdEnd)] }
                return [.knob(.press(index: Int(index)))]
            }
        }

        if opCode == 0x55 {
            switch command {
            case 0x2E where payload.count >= 4:
                return [.state(.firmware(name: Int(payload[0]), version: "\(payload[1]).\(payload[2]).\(payload[3])"))]
            case 0x03 where payload.count >= 1:
                return [.state(.mic(enabled: payload[0] == 1))]
            case 0x05 where payload.count >= 1:
                return [.state(.luminance(Int(payload[0])))]
            case 0xEF:
                return [.state(.pong)]
            case 0x00 where payload.count >= 1:
                return [.state(.stateSync(busy: payload[0] == 0x90))]
            default:
                return [.state(.raw(command: Int(command), payload: payload))]
            }
        }

        return []
    }

    public static func decodeTouchReport(_ bytes: [UInt8]) -> [DeviceEvent] {
        guard bytes.count >= 5, bytes[0] == 0xA3, bytes[3] == 0x1A else { return [] }
        let count = Int(bytes[4])
        var points: [TouchPoint] = []

        for index in 0..<count {
            let offset = 5 + 5 * index
            guard bytes.count >= offset + 5 else { break }
            let action = bytes[offset]
            let y = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 1])
            let x = Int(bytes[offset + 4]) << 8 | Int(bytes[offset + 3])
            points.append(TouchPoint(phase: action == 1 ? .down : .up, x: x, y: y))
        }

        return points.isEmpty ? [] : [.touch(points)]
    }
}
