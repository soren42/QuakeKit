import Foundation
import QuakePluginAPI

public enum KnobRingSemanticState: String, Codable, Equatable, Sendable {
    case idle
    case focus
    case success
    case warning
    case danger
    case progress
}

public enum KnobRingPriority: Int, Codable, Equatable, Comparable, Sendable {
    case idle = 0
    case focus = 20
    case pluginStatus = 40
    case warning = 60
    case danger = 80
    case systemCritical = 100

    public static func < (lhs: KnobRingPriority, rhs: KnobRingPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum KnobRingAnimation: String, Codable, Equatable, Sendable {
    case solid
    case pulse
    case flash
    case strobe
    case progress
    case off
}

public struct KnobRingRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var source: String
    public var state: KnobRingSemanticState
    public var priority: KnobRingPriority
    public var ttl: TimeInterval?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        source: String,
        state: KnobRingSemanticState,
        priority: KnobRingPriority = .pluginStatus,
        ttl: TimeInterval? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.state = state
        self.priority = priority
        self.ttl = ttl
        self.createdAt = createdAt
    }

    public func isExpired(at now: Date = Date()) -> Bool {
        guard let ttl else { return false }
        return now.timeIntervalSince(createdAt) >= ttl
    }
}

public struct KnobRingResolvedOutput: Codable, Equatable, Sendable {
    public var source: String
    public var state: KnobRingSemanticState
    public var color: String
    public var intensity: Double
    public var animation: KnobRingAnimation
    public var priority: KnobRingPriority
    public var expiresAt: Date?

    public init(
        source: String,
        state: KnobRingSemanticState,
        color: String,
        intensity: Double,
        animation: KnobRingAnimation,
        priority: KnobRingPriority,
        expiresAt: Date? = nil
    ) {
        self.source = source
        self.state = state
        self.color = color
        self.intensity = min(1, max(0, intensity))
        self.animation = animation
        self.priority = priority
        self.expiresAt = expiresAt
    }
}

public struct KnobRingCoordinator: Sendable {
    private var requestsBySource: [String: KnobRingRequest]

    public init(requests: [KnobRingRequest] = []) {
        self.requestsBySource = Dictionary(uniqueKeysWithValues: requests.map { ($0.source, $0) })
    }

    public mutating func submit(_ request: KnobRingRequest) {
        requestsBySource[request.source] = request
    }

    public mutating func clear(source: String) {
        requestsBySource.removeValue(forKey: source)
    }

    public mutating func clearAll() {
        requestsBySource.removeAll()
    }

    public mutating func pruneExpired(at now: Date = Date()) {
        requestsBySource = requestsBySource.filter { !$0.value.isExpired(at: now) }
    }

    public mutating func resolve(theme knobRing: ThemeKnobRing?, now: Date = Date()) -> KnobRingResolvedOutput? {
        pruneExpired(at: now)
        guard knobRing?.enabled ?? true else { return nil }

        let winningRequest = requestsBySource.values.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
            return lhs.createdAt > rhs.createdAt
        }.first

        let source = winningRequest?.source ?? "theme"
        let state = winningRequest?.state ?? .idle
        let priority = winningRequest?.priority ?? .idle
        let expiresAt = winningRequest.flatMap { request in
            request.ttl.map { request.createdAt.addingTimeInterval($0) }
        }

        guard let themedState = knobRing?.state(for: state) ?? knobRing?.idle else {
            return nil
        }

        return KnobRingResolvedOutput(
            source: source,
            state: state,
            color: themedState.color,
            intensity: themedState.intensity,
            animation: KnobRingAnimation(themeAnimation: themedState.animation),
            priority: priority,
            expiresAt: expiresAt
        )
    }
}

private extension KnobRingAnimation {
    init(themeAnimation: ThemeKnobRingAnimation) {
        switch themeAnimation {
        case .solid:
            self = .solid
        case .pulse:
            self = .pulse
        case .flash:
            self = .flash
        case .strobe:
            self = .strobe
        case .progress:
            self = .progress
        case .off:
            self = .off
        }
    }
}

public extension ThemeKnobRing {
    func state(for semanticState: KnobRingSemanticState) -> ThemeKnobRingState? {
        switch semanticState {
        case .idle:
            return idle
        case .focus:
            return focus
        case .success:
            return success
        case .warning:
            return warning
        case .danger:
            return danger
        case .progress:
            return progress
        }
    }
}
