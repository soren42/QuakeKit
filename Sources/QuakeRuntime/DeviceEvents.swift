import Foundation

public struct TouchPoint: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case down
        case up
    }

    public var phase: Phase
    public var x: Int
    public var y: Int

    public init(phase: Phase, x: Int, y: Int) {
        self.phase = phase
        self.x = x
        self.y = y
    }
}

public enum KnobEvent: Codable, Equatable, Sendable {
    case rotate(direction: Int)
    case press(index: Int)
    case holdStart
    case holdEnd
}

public enum DeviceStateEvent: Codable, Equatable, Sendable {
    case firmware(name: Int, version: String)
    case mic(enabled: Bool)
    case luminance(Int)
    case pong
    case stateSync(busy: Bool)
    case raw(command: Int, payload: [UInt8])
}

public enum DeviceEvent: Codable, Equatable, Sendable {
    case touch([TouchPoint])
    case knob(KnobEvent)
    case key(row: Int, column: Int, isDown: Bool)
    case state(DeviceStateEvent)
    case connected(interface: String)
    case disconnected(interface: String)
}

public struct RuntimeEvent: Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var source: String
    public var event: DeviceEvent

    public init(id: UUID = UUID(), timestamp: Date = Date(), source: String, event: DeviceEvent) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.event = event
    }
}
