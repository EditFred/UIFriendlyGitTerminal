import AppKit
import Foundation
import GitVibesCore

struct NPMProjectInfo: Equatable, Sendable {
    let projectDirectoryPath: String
    let availableScripts: Set<NPMCommand>
    let suggestedBrowserURL: String?
}

protocol NPMProjectServicing: Sendable {
    func inspectProject(in repositoryRoot: URL) throws -> NPMProjectInfo?
    func run(_ command: NPMCommand, in projectDirectory: URL) throws -> GitCommandResult
    func launch(_ command: NPMCommand, in projectDirectory: URL) throws -> Int32
}

enum NPMProjectServiceError: Error, LocalizedError {
    case packageJSONNotFound
    case invalidPackageJSON

    var errorDescription: String? {
        switch self {
        case .packageJSONNotFound:
            return "No package.json was found in this repository."
        case .invalidPackageJSON:
            return "package.json is not valid JSON."
        }
    }
}

struct NPMProjectService: NPMProjectServicing, Sendable {

    func inspectProject(in repositoryRoot: URL) throws -> NPMProjectInfo? {
        guard let packageURL = findPackageJSON(in: repositoryRoot) else {
            return nil
        }

        let scripts = try parseScripts(from: packageURL)
        let availableScripts = Set(NPMCommand.allCases.filter { scripts[$0.scriptName] != nil })
        let suggestedBrowserURL = inferSuggestedBrowserURL(from: scripts)

        return NPMProjectInfo(
            projectDirectoryPath: packageURL.deletingLastPathComponent().path,
            availableScripts: availableScripts,
            suggestedBrowserURL: suggestedBrowserURL
        )
    }

    func run(_ command: NPMCommand, in projectDirectory: URL) throws -> GitCommandResult {
        try runNPM(arguments: command.arguments, in: projectDirectory)
    }

    func launch(_ command: NPMCommand, in projectDirectory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm"] + command.arguments
        process.currentDirectoryURL = projectDirectory

        let nullDevice = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullDevice
        process.standardError = nullDevice

        try process.run()
        return process.processIdentifier
    }

    private func runNPM(arguments: [String], in directory: URL) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm"] + arguments
        process.currentDirectoryURL = directory

        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe

        try process.run()
        process.waitUntilExit()

        let standardOutputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
        let standardErrorData = standardErrorPipe.fileHandleForReading.readDataToEndOfFile()

        return GitCommandResult(
            standardOutput: String(decoding: standardOutputData, as: UTF8.self),
            standardError: String(decoding: standardErrorData, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }

    private func findPackageJSON(in repositoryRoot: URL) -> URL? {
        let rootPackage = repositoryRoot.appendingPathComponent("package.json")
        if FileManager.default.fileExists(atPath: rootPackage.path) {
            return rootPackage
        }

        guard let enumerator = FileManager.default.enumerator(
            at: repositoryRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            if [".git", "node_modules"].contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            if url.lastPathComponent == "package.json" {
                return url
            }
        }

        return nil
    }

    private func parseScripts(from packageURL: URL) throws -> [String: String] {
        let data = try Data(contentsOf: packageURL)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scripts = root["scripts"] as? [String: Any]
        else {
            return [:]
        }

        return scripts.reduce(into: [String: String]()) { partialResult, entry in
            if let command = entry.value as? String {
                partialResult[entry.key] = command
            }
        }
    }

    private func inferSuggestedBrowserURL(from scripts: [String: String]) -> String? {
        guard let startScript = scripts["start"] else {
            return nil
        }

        if startScript.contains("5173") {
            return "http://localhost:5173"
        }
        if startScript.contains("8080") {
            return "http://localhost:8080"
        }
        return "http://localhost:3000"
    }
}

enum IDEApplication: String, CaseIterable, Equatable, Identifiable {
    case xcode
    case visualStudioCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xcode:
            return "Xcode"
        case .visualStudioCode:
            return "Visual Studio Code"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .xcode:
            return "com.apple.dt.Xcode"
        case .visualStudioCode:
            return "com.microsoft.VSCode"
        }
    }
}

struct RepositoryOpenOption: Equatable {
    let application: IDEApplication
    let targetPath: String
    let reason: String
    let isRecommended: Bool
}

struct RepositoryOpenPlan: Equatable {
    let options: [RepositoryOpenOption]
}

protocol RepositoryOpenPlanning {
    func planOpenOptions(for repositoryRoot: URL) throws -> RepositoryOpenPlan
}

struct RepositoryOpenPlanner: RepositoryOpenPlanning {
    private let fileManager = FileManager.default

    func planOpenOptions(for repositoryRoot: URL) throws -> RepositoryOpenPlan {
        let workspace = findFirstPath(in: repositoryRoot, withExtension: "xcworkspace")
        let xcodeProject = findFirstPath(in: repositoryRoot, withExtension: "xcodeproj")
        let packageJSON = findFirstPath(in: repositoryRoot, named: "package.json")

        let xcodeTarget = workspace ?? xcodeProject ?? repositoryRoot.path
        let xcodeReason = (workspace != nil || xcodeProject != nil)
            ? "Xcode project files were found in this repository."
            : "Open the repository root in Xcode."

        let codeReason = packageJSON != nil
            ? "Detected package.json; Visual Studio Code is often a good fit for JS/TS repos."
            : "Open the repository root in Visual Studio Code."

        let shouldRecommendXcode = workspace != nil || xcodeProject != nil

        return RepositoryOpenPlan(options: [
            RepositoryOpenOption(
                application: .xcode,
                targetPath: xcodeTarget,
                reason: xcodeReason,
                isRecommended: shouldRecommendXcode
            ),
            RepositoryOpenOption(
                application: .visualStudioCode,
                targetPath: repositoryRoot.path,
                reason: codeReason,
                isRecommended: !shouldRecommendXcode
            )
        ])
    }

    private func findFirstPath(in root: URL, withExtension fileExtension: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            if [".git", "node_modules"].contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            if url.pathExtension == fileExtension {
                return url.path
            }
        }

        return nil
    }

    private func findFirstPath(in root: URL, named fileName: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            if [".git", "node_modules"].contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            if url.lastPathComponent == fileName {
                return url.path
            }
        }

        return nil
    }
}

protocol BrowserOpening {
    func open(_ url: URL)
}

struct BrowserOpener: BrowserOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

protocol IDEProjectOpening {
    func isAvailable(_ application: IDEApplication) -> Bool
    func openProject(at projectURL: URL, with application: IDEApplication) throws
}

enum IDEProjectOpeningError: Error, LocalizedError {
    case applicationUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .applicationUnavailable(name):
            return "\(name) is not available on this Mac."
        }
    }
}

struct WorkspaceIDEProjectOpener: IDEProjectOpening {
    func isAvailable(_ application: IDEApplication) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier) != nil
    }

    func openProject(at projectURL: URL, with application: IDEApplication) throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier) else {
            throw IDEProjectOpeningError.applicationUnavailable(application.displayName)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([projectURL], withApplicationAt: appURL, configuration: configuration) { _, _ in }
    }
}
