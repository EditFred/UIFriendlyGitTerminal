import Foundation

public protocol ShellCommandRunning: Sendable {
    func run(arguments: [String], workingDirectory: URL?) throws -> GitCommandResult
}

public enum GitServiceError: Error, LocalizedError {
    case notARepository
    case commandFailed(label: String, result: GitCommandResult)

    public var errorDescription: String? {
        switch self {
        case .notARepository:
            return "The selected folder is not a git repository."
        case let .commandFailed(label, result):
            let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return "\(label) failed with exit code \(result.terminationStatus)."
            }
            return "\(label) failed: \(output)"
        }
    }
}

public struct ProcessRunner: ShellCommandRunning {
    public init() {}

    public func run(arguments: [String], workingDirectory: URL?) throws -> GitCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
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
}

public struct GitRepositoryService: Sendable {
    private let runner: any ShellCommandRunning

    public init(runner: any ShellCommandRunning = ProcessRunner()) {
        self.runner = runner
    }

    public func resolveRepositoryRoot(for folder: URL) throws -> URL {
        let result = try runner.run(arguments: GitCommand.resolveTopLevel.arguments, workingDirectory: folder)
        guard result.succeeded else {
            throw GitServiceError.notARepository
        }

        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw GitServiceError.notARepository
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public func loadSnapshot(for folder: URL) throws -> GitRepositorySnapshot {
        let root = try resolveRepositoryRoot(for: folder)
        let currentBranch = try requiredOutput(for: .currentBranch, in: root)
        let branchesOutput = try requiredOutput(for: .listBranches, in: root)
        let statusOutput = try requiredOutput(for: .statusShort, in: root, allowEmpty: true)

        return GitRepositorySnapshot(
            rootPath: root.path,
            currentBranch: currentBranch,
            branches: GitParsing.parseBranches(branchesOutput),
            changedFiles: GitParsing.parseChangedFiles(statusOutput)
        )
    }

    @discardableResult
    public func perform(_ command: GitCommand, in folder: URL) throws -> GitCommandResult {
        let root = try resolveRepositoryRoot(for: folder)
        let result = try runner.run(arguments: command.arguments, workingDirectory: root)
        guard result.succeeded else {
            throw GitServiceError.commandFailed(label: command.label, result: result)
        }
        return result
    }

    private func requiredOutput(for command: GitCommand, in folder: URL, allowEmpty: Bool = false) throws -> String {
        let result = try runner.run(arguments: command.arguments, workingDirectory: folder)
        guard result.succeeded else {
            throw GitServiceError.commandFailed(label: command.label, result: result)
        }

        let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowEmpty && output.isEmpty {
            throw GitServiceError.commandFailed(label: command.label, result: result)
        }
        return output
    }
}
