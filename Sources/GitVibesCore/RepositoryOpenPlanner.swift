import Foundation

public enum IDEApplication: String, CaseIterable, Equatable, Identifiable, Sendable {
    case xcode
    case visualStudioCode
    case cursor
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .xcode:
            return "Xcode"
        case .visualStudioCode:
            return "VS Code"
        case .cursor:
            return "Cursor"
        case .codex:
            return "Codex"
        }
    }
}

public struct IDEOpenOption: Equatable, Identifiable, Sendable {
    public let application: IDEApplication
    public let targetPath: String
    public let reason: String
    public let isRecommended: Bool

    public init(application: IDEApplication, targetPath: String, reason: String, isRecommended: Bool) {
        self.application = application
        self.targetPath = targetPath
        self.reason = reason
        self.isRecommended = isRecommended
    }

    public var id: String {
        "\(application.rawValue):\(targetPath)"
    }
}

public struct RepositoryOpenPlan: Equatable, Sendable {
    public let repositoryRootPath: String
    public let options: [IDEOpenOption]

    public init(repositoryRootPath: String, options: [IDEOpenOption]) {
        self.repositoryRootPath = repositoryRootPath
        self.options = options
    }
}

public protocol RepositoryOpenPlanning: Sendable {
    func planOpenOptions(for repositoryRoot: URL) throws -> RepositoryOpenPlan
}

public struct RepositoryOpenPlanner: RepositoryOpenPlanning, @unchecked Sendable {
    private let fileManager: FileManager
    private let maxSearchDepth: Int

    public init(fileManager: FileManager = .default, maxSearchDepth: Int = 3) {
        self.fileManager = fileManager
        self.maxSearchDepth = maxSearchDepth
    }

    public func planOpenOptions(for repositoryRoot: URL) throws -> RepositoryOpenPlan {
        let xcodeWorkspace = firstMatch(in: repositoryRoot, extensions: ["xcworkspace"])
        let xcodeProject = firstMatch(in: repositoryRoot, extensions: ["xcodeproj"])
        let codeWorkspace = firstMatch(in: repositoryRoot, extensions: ["code-workspace"])
        let swiftPackage = firstMatch(in: repositoryRoot, fileNames: ["Package.swift"])
        let nodePackage = firstMatch(in: repositoryRoot, fileNames: ["package.json"])

        let xcodeTargetURL = xcodeWorkspace
            ?? xcodeProject
            ?? swiftPackage?.deletingLastPathComponent()
            ?? repositoryRoot
        let editorTargetURL = codeWorkspace
            ?? nodePackage?.deletingLastPathComponent()
            ?? repositoryRoot
        // HUMHERE: Confirm whether Swift packages without Xcode metadata should keep preferring Xcode, or if the default recommendation should become editor-first.
        let recommendedApplication: IDEApplication = if xcodeWorkspace != nil || xcodeProject != nil || swiftPackage != nil {
            .xcode
        } else if codeWorkspace != nil || nodePackage != nil {
            .visualStudioCode
        } else {
            .visualStudioCode
        }

        let xcodeReason = if let xcodeWorkspace {
            "Open detected Xcode workspace \(xcodeWorkspace.lastPathComponent)."
        } else if let xcodeProject {
            "Open detected Xcode project \(xcodeProject.lastPathComponent)."
        } else if let swiftPackage {
            "Open \(swiftPackage.deletingLastPathComponent().lastPathComponent) because Package.swift was detected."
        } else {
            "Open the repository root in Xcode."
        }

        let editorReason = if let codeWorkspace {
            "Open detected editor workspace \(codeWorkspace.lastPathComponent)."
        } else if let nodePackage {
            "Open \(nodePackage.deletingLastPathComponent().lastPathComponent) because package.json was detected."
        } else {
            "Open the repository root in a code editor."
        }

        let options = [
            IDEOpenOption(
                application: .xcode,
                targetPath: xcodeTargetURL.path,
                reason: xcodeReason,
                isRecommended: recommendedApplication == .xcode
            ),
            IDEOpenOption(
                application: .visualStudioCode,
                targetPath: editorTargetURL.path,
                reason: editorReason,
                isRecommended: recommendedApplication == .visualStudioCode
            ),
            IDEOpenOption(
                application: .cursor,
                targetPath: editorTargetURL.path,
                reason: editorReason,
                isRecommended: false
            ),
            IDEOpenOption(
                application: .codex,
                targetPath: editorTargetURL.path,
                reason: editorReason,
                isRecommended: false
            )
        ]

        return RepositoryOpenPlan(repositoryRootPath: repositoryRoot.path, options: options)
    }

    private func firstMatch(in repositoryRoot: URL, extensions: Set<String>) -> URL? {
        firstMatch(in: repositoryRoot, extensions: extensions, fileNames: [])
    }

    private func firstMatch(in repositoryRoot: URL, fileNames: Set<String>) -> URL? {
        firstMatch(in: repositoryRoot, extensions: [], fileNames: fileNames)
    }

    private func firstMatch(in repositoryRoot: URL, extensions: Set<String>, fileNames: Set<String>) -> URL? {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: repositoryRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        let rootDepth = repositoryRoot.standardizedFileURL.pathComponents.count
        var matches: [URL] = []

        for case let candidate as URL in enumerator {
            let standardizedCandidate = candidate.standardizedFileURL
            let depth = standardizedCandidate.pathComponents.count - rootDepth
            if depth > maxSearchDepth {
                enumerator.skipDescendants()
                continue
            }

            if extensions.contains(standardizedCandidate.pathExtension.lowercased())
                || fileNames.contains(standardizedCandidate.lastPathComponent) {
                matches.append(standardizedCandidate)
            }
        }

        return matches.sorted { lhs, rhs in
            if lhs.pathComponents.count == rhs.pathComponents.count {
                return lhs.path < rhs.path
            }
            return lhs.pathComponents.count < rhs.pathComponents.count
        }.first
    }
}
