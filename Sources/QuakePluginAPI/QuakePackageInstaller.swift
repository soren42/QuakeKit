import Foundation

public enum QuakePackageKind: String, Codable, Sendable {
    case plugin
    case theme
}

public struct QuakeInstalledPackage: Equatable, Sendable {
    public var kind: QuakePackageKind
    public var id: String
    public var name: String
    public var url: URL

    public init(kind: QuakePackageKind, id: String, name: String, url: URL) {
        self.kind = kind
        self.id = id
        self.name = name
        self.url = url
    }
}

public enum QuakePackageInstallError: Error, CustomStringConvertible, Sendable {
    case applicationSupportUnavailable
    case sourceMissing(URL)
    case unsupportedPackage(URL)
    case archiveExtractionFailed(String)
    case validationFailed([String])
    case installFailed(String)

    public var description: String {
        switch self {
        case .applicationSupportUnavailable:
            return "Application Support directory is unavailable."
        case .sourceMissing(let url):
            return "Package source does not exist: \(url.path)"
        case .unsupportedPackage(let url):
            return "Unsupported package format: \(url.path)"
        case .archiveExtractionFailed(let message):
            return "Archive extraction failed: \(message)"
        case .validationFailed(let errors):
            return "Package validation failed: \(errors.joined(separator: "; "))"
        case .installFailed(let message):
            return "Package install failed: \(message)"
        }
    }
}

public enum QuakePackageInstaller {
    public static func installPackage(from sourceURL: URL, fileManager: FileManager = .default) throws -> QuakeInstalledPackage {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw QuakePackageInstallError.sourceMissing(sourceURL)
        }

        if isDirectory.boolValue {
            return try installDirectory(sourceURL, fileManager: fileManager)
        }

        guard isArchive(sourceURL) else {
            throw QuakePackageInstallError.unsupportedPackage(sourceURL)
        }

        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("QuakeKitInstall-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        try extractArchive(sourceURL, to: tempRoot)
        guard let packageDirectory = packageDirectory(in: tempRoot, fileManager: fileManager) else {
            throw QuakePackageInstallError.unsupportedPackage(sourceURL)
        }
        return try installDirectory(packageDirectory, fileManager: fileManager)
    }

    private static func installDirectory(_ sourceURL: URL, fileManager: FileManager) throws -> QuakeInstalledPackage {
        if sourceURL.pathExtension == "quakekitplugin" || fileManager.fileExists(atPath: sourceURL.appendingPathComponent("manifest.json").path) {
            let package = try loadPluginPackage(at: sourceURL)
            let destination = try QuakePackageLocations.installedPluginDirectory(fileManager: fileManager)
                .appendingPathComponent("\(package.manifest.id).quakekitplugin", isDirectory: true)
            try replaceItem(at: destination, with: sourceURL, fileManager: fileManager)
            return QuakeInstalledPackage(kind: .plugin, id: package.manifest.id, name: package.manifest.name, url: destination)
        }

        if sourceURL.pathExtension == "quakekittheme" || fileManager.fileExists(atPath: sourceURL.appendingPathComponent("theme.json").path) {
            let package = try loadThemePackage(at: sourceURL)
            let destination = try QuakePackageLocations.installedThemeDirectory(fileManager: fileManager)
                .appendingPathComponent("\(package.manifest.id).quakekittheme", isDirectory: true)
            try replaceItem(at: destination, with: sourceURL, fileManager: fileManager)
            return QuakeInstalledPackage(kind: .theme, id: package.manifest.id, name: package.manifest.name, url: destination)
        }

        throw QuakePackageInstallError.unsupportedPackage(sourceURL)
    }

    private static func loadPluginPackage(at directory: URL) throws -> PluginPackage {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        do {
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: manifestURL))
            let validation = PluginManifestValidator.validatePackage(manifest, baseURL: directory)
            guard validation.isValid else {
                throw QuakePackageInstallError.validationFailed(validation.errors)
            }
            return PluginPackage(manifest: manifest, baseURL: directory, manifestURL: manifestURL)
        } catch let error as QuakePackageInstallError {
            throw error
        } catch {
            throw QuakePackageInstallError.installFailed(String(describing: error))
        }
    }

    private static func loadThemePackage(at directory: URL) throws -> ThemePackage {
        let manifestURL = directory.appendingPathComponent("theme.json")
        do {
            let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(contentsOf: manifestURL))
            let validation = ThemeManifestValidator.validate(manifest)
            guard validation.isValid else {
                throw QuakePackageInstallError.validationFailed(validation.errors)
            }
            return ThemePackage(manifest: manifest, baseURL: directory, manifestURL: manifestURL)
        } catch let error as QuakePackageInstallError {
            throw error
        } catch {
            throw QuakePackageInstallError.installFailed(String(describing: error))
        }
    }

    private static func replaceItem(at destination: URL, with source: URL, fileManager: FileManager) throws {
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw QuakePackageInstallError.installFailed(String(describing: error))
        }
    }

    private static func packageDirectory(in directory: URL, fileManager: FileManager) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            if url.pathExtension == "quakekitplugin" || url.pathExtension == "quakekittheme" {
                return url
            }
            if fileManager.fileExists(atPath: url.appendingPathComponent("manifest.json").path)
                || fileManager.fileExists(atPath: url.appendingPathComponent("theme.json").path) {
                return url
            }
        }
        return nil
    }

    private static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".tar") || name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz")
    }

    private static func extractArchive(_ archiveURL: URL, to directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archiveURL.path, "-C", directory.path]
        let stderr = Pipe()
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw QuakePackageInstallError.archiveExtractionFailed(String(describing: error))
        }
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "tar exited \(process.terminationStatus)"
            throw QuakePackageInstallError.archiveExtractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
