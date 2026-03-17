import Foundation

public struct GitBranch: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isCurrent: Bool

    public init(name: String, isCurrent: Bool) {
        self.id = name
        self.name = name
        self.isCurrent = isCurrent
    }
}

public struct GitChangedFile: Identifiable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let status: String
    public let isStaged: Bool
    public let hasUnstagedChanges: Bool

    public var canStage: Bool {
        hasUnstagedChanges || !isStaged
    }

    public init(
        path: String,
        status: String,
        isStaged: Bool = false,
        hasUnstagedChanges: Bool = true
    ) {
        self.id = "\(status):\(path)"
        self.path = path
        self.status = status
        self.isStaged = isStaged
        self.hasUnstagedChanges = hasUnstagedChanges
    }
}

public struct GitCommandResult: Equatable, Sendable {
    public let standardOutput: String
    public let standardError: String
    public let terminationStatus: Int32

    public init(standardOutput: String, standardError: String, terminationStatus: Int32) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.terminationStatus = terminationStatus
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    public var succeeded: Bool {
        terminationStatus == 0
    }
}

public struct GitRepositorySnapshot: Equatable, Sendable {
    public let rootPath: String
    public let currentBranch: String
    public let branches: [GitBranch]
    public let changedFiles: [GitChangedFile]

    public init(rootPath: String, currentBranch: String, branches: [GitBranch], changedFiles: [GitChangedFile]) {
        self.rootPath = rootPath
        self.currentBranch = currentBranch
        self.branches = branches
        self.changedFiles = changedFiles
    }
}
