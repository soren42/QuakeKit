import Foundation

public struct PluginManifest: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var apiVersion: String
    public var entry: PluginEntry
    public var capabilities: [PluginCapability]
    public var permissions: [PluginPermission]
    public var settings: [PluginSetting]
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
        settings: [PluginSetting] = [],
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
        self.settings = settings
        self.actions = actions
        self.dataStreams = dataStreams
        self.views = views
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case apiVersion
        case entry
        case capabilities
        case permissions
        case settings
        case actions
        case dataStreams
        case views
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        apiVersion = try container.decodeIfPresent(String.self, forKey: .apiVersion) ?? PluginManifestValidator.currentAPIVersion
        entry = try container.decode(PluginEntry.self, forKey: .entry)
        capabilities = try container.decodeIfPresent([PluginCapability].self, forKey: .capabilities) ?? []
        permissions = try container.decodeIfPresent([PluginPermission].self, forKey: .permissions) ?? []
        settings = try container.decodeIfPresent([PluginSetting].self, forKey: .settings) ?? []
        actions = try container.decodeIfPresent([PluginAction].self, forKey: .actions) ?? []
        dataStreams = try container.decodeIfPresent([PluginDataStream].self, forKey: .dataStreams) ?? []
        views = try container.decodeIfPresent([PluginView].self, forKey: .views) ?? []
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

public struct PluginSetting: Codable, Equatable, Identifiable, Sendable {
    public enum ValueType: String, Codable, Sendable {
        case string
        case integer
        case number
        case boolean
        case choice
        case secret
    }

    public var id: String
    public var title: String
    public var type: ValueType
    public var defaultValue: JSONValue
    public var choices: [JSONValue]
    public var minimum: Double?
    public var maximum: Double?
    public var environment: String?
    public var help: String?
    public var group: String?
    public var order: Int?
    public var uiControl: String?
    public var restartRequired: Bool

    public init(
        id: String,
        title: String,
        type: ValueType,
        defaultValue: JSONValue,
        choices: [JSONValue] = [],
        minimum: Double? = nil,
        maximum: Double? = nil,
        environment: String? = nil,
        help: String? = nil,
        group: String? = nil,
        order: Int? = nil,
        uiControl: String? = nil,
        restartRequired: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.defaultValue = defaultValue
        self.choices = choices
        self.minimum = minimum
        self.maximum = maximum
        self.environment = environment
        self.help = help
        self.group = group
        self.order = order
        self.uiControl = uiControl
        self.restartRequired = restartRequired
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case type
        case defaultValue
        case choices
        case minimum
        case maximum
        case environment
        case help
        case group
        case order
        case uiControl
        case restartRequired
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(ValueType.self, forKey: .type)
        defaultValue = try container.decode(JSONValue.self, forKey: .defaultValue)
        choices = try container.decodeIfPresent([JSONValue].self, forKey: .choices) ?? []
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        environment = try container.decodeIfPresent(String.self, forKey: .environment)
        help = try container.decodeIfPresent(String.self, forKey: .help)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        order = try container.decodeIfPresent(Int.self, forKey: .order)
        uiControl = try container.decodeIfPresent(String.self, forKey: .uiControl)
        restartRequired = try container.decodeIfPresent(Bool.self, forKey: .restartRequired) ?? false
    }
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

    public enum Layout: String, Codable, Sendable {
        case grid
        case fullScreen
        case halfLeading
        case halfTrailing
        case halfAndGrid
        case twoHalves
        case thirds
        case quarters
    }

    public var id: String
    public var title: String
    public var type: ViewType?
    public var presentation: Presentation?
    public var layout: Layout?
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
        layout: Layout? = nil,
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
        self.layout = layout
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
