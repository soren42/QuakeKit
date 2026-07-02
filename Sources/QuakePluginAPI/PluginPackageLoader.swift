import Foundation

public struct PluginPackage: Equatable, Sendable {
    public var manifest: PluginManifest
    public var baseURL: URL
    public var manifestURL: URL

    public init(manifest: PluginManifest, baseURL: URL, manifestURL: URL) {
        self.manifest = manifest
        self.baseURL = baseURL
        self.manifestURL = manifestURL
    }
}

public enum PluginPackageLoader {
    public static func loadPackages(from directory: URL, fileManager: FileManager = .default) -> [PluginPackageLoadResult] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .sorted { $0.path < $1.path }
            .compactMap { entry in
                manifestCandidate(for: entry, fileManager: fileManager).map(loadPackage)
            }
    }

    private static func manifestCandidate(for url: URL, fileManager: FileManager) -> URL? {
        if url.pathExtension == "json" {
            return url
        }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else {
            return nil
        }

        let manifestURL = url.appendingPathComponent("manifest.json")
        return fileManager.fileExists(atPath: manifestURL.path) ? manifestURL : nil
    }

    private static func loadPackage(from manifestURL: URL) -> PluginPackageLoadResult {
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
            let validation = PluginManifestValidator.validate(manifest)
            guard validation.isValid else {
                return .failure(manifestURL, validation.errors)
            }
            return .success(PluginPackage(
                manifest: manifest,
                baseURL: manifestURL.deletingLastPathComponent(),
                manifestURL: manifestURL
            ), warnings: validation.warnings)
        } catch {
            return .failure(manifestURL, [String(describing: error)])
        }
    }
}

public enum PluginPackageLoadResult: Equatable, Sendable {
    case success(PluginPackage, warnings: [String])
    case failure(URL, [String])
}
