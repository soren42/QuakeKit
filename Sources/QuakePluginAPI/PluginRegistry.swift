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

        switch manifest.entry.transport {
        case .stdioJSONRPC, .shell, .php:
            if manifest.entry.command?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                errors.append("Plugin entry command is required for \(manifest.entry.transport.rawValue).")
            }
        case .webView:
            if manifest.entry.url == nil && !manifest.views.contains(where: { $0.entryPath != nil }) {
                errors.append("Web view plugins must define entry.url or at least one view entryPath.")
            }
        case .websocket:
            if manifest.entry.url == nil {
                errors.append("WebSocket plugins must define entry.url.")
            }
        case .nativeSwift:
            break
        }

        if Set(manifest.capabilities).count != manifest.capabilities.count {
            errors.append("Plugin capabilities must be unique.")
        }

        let settingIDs = manifest.settings.map(\.id)
        if Set(settingIDs).count != settingIDs.count {
            errors.append("Plugin setting ids must be unique.")
        }
        for setting in manifest.settings {
            if setting.id.range(of: idPattern, options: .regularExpression) == nil {
                errors.append("Setting \(setting.id) id must match \(idPattern).")
            }
            if setting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append("Setting \(setting.id) title is required.")
            }
            if setting.type == .choice && setting.choices.isEmpty {
                errors.append("Setting \(setting.id) must define choices.")
            }
            if let minimum = setting.minimum, let maximum = setting.maximum, minimum > maximum {
                errors.append("Setting \(setting.id) minimum must be less than or equal to maximum.")
            }
        }

        let actionIDs = manifest.actions.map(\.id)
        if Set(actionIDs).count != actionIDs.count {
            errors.append("Plugin action ids must be unique.")
        }
        for action in manifest.actions {
            let fieldIDs = action.argumentSchema.map(\.id)
            if Set(fieldIDs).count != fieldIDs.count {
                errors.append("Action \(action.id) argument field ids must be unique.")
            }
        }

        let streamIDs = manifest.dataStreams.map(\.id)
        if Set(streamIDs).count != streamIDs.count {
            errors.append("Plugin data stream ids must be unique.")
        }
        let streamIDSet = Set(streamIDs)
        for stream in manifest.dataStreams {
            let fieldIDs = stream.valueSchema.map(\.id)
            if Set(fieldIDs).count != fieldIDs.count {
                errors.append("Data stream \(stream.id) value field ids must be unique.")
            }
        }

        let viewIDs = manifest.views.map(\.id)
        if Set(viewIDs).count != viewIDs.count {
            errors.append("Plugin view ids must be unique.")
        }
        for view in manifest.views {
            if let dataStreamID = view.dataStreamID, !streamIDSet.contains(dataStreamID) {
                errors.append("View \(view.id) references missing data stream \(dataStreamID).")
            }
            if let columnSpan = view.columnSpan, columnSpan < 1 {
                errors.append("View \(view.id) columnSpan must be positive.")
            }
            if let rowSpan = view.rowSpan, rowSpan < 1 {
                errors.append("View \(view.id) rowSpan must be positive.")
            }
            if let width = view.preferredWidth, width < 1 {
                errors.append("View \(view.id) preferredWidth must be positive.")
            }
            if let height = view.preferredHeight, height < 1 {
                errors.append("View \(view.id) preferredHeight must be positive.")
            }
        }

        return PluginValidationResult(errors: errors, warnings: warnings)
    }

    public static func validatePackage(_ manifest: PluginManifest, baseURL: URL, fileManager: FileManager = .default) -> PluginValidationResult {
        var result = validate(manifest)
        switch manifest.entry.transport {
        case .stdioJSONRPC, .shell:
            if let command = manifest.entry.command, !command.contains("/") {
                let localURL = baseURL.appendingPathComponent(command)
                if !fileManager.isExecutableFile(atPath: localURL.path) {
                    result.warnings.append("Entry command \(command) was not found as an executable package file; host will search PATH at runtime.")
                }
            } else if let command = manifest.entry.command {
                let url = command.hasPrefix("/") ? URL(fileURLWithPath: command) : baseURL.appendingPathComponent(command)
                if !fileManager.isExecutableFile(atPath: url.path) {
                    result.errors.append("Entry command \(command) is not executable.")
                }
            }
        case .php:
            if let command = manifest.entry.command {
                let url = baseURL.appendingPathComponent(command)
                if !fileManager.fileExists(atPath: url.path) {
                    result.errors.append("PHP entry script \(command) does not exist.")
                }
            }
        case .webView:
            if let url = manifest.entry.url, url.scheme == nil {
                let fileURL = baseURL.appendingPathComponent(url.relativeString)
                if !fileManager.fileExists(atPath: fileURL.path) {
                    result.errors.append("Web view entry URL \(url.relativeString) does not exist.")
                }
            }
        case .websocket, .nativeSwift:
            break
        }

        for view in manifest.views {
            if let entryPath = view.entryPath {
                let entryURL = baseURL.appendingPathComponent(entryPath)
                if !fileManager.fileExists(atPath: entryURL.path) {
                    result.errors.append("View \(view.id) entryPath \(entryPath) does not exist.")
                }
            }
        }

        return result
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
