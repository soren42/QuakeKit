import Foundation

public struct PluginPermissionGrant: Codable, Equatable, Sendable {
    public var pluginID: String
    public var grantedPermissions: [PluginPermission]
    public var grantedAt: Date

    public init(pluginID: String, grantedPermissions: [PluginPermission], grantedAt: Date = Date()) {
        self.pluginID = pluginID
        self.grantedPermissions = grantedPermissions
        self.grantedAt = grantedAt
    }
}

public struct PluginPermissionSet: Codable, Equatable, Sendable {
    public var grants: [String: PluginPermissionGrant]

    public init(grants: [String: PluginPermissionGrant] = [:]) {
        self.grants = grants
    }

    public func grant(for pluginID: String) -> PluginPermissionGrant? {
        grants[pluginID]
    }
}
