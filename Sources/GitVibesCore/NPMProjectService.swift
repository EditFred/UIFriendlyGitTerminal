import Foundation

public struct NPMProjectInfo: Equatable, Sendable {
    public let projectDirectoryPath: String
    public let availableScripts: [NPMCommand]
    public let suggestedBrowserURL: String

    public init(projectDirectoryPath: String, availableScripts: [NPMCommand], suggestedBrowserURL: String) {
        self.projectDirectoryPath = projectDirectoryPath
        self.availableScripts = availableScripts
        self.suggestedBrowserURL = suggestedBrowserURL
    }
}

public protocol NPMProjectServicing: Sendable {
    func inspectProject(in repositoryRoot: URL) throws -> NPMProjectInfo?
    func run(_ command: NPMCommand, in projectDirectory: URL) throws -> GitCommandResult
    func launch(_ command: NPMCommand, in projectDirectory: URL) throws -> ProcessIdentifier
}

public enum NPMServiceError: Error, LocalizedError {
    case invalidPackageJSON
    case commandFailed(label: String, result: GitCommandResult)

    public var errorDescription: String? {
        switch self {
        case .invalidPackageJSON:
            return "The package.json file could not be parsed."
        case let .commandFailed(label, result):
            let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return "\(label) failed with exit code \(result.terminationStatus)."
            }
            return "\(label) failed: \(output)"
        }
    }
}

public protocol ProcessLaunching: Sendable {
    func run(executableName: String, arguments: [String], workingDirectory: URL?) throws -> GitCommandResult
    func launch(executableName: String, arguments: [String], workingDirectory: URL?) throws -> ProcessIdentifier
}

public typealias ProcessIdentifier = Int32

extension ProcessRunner: ProcessLaunching {
    public func run(executableName: String, arguments: [String], workingDirectory: URL?) throws -> GitCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executableName] + arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let standardOutput = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let standardError = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        return GitCommandResult(
            standardOutput: standardOutput,
            standardError: standardError,
            terminationStatus: process.terminationStatus
        )
    }

    public func launch(executableName: String, arguments: [String], workingDirectory: URL?) throws -> ProcessIdentifier {
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executableName] + arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        return process.processIdentifier
    }
}

public struct NPMProjectService: NPMProjectServicing {
    private let runner: any ProcessLaunching

    public init(runner: any ProcessLaunching = ProcessRunner()) {
        self.runner = runner
    }

    public func inspectProject(in repositoryRoot: URL) throws -> NPMProjectInfo? {
        let packageJSONURL = repositoryRoot.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: packageJSONURL.path) else {
            return nil
        }

        let packageData = try Data(contentsOf: packageJSONURL)
        guard let jsonObject = try JSONSerialization.jsonObject(with: packageData) as? [String: Any] else {
            throw NPMServiceError.invalidPackageJSON
        }

        let scripts = jsonObject["scripts"] as? [String: String] ?? [:]
        let availableScripts = NPMCommand.allCases.filter { scripts[$0.scriptName] != nil }
        let browserURL = Self.suggestedBrowserURL(from: scripts)

        return NPMProjectInfo(
            projectDirectoryPath: repositoryRoot.path,
            availableScripts: availableScripts,
            suggestedBrowserURL: browserURL
        )
    }

    public func run(_ command: NPMCommand, in projectDirectory: URL) throws -> GitCommandResult {
        // HUMHERE: This assumes `npm` is available on PATH for app-launched processes via `/usr/bin/env`, which may differ from shell-initialized Node setups.
        let result = try runner.run(
            executableName: "npm",
            arguments: command.arguments,
            workingDirectory: projectDirectory
        )
        guard result.succeeded else {
            throw NPMServiceError.commandFailed(label: command.label, result: result)
        }
        return result
    }

    public func launch(_ command: NPMCommand, in projectDirectory: URL) throws -> ProcessIdentifier {
        // HUMHERE: This assumes `npm start` can be launched detached without streaming output back into the app, which may need revisiting for long-running dev servers.
        try runner.launch(
            executableName: "npm",
            arguments: command.arguments,
            workingDirectory: projectDirectory
        )
    }

    static func suggestedBrowserURL(from scripts: [String: String]) -> String {
        let scriptBodies = [
            scripts[NPMCommand.start.scriptName],
            scripts[NPMCommand.build.scriptName],
            scripts[NPMCommand.test.scriptName]
        ]
        .compactMap { $0 }

        let patterns = [
            #"https?://(?:localhost|127\.0\.0\.1):\d+"#,
            #"(?:(?:--port|-p)\s+|PORT=)(\d{2,5})"#
        ]

        for body in scriptBodies {
            for pattern in patterns {
                guard let expression = try? NSRegularExpression(pattern: pattern) else {
                    continue
                }

                let fullRange = NSRange(body.startIndex..<body.endIndex, in: body)
                guard let match = expression.firstMatch(in: body, range: fullRange) else {
                    continue
                }

                if pattern.contains("https?://"), let range = Range(match.range(at: 0), in: body) {
                    return String(body[range])
                }

                if let range = Range(match.range(at: 1), in: body) {
                    return "http://localhost:\(body[range])"
                }
            }
        }

        // HUMHERE: Defaulting browser launch to port 3000 is a product choice until the team defines per-framework defaults or a user preference.
        return "http://localhost:3000"
    }
}
