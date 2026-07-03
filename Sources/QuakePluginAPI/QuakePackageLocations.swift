import Foundation

public enum QuakePackageLocations {
    public static let applicationSupportFolder = "QuakeKit"

    public static func applicationSupportDirectory(fileManager: FileManager = .default) throws -> URL {
        if let override = ProcessInfo.processInfo.environment["QUAKEKIT_APPLICATION_SUPPORT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw QuakePackageInstallError.applicationSupportUnavailable
        }
        let url = directory.appendingPathComponent(applicationSupportFolder, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func installedPluginDirectory(fileManager: FileManager = .default) throws -> URL {
        let url = try applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("Plugins", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func installedThemeDirectory(fileManager: FileManager = .default) throws -> URL {
        let url = try applicationSupportDirectory(fileManager: fileManager).appendingPathComponent("Themes", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
