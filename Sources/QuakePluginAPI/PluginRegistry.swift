import Foundation

public struct PluginValidationResult: Equatable, Sendable {
    public var isValid: Bool { errors.isEmpty }
    public var errors: [String]
    public var warnings: [String]

    public init(errors: [String] = [], warnings: [String] = []) {
        self.errors = errors
        self.warnings = warnings
    }
}

public enum PluginManifestValidator {
    public static let currentAPIVersion = "0.1"
    public static let idPattern = #"^[a-z0-9][a-z0-9_-]*$"#

    public static func validate(_ manifest: PluginManifest) -> PluginValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        if manifest.id.range(of: idPattern, options: .regularExpression) == nil {
            errors.append("Plugin id must match \(idPattern).")
        }

        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Plugin name is required.")
        }

        if manifest.apiVersion != currentAPIVersion {
            warnings.append("Plugin API version \(manifest.apiVersion) differs from host API \(currentAPIVersion).")
        }

        let actionIDs = manifest.actions.map(\.id)
        if Set(actionIDs).count != actionIDs.count {
            errors.append("Plugin action ids must be unique.")
        }

        let streamIDs = manifest.dataStreams.map(\.id)
        if Set(streamIDs).count != streamIDs.count {
            errors.append("Plugin data stream ids must be unique.")
        }

        let viewIDs = manifest.views.map(\.id)
        if Set(viewIDs).count != viewIDs.count {
            errors.append("Plugin view ids must be unique.")
        }

        return PluginValidationResult(errors: errors, warnings: warnings)
    }
}

public struct PluginRegistry: Sendable {
    public private(set) var manifests: [String: PluginManifest]

    public init(manifests: [String: PluginManifest] = [:]) {
        self.manifests = manifests
    }

    public mutating func register(_ manifest: PluginManifest) throws {
        let result = PluginManifestValidator.validate(manifest)
        guard result.isValid else {
            throw PluginRegistryError.invalidManifest(result.errors)
        }
        guard manifests[manifest.id] == nil else {
            throw PluginRegistryError.duplicatePluginID(manifest.id)
        }
        manifests[manifest.id] = manifest
    }
}

public enum PluginRegistryError: Error, Equatable, Sendable {
    case invalidManifest([String])
    case duplicatePluginID(String)
}
