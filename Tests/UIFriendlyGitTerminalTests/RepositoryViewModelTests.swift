import Foundation
import GitVibesCore
import Testing
@testable import UIFriendlyGitTerminal

@MainActor
@Test func refreshLoadsRepositoryAndUpdatesRecentProjects() async throws {
    let snapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-one",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true),
            GitBranch(name: "feature/login", isCurrent: false)
        ],
        changedFiles: []
    )
    let service = MockGitRepositoryService(loadSnapshots: [snapshot])
    let store = InMemoryRecentRepositoryStore()
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: store)

    viewModel.selectedFolderURL = URL(fileURLWithPath: "/tmp/projects/repo-one", isDirectory: true)
    viewModel.refresh()
    await waitUntilIdle(viewModel)

    #expect(viewModel.repositoryPath == "/tmp/projects/repo-one")
    #expect(viewModel.recentRepositories == [RecentRepository(path: "/tmp/projects/repo-one")])
    #expect(viewModel.mergeSourceBranchName == "main")
    #expect(viewModel.mergeTargetBranchName == "feature/login")
}

@MainActor
@Test func mergeSelectedBranchesSwitchesTargetBeforeMergingSource() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-two",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true),
            GitBranch(name: "release", isCurrent: false),
            GitBranch(name: "feature/login", isCurrent: false)
        ],
        changedFiles: []
    )
    let mergedSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-two",
        currentBranch: "release",
        branches: [
            GitBranch(name: "release", isCurrent: true),
            GitBranch(name: "main", isCurrent: false),
            GitBranch(name: "feature/login", isCurrent: false)
        ],
        changedFiles: []
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [mergedSnapshot],
        performResults: [
            .success(GitCommandResult(standardOutput: "", standardError: "", terminationStatus: 0)),
            .success(GitCommandResult(standardOutput: "Already up to date.", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.snapshot = initialSnapshot
    viewModel.selectedBranchName = "main"
    viewModel.mergeSourceBranchName = "main"
    viewModel.mergeTargetBranchName = "release"

    viewModel.mergeSelectedBranches()
    await waitUntilIdle(viewModel)

    #expect(service.performedCommands == [
        .switchBranch(name: "release"),
        .merge(branch: "main")
    ])
    #expect(viewModel.snapshot?.currentBranch == "release")
}

@MainActor
@Test func cloneRepositoryLoadsClonedSnapshotAndTracksItAsRecent() async throws {
    let snapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/cloned-repo",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true),
            GitBranch(name: "develop", isCurrent: false)
        ],
        changedFiles: []
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [snapshot],
        clonedRepositoryURL: URL(fileURLWithPath: "/tmp/projects/cloned-repo", isDirectory: true)
    )
    let store = InMemoryRecentRepositoryStore()
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: store)
    viewModel.cloneRepositoryURL = "https://github.com/EditFred/cloned-repo.git"
    viewModel.cloneDestinationURL = URL(fileURLWithPath: "/tmp/projects", isDirectory: true)

    viewModel.cloneRepository()
    await waitUntilIdle(viewModel)

    #expect(service.cloneCalls == [
        MockGitRepositoryService.CloneCall(
            repositoryURL: "https://github.com/EditFred/cloned-repo.git",
            destinationFolder: URL(fileURLWithPath: "/tmp/projects", isDirectory: true)
        )
    ])
    #expect(viewModel.selectedFolderURL?.path == "/tmp/projects/cloned-repo")
    #expect(viewModel.recentRepositories == [RecentRepository(path: "/tmp/projects/cloned-repo")])
}

@MainActor
private func waitUntilIdle(_ viewModel: RepositoryViewModel) async {
    for _ in 0..<50 {
        if !viewModel.isBusy {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private final class MockGitRepositoryService: GitRepositoryServicing, @unchecked Sendable {
    struct CloneCall: Equatable {
        let repositoryURL: String
        let destinationFolder: URL
    }

    var loadSnapshots: [GitRepositorySnapshot]
    var performResults: [Result<GitCommandResult, Error>]
    var clonedRepositoryURL: URL
    private(set) var performedCommands: [GitCommand] = []
    private(set) var cloneCalls: [CloneCall] = []

    init(
        loadSnapshots: [GitRepositorySnapshot],
        performResults: [Result<GitCommandResult, Error>] = [],
        clonedRepositoryURL: URL = URL(fileURLWithPath: "/tmp/projects/cloned", isDirectory: true)
    ) {
        self.loadSnapshots = loadSnapshots
        self.performResults = performResults
        self.clonedRepositoryURL = clonedRepositoryURL
    }

    func resolveRepositoryRoot(for folder: URL) throws -> URL {
        folder
    }

    func loadSnapshot(for folder: URL) throws -> GitRepositorySnapshot {
        loadSnapshots.removeFirst()
    }

    func perform(_ command: GitCommand, in folder: URL) throws -> GitCommandResult {
        performedCommands.append(command)
        return try performResults.removeFirst().get()
    }

    func cloneRepository(from repositoryURL: String, into destinationFolder: URL) throws -> URL {
        cloneCalls.append(CloneCall(repositoryURL: repositoryURL, destinationFolder: destinationFolder))
        return clonedRepositoryURL
    }
}

private final class InMemoryRecentRepositoryStore: RecentRepositoryStoring {
    private var items: [RecentRepository] = []

    func load() -> [RecentRepository] {
        items
    }

    func add(_ repositoryPath: String) {
        items.removeAll { $0.path == repositoryPath }
        items.insert(RecentRepository(path: repositoryPath), at: 0)
    }
}
