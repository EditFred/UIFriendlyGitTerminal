import AppKit
import Foundation
import GitVibesCore

protocol IDEProjectOpening: Sendable {
    func isAvailable(_ application: IDEApplication) -> Bool
    func openProject(at targetURL: URL, with application: IDEApplication) throws
}

enum IDEProjectOpeningError: Error, LocalizedError {
    case applicationNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .applicationNotFound(displayName):
            return "\(displayName) is not installed or could not be located."
        }
    }
}

struct WorkspaceIDEProjectOpener: IDEProjectOpening {
    func isAvailable(_ application: IDEApplication) -> Bool {
        resolveApplicationURL(for: application) != nil
    }

    func openProject(at targetURL: URL, with application: IDEApplication) throws {
        guard let applicationURL = resolveApplicationURL(for: application) else {
            throw IDEProjectOpeningError.applicationNotFound(application.displayName)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([targetURL], withApplicationAt: applicationURL, configuration: configuration) { _, _ in }
    }

    private func resolveApplicationURL(for application: IDEApplication) -> URL? {
        for bundleIdentifier in application.candidateBundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                return url
            }
        }

        for applicationName in application.candidateApplicationNames {
            if let path = NSWorkspace.shared.fullPath(forApplication: applicationName) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }

        return nil
    }
}

private extension IDEApplication {
    var candidateBundleIdentifiers: [String] {
        switch self {
        case .xcode:
            return ["com.apple.dt.Xcode"]
        case .visualStudioCode:
            return ["com.microsoft.VSCode"]
        case .cursor:
            return ["com.todesktop.230313mzl4w4u92"]
        case .codex:
            // HUMHERE: Confirm the production Codex macOS bundle identifier if local app discovery should prefer something other than the app name.
            return ["com.openai.codex"]
        }
    }

    var candidateApplicationNames: [String] {
        switch self {
        case .xcode:
            return ["Xcode"]
        case .visualStudioCode:
            return ["Visual Studio Code"]
        case .cursor:
            return ["Cursor"]
        case .codex:
            return ["Codex"]
        }
    }
}
