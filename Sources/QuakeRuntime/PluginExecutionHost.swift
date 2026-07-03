import Foundation
import QuakePluginAPI

public struct PluginInvocationResult: Codable, Equatable, Sendable {
    public var pluginID: String
    public var actionID: String
    public var response: PluginResponse
    public var stdout: String
    public var stderr: String
    public var exitStatus: Int32?
    public var duration: TimeInterval

    public init(
        pluginID: String,
        actionID: String,
        response: PluginResponse,
        stdout: String = "",
        stderr: String = "",
        exitStatus: Int32? = nil,
        duration: TimeInterval = 0
    ) {
        self.pluginID = pluginID
        self.actionID = actionID
        self.response = response
        self.stdout = stdout
        self.stderr = stderr
        self.exitStatus = exitStatus
        self.duration = duration
    }
}

public enum PluginExecutionError: Error, CustomStringConvertible, Sendable {
    case pluginNotFound(String)
    case actionNotFound(pluginID: String, actionID: String)
    case unsupportedTransport(PluginEntry.Transport)
    case missingCommand(pluginID: String)
    case commandNotFound(String)
    case launchFailed(String)
    case timedOut(TimeInterval)

    public var description: String {
        switch self {
        case .pluginNotFound(let pluginID):
            return "Plugin \(pluginID) is not loaded."
        case .actionNotFound(let pluginID, let actionID):
            return "Action \(actionID) is not declared by plugin \(pluginID)."
        case .unsupportedTransport(let transport):
            return "Plugin transport \(transport.rawValue) is not executable by the local process host."
        case .missingCommand(let pluginID):
            return "Plugin \(pluginID) does not declare an executable command."
        case .commandNotFound(let command):
            return "Plugin command \(command) was not found."
        case .launchFailed(let message):
            return "Plugin launch failed: \(message)"
        case .timedOut(let timeout):
            return "Plugin command timed out after \(String(format: "%.1f", timeout))s."
        }
    }
}

public final class PluginExecutionHost: @unchecked Sendable {
    private let packagesByID: [String: PluginPackage]
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(packages: [PluginPackage]) {
        self.packagesByID = Dictionary(uniqueKeysWithValues: packages.map { ($0.manifest.id, $0) })
    }

    public func invokeAction(
        pluginID: String,
        actionID: String,
        params: JSONValue = .object([:]),
        timeout: TimeInterval = 5
    ) -> PluginInvocationResult {
        let request = PluginRequest(method: "action.\(actionID)", params: params)
        let start = Date()

        do {
            let package = try package(pluginID)
            guard package.manifest.actions.contains(where: { $0.id == actionID }) else {
                throw PluginExecutionError.actionNotFound(pluginID: pluginID, actionID: actionID)
            }

            let process = try makeProcess(for: package)
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            try send(request, to: stdin)

            let timedOut = wait(for: process, timeout: timeout)
            if timedOut {
                process.terminate()
                throw PluginExecutionError.timedOut(timeout)
            }

            let output = readString(stdout)
            let errors = readString(stderr)
            let response = decodeResponse(from: output, requestID: request.id, exitStatus: process.terminationStatus)
            return PluginInvocationResult(
                pluginID: pluginID,
                actionID: actionID,
                response: response,
                stdout: output,
                stderr: errors,
                exitStatus: process.terminationStatus,
                duration: Date().timeIntervalSince(start)
            )
        } catch let error as PluginExecutionError {
            return failed(pluginID: pluginID, actionID: actionID, requestID: request.id, error: error, duration: Date().timeIntervalSince(start))
        } catch {
            return failed(
                pluginID: pluginID,
                actionID: actionID,
                requestID: request.id,
                error: PluginExecutionError.launchFailed(String(describing: error)),
                duration: Date().timeIntervalSince(start)
            )
        }
    }

    private func package(_ pluginID: String) throws -> PluginPackage {
        guard let package = packagesByID[pluginID] else {
            throw PluginExecutionError.pluginNotFound(pluginID)
        }
        return package
    }

    private func makeProcess(for package: PluginPackage) throws -> Process {
        let entry = package.manifest.entry
        let process = Process()
        process.currentDirectoryURL = package.baseURL

        switch entry.transport {
        case .shell, .stdioJSONRPC:
            guard let command = entry.command, !command.isEmpty else {
                throw PluginExecutionError.missingCommand(pluginID: package.manifest.id)
            }
            process.executableURL = try executableURL(command: command, baseURL: package.baseURL)
            process.arguments = entry.arguments
        case .php:
            guard let command = entry.command, !command.isEmpty else {
                throw PluginExecutionError.missingCommand(pluginID: package.manifest.id)
            }
            let scriptURL = package.baseURL.appendingPathComponent(command)
            guard FileManager.default.fileExists(atPath: scriptURL.path) else {
                throw PluginExecutionError.commandNotFound(command)
            }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["php", scriptURL.path] + entry.arguments
        case .websocket, .nativeSwift, .webView:
            throw PluginExecutionError.unsupportedTransport(entry.transport)
        }

        process.environment = environment(for: package)
        return process
    }

    private func executableURL(command: String, baseURL: URL) throws -> URL {
        let localURL = baseURL.appendingPathComponent(command)
        if FileManager.default.isExecutableFile(atPath: localURL.path) {
            return localURL
        }
        if command.contains("/") {
            let explicitURL = URL(fileURLWithPath: command)
            if FileManager.default.isExecutableFile(atPath: explicitURL.path) {
                return explicitURL
            }
            throw PluginExecutionError.commandNotFound(command)
        }
        let paths = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        for path in paths {
            let url = URL(fileURLWithPath: path).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        throw PluginExecutionError.commandNotFound(command)
    }

    private func environment(for package: PluginPackage) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["QUAKEKIT_PLUGIN_ID"] = package.manifest.id
        environment["QUAKEKIT_PLUGIN_NAME"] = package.manifest.name
        environment["QUAKEKIT_PLUGIN_BASE"] = package.baseURL.path
        environment["QUAKEKIT_API_VERSION"] = package.manifest.apiVersion
        return environment
    }

    private func send(_ request: PluginRequest, to pipe: Pipe) throws {
        let data = try encoder.encode(request)
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.write(Data([0x0A]))
        try pipe.fileHandleForWriting.close()
    }

    private func wait(for process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        return process.isRunning
    }

    private func readString(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func decodeResponse(from output: String, requestID: UUID, exitStatus: Int32) -> PluginResponse {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), let response = try? decoder.decode(PluginResponse.self, from: data) {
            return response
        }
        if let data = trimmed.data(using: .utf8), let value = try? decoder.decode(JSONValue.self, from: data) {
            return PluginResponse(id: requestID, ok: exitStatus == 0, result: value, error: exitStatus == 0 ? nil : "Plugin exited with status \(exitStatus).")
        }
        return PluginResponse(
            id: requestID,
            ok: exitStatus == 0,
            result: trimmed.isEmpty ? nil : .string(trimmed),
            error: exitStatus == 0 ? nil : "Plugin exited with status \(exitStatus)."
        )
    }

    private func failed(
        pluginID: String,
        actionID: String,
        requestID: UUID,
        error: PluginExecutionError,
        duration: TimeInterval
    ) -> PluginInvocationResult {
        PluginInvocationResult(
            pluginID: pluginID,
            actionID: actionID,
            response: PluginResponse(id: requestID, ok: false, error: error.description),
            duration: duration
        )
    }
}
