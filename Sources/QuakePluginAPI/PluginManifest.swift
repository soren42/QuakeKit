import Foundation

public struct PluginManifest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var apiVersion: String
    public var entry: PluginEntry
    public var capabilities: [PluginCapability]
    public var permissions: [PluginPermission]
    public var actions: [PluginAction]
    public var dataStreams: [PluginDataStream]
    public var views: [PluginView]

    public init(
        id: String,
        name: String,
        version: String,
        apiVersion: String = PluginManifestValidator.currentAPIVersion,
        entry: PluginEntry,
        capabilities: [PluginCapability] = [],
        permissions: [PluginPermission] = [],
        actions: [PluginAction] = [],
        dataStreams: [PluginDataStream] = [],
        views: [PluginView] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.apiVersion = apiVersion
        self.entry = entry
        self.capabilities = capabilities
        self.permissions = permissions
        self.actions = actions
        self.dataStreams = dataStreams
        self.views = views
    }
}

public struct PluginEntry: Codable, Equatable, Sendable {
    public enum Transport: String, Codable, Sendable {
        case stdioJSONRPC
        case websocket
        case nativeSwift
        case webView
        case shell
        case php
    }

    public var transport: Transport
    public var command: String?
    public var arguments: [String]
    public var url: URL?

    public init(transport: Transport, command: String? = nil, arguments: [String] = [], url: URL? = nil) {
        self.transport = transport
        self.command = command
        self.arguments = arguments
        self.url = url
    }
}

public enum PluginCapability: String, Codable, Equatable, Sendable {
    case settings
    case eventPublisher
    case eventSubscriber
    case dataProvider
    case actionProvider
    case viewProvider
    case deviceProvider
    case backgroundWorker
}

public enum PluginPermission: Codable, Equatable, Sendable {
    case network(hosts: [String])
    case secrets(keys: [String])
    case filesystem(paths: [String], write: Bool)
    case inputSynthesis
    case audioCapture
    case localProcess
}

public struct PluginAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var argumentSchema: [PluginSchemaField]

    public init(id: String, title: String, argumentSchema: [PluginSchemaField] = []) {
        self.id = id
        self.title = title
        self.argumentSchema = argumentSchema
    }
}

public struct PluginDataStream: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var valueSchema: [PluginSchemaField]

    public init(id: String, title: String, valueSchema: [PluginSchemaField] = []) {
        self.id = id
        self.title = title
        self.valueSchema = valueSchema
    }
}

public struct PluginView: Codable, Equatable, Identifiable, Sendable {
    public enum ViewType: String, Codable, Sendable {
        case native
        case webCanvas
        case webDocument
        case text
        case dataDriven
    }

    public enum Presentation: String, Codable, Sendable {
        case page
        case widget
        case pageAndWidget
    }

    public var id: String
    public var title: String
    public var type: ViewType?
    public var presentation: Presentation?
    public var entryPath: String?
    public var dataStreamID: String?
    public var columnSpan: Int?
    public var rowSpan: Int?
    public var preferredWidth: Int?
    public var preferredHeight: Int?

    public init(
        id: String,
        title: String,
        type: ViewType? = nil,
        presentation: Presentation? = nil,
        entryPath: String? = nil,
        dataStreamID: String? = nil,
        columnSpan: Int? = nil,
        rowSpan: Int? = nil,
        preferredWidth: Int? = nil,
        preferredHeight: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.presentation = presentation
        self.entryPath = entryPath
        self.dataStreamID = dataStreamID
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
    }
}

public struct PluginSchemaField: Codable, Equatable, Identifiable, Sendable {
    public enum ValueType: String, Codable, Sendable {
        case string
        case integer
        case number
        case boolean
        case url
        case secret
    }

    public var id: String
    public var title: String
    public var type: ValueType
    public var required: Bool
    public var defaultValue: JSONValue?

    public init(id: String, title: String, type: ValueType, required: Bool = false, defaultValue: JSONValue? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
    }
}
