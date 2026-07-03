import Foundation
import QuakePluginAPI

public struct PluginDataKey: Codable, Equatable, Hashable, Sendable {
    public var pluginID: String
    public var streamID: String

    public init(pluginID: String, streamID: String) {
        self.pluginID = pluginID
        self.streamID = streamID
    }
}

public struct PluginDataSnapshot: Codable, Equatable, Sendable {
    public var pluginID: String
    public var streamID: String
    public var timestamp: Date
    public var payload: JSONValue

    public init(pluginID: String, streamID: String, timestamp: Date = Date(), payload: JSONValue) {
        self.pluginID = pluginID
        self.streamID = streamID
        self.timestamp = timestamp
        self.payload = payload
    }
}

public struct PluginDataStore: Sendable {
    private var snapshots: [PluginDataKey: PluginDataSnapshot]

    public init(snapshots: [PluginDataKey: PluginDataSnapshot] = [:]) {
        self.snapshots = snapshots
    }

    public mutating func apply(_ event: PluginEvent) {
        set(pluginID: event.pluginID, streamID: event.streamID, timestamp: event.timestamp, payload: event.payload)
    }

    public mutating func set(pluginID: String, streamID: String, timestamp: Date = Date(), payload: JSONValue) {
        let key = PluginDataKey(pluginID: pluginID, streamID: streamID)
        snapshots[key] = PluginDataSnapshot(pluginID: pluginID, streamID: streamID, timestamp: timestamp, payload: payload)
    }

    public func snapshot(pluginID: String, streamID: String) -> PluginDataSnapshot? {
        snapshots[PluginDataKey(pluginID: pluginID, streamID: streamID)]
    }

    public func snapshots(for pluginID: String) -> [PluginDataSnapshot] {
        snapshots.values
            .filter { $0.pluginID == pluginID }
            .sorted { $0.streamID < $1.streamID }
    }
}
