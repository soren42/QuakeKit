import Foundation

public struct PanelResolution: Codable, Equatable, Sendable {
    public static let quakeLandscape = PanelResolution(width: 1920, height: 480)

    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct Tile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var icon: String?
    public var action: ActionBinding?
    public var columnSpan: Int
    public var rowSpan: Int

    public init(
        id: UUID = UUID(),
        label: String,
        icon: String? = nil,
        action: ActionBinding? = nil,
        columnSpan: Int = 1,
        rowSpan: Int = 1
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.action = action
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }
}

public struct Page: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case grid
        case dashboard
        case pluginView
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var columns: Int
    public var rows: Int
    public var tiles: [Tile]
    public var pluginViewID: String?
    public var dashboardURL: URL?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .grid,
        columns: Int = 8,
        rows: Int = 2,
        tiles: [Tile] = [],
        pluginViewID: String? = nil,
        dashboardURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.columns = columns
        self.rows = rows
        self.tiles = tiles
        self.pluginViewID = pluginViewID
        self.dashboardURL = dashboardURL
    }
}

public struct ActionBinding: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case host
        case plugin
        case page
        case macro
    }

    public var kind: Kind
    public var identifier: String
    public var arguments: [String: String]

    public init(kind: Kind, identifier: String, arguments: [String: String] = [:]) {
        self.kind = kind
        self.identifier = identifier
        self.arguments = arguments
    }
}
