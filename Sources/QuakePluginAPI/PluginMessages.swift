import Foundation

public struct PluginRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var method: String
    public var params: JSONValue

    public init(id: UUID = UUID(), method: String, params: JSONValue = .object([:])) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct PluginResponse: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var ok: Bool
    public var result: JSONValue?
    public var error: String?

    public init(id: UUID, ok: Bool, result: JSONValue? = nil, error: String? = nil) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }
}

public struct PluginEvent: Codable, Equatable, Sendable {
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
