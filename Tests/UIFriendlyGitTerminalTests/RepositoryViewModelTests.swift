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
    let npmService = MockNPMProjectService(projectInfo: NPMProjectInfo(
        projectDirectoryPath: snapshot.rootPath,
        availableScripts: [.test, .build, .start],
        suggestedBrowserURL: "http://localhost:4173"
    ))
    let openPlanner = MockRepositoryOpenPlanner(plan: RepositoryOpenPlan(
        repositoryRootPath: snapshot.rootPath,
        options: [
            IDEOpenOption(
                application: .xcode,
                targetPath: "/tmp/projects/repo-one/UIFriendlyGitTerminal.xcodeproj",
                reason: "Open detected Xcode project UIFriendlyGitTerminal.xcodeproj.",
                isRecommended: true
            )
        ]
    ))
    let projectOpener = MockIDEProjectOpener(availableApplications: [.xcode])
    let viewModel = RepositoryViewModel(
        service: service,
        npmService: npmService,
        openPlanner: openPlanner,
        recentRepositoryStore: store,
        projectOpener: projectOpener
    )

    viewModel.selectedFolderURL = URL(fileURLWithPath: "/tmp/projects/repo-one", isDirectory: true)
    viewModel.refresh()
    await waitUntilIdle(viewModel)

    #expect(viewModel.repositoryPath == "/tmp/projects/repo-one")
    #expect(viewModel.recentRepositories == [RecentRepository(path: "/tmp/projects/repo-one")])
    #expect(viewModel.mergeSourceBranchName == "main")
    #expect(viewModel.mergeTargetBranchName == "feature/login")
    #expect(viewModel.npmBrowserURL == "http://localhost:4173")
    #expect(viewModel.supports(.start))
    #expect(viewModel.openOptions == [
        RepositoryViewModel.OpenOption(
            application: .xcode,
            targetPath: "/tmp/projects/repo-one/UIFriendlyGitTerminal.xcodeproj",
            reason: "Open detected Xcode project UIFriendlyGitTerminal.xcodeproj.",
            isRecommended: true,
            isAvailable: true
        )
    ])
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
    #expect(viewModel.postMergeDeleteBranchName == nil)
}

@MainActor
@Test func mergeIntoMainOffersDeletingMergedBranch() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-merge-main",
        currentBranch: "feature/login",
        branches: [
            GitBranch(name: "main", isCurrent: false),
            GitBranch(name: "feature/login", isCurrent: true)
        ],
        changedFiles: []
    )
    let mergedSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-merge-main",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true),
            GitBranch(name: "feature/login", isCurrent: false)
        ],
        changedFiles: []
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [mergedSnapshot],
        performResults: [
            .success(GitCommandResult(standardOutput: "", standardError: "", terminationStatus: 0)),
            .success(GitCommandResult(standardOutput: "Merge made by the 'ort' strategy.", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.snapshot = initialSnapshot
    viewModel.selectedBranchName = "feature/login"
    viewModel.mergeSourceBranchName = "feature/login"
    viewModel.mergeTargetBranchName = "main"

    viewModel.mergeSelectedBranches()
    await waitUntilIdle(viewModel)

    #expect(viewModel.snapshot?.currentBranch == "main")
    #expect(viewModel.postMergeDeleteBranchName == "feature/login")
}

@MainActor
@Test func deleteMergedBranchRequiresExactTypedConfirmation() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-delete-guard",
        currentBranch: "feature/login",
        branches: [
            GitBranch(name: "main", isCurrent: false),
            GitBranch(name: "feature/login", isCurrent: true)
        ],
        changedFiles: []
    )
    let mergedSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-delete-guard",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true),
            GitBranch(name: "feature/login", isCurrent: false)
        ],
        changedFiles: []
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [mergedSnapshot],
        performResults: [
            .success(GitCommandResult(standardOutput: "", standardError: "", terminationStatus: 0)),
            .success(GitCommandResult(standardOutput: "Merge made by the 'ort' strategy.", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.snapshot = initialSnapshot
    viewModel.mergeSourceBranchName = "feature/login"
    viewModel.mergeTargetBranchName = "main"

    viewModel.mergeSelectedBranches()
    await waitUntilIdle(viewModel)

    viewModel.deleteMergedBranchConfirmationText = "feature/login-2"

    viewModel.deleteMergedBranch()

    #expect(viewModel.errorMessage == "Type the branch name exactly to delete it.")
    #expect(service.performedCommands == [
        .switchBranch(name: "main"),
        .merge(branch: "feature/login")
    ])
}

@MainActor
@Test func deleteMergedBranchRunsDeleteCommandAndClearsOffer() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-delete-merged",
        currentBranch: "feature/login",
        branches: [
            GitBranch(name: "main", isCurrent: false),
            GitBranch(name: "feature/login", isCurrent: true)
        ],
        changedFiles: []
    )
    let mergedSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-delete-merged",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true),
            GitBranch(name: "feature/login", isCurrent: false)
        ],
        changedFiles: []
    )
    let refreshedSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-delete-merged",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: []
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [mergedSnapshot, refreshedSnapshot],
        performResults: [
            .success(GitCommandResult(standardOutput: "", standardError: "", terminationStatus: 0)),
            .success(GitCommandResult(standardOutput: "Merge made by the 'ort' strategy.", standardError: "", terminationStatus: 0)),
            .success(GitCommandResult(standardOutput: "Deleted branch feature/login (was abc123).", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.snapshot = initialSnapshot
    viewModel.mergeSourceBranchName = "feature/login"
    viewModel.mergeTargetBranchName = "main"

    viewModel.mergeSelectedBranches()
    await waitUntilIdle(viewModel)

    viewModel.deleteMergedBranchConfirmationText = "feature/login"
    viewModel.isDeleteMergedBranchConfirmationPresented = true

    viewModel.deleteMergedBranch()
    await waitUntilIdle(viewModel)

    #expect(service.performedCommands == [
        .switchBranch(name: "main"),
        .merge(branch: "feature/login"),
        .deleteBranch(name: "feature/login")
    ])
    #expect(viewModel.postMergeDeleteBranchName == nil)
    #expect(viewModel.isDeleteMergedBranchConfirmationPresented == false)
}

@MainActor
@Test func runNPMCommandRunsRequestedScriptAndRefreshesSnapshot() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-five",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: []
    )
    let refreshedSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-five",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: [
            GitChangedFile(path: "dist/index.js", status: "M")
        ]
    )
    let service = MockGitRepositoryService(loadSnapshots: [initialSnapshot, refreshedSnapshot])
    let npmService = MockNPMProjectService(
        projectInfo: NPMProjectInfo(
            projectDirectoryPath: initialSnapshot.rootPath,
            availableScripts: [.build],
            suggestedBrowserURL: "http://localhost:3000"
        ),
        runResults: [
            .success(GitCommandResult(standardOutput: "build complete", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(
        service: service,
        npmService: npmService,
        recentRepositoryStore: InMemoryRecentRepositoryStore()
    )
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.refresh()
    await waitUntilIdle(viewModel)
    viewModel.runNPMCommand(.build)
    await waitUntilIdle(viewModel)

    #expect(npmService.runCommands == [.build])
    #expect(viewModel.changedFiles == refreshedSnapshot.changedFiles)
}

@MainActor
@Test func runNPMStartLaunchesInBackground() async throws {
    let snapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-six",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: []
    )
    let service = MockGitRepositoryService(loadSnapshots: [snapshot, snapshot])
    let npmService = MockNPMProjectService(
        projectInfo: NPMProjectInfo(
            projectDirectoryPath: snapshot.rootPath,
            availableScripts: [.start],
            suggestedBrowserURL: "http://localhost:5173"
        ),
        launchedProcessIdentifier: 4242
    )
    let viewModel = RepositoryViewModel(
        service: service,
        npmService: npmService,
        recentRepositoryStore: InMemoryRecentRepositoryStore()
    )
    viewModel.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
    viewModel.refresh()
    await waitUntilIdle(viewModel)

    viewModel.runNPMCommand(.start)
    await waitUntilIdle(viewModel)

    #expect(npmService.launchCommands == [.start])
    #expect(viewModel.outputLog.contains("PID 4242"))
}

@MainActor
@Test func openNPMProjectInBrowserNormalizesLocalhostURL() async throws {
    let snapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-seven",
        currentBranch: "main",
        branches: [GitBranch(name: "main", isCurrent: true)],
        changedFiles: []
    )
    let service = MockGitRepositoryService(loadSnapshots: [snapshot])
    let npmService = MockNPMProjectService(
        projectInfo: NPMProjectInfo(
            projectDirectoryPath: "/tmp/projects/repo-seven",
            availableScripts: [.start],
            suggestedBrowserURL: "localhost:3000"
        )
    )
    let browserOpener = MockBrowserOpener()
    let viewModel = RepositoryViewModel(
        service: service,
        npmService: npmService,
        recentRepositoryStore: InMemoryRecentRepositoryStore(),
        browserOpener: browserOpener
    )
    viewModel.selectedFolderURL = URL(fileURLWithPath: "/tmp/projects/repo-seven", isDirectory: true)
    viewModel.runTaskForTestsToLoadNPM()
    await waitUntilIdle(viewModel)
    viewModel.npmBrowserURL = "localhost:3000"

    viewModel.openNPMProjectInBrowser()

    #expect(browserOpener.openedURLs == ["http://localhost:3000"])
}

@MainActor
@Test func openProjectUsesPlannedTargetForSelectedApplication() async throws {
    let snapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-open",
        currentBranch: "main",
        branches: [GitBranch(name: "main", isCurrent: true)],
        changedFiles: []
    )
    let service = MockGitRepositoryService(loadSnapshots: [snapshot])
    let projectOpener = MockIDEProjectOpener(availableApplications: [.xcode, .visualStudioCode])
    let viewModel = RepositoryViewModel(
        service: service,
        openPlanner: MockRepositoryOpenPlanner(plan: RepositoryOpenPlan(
            repositoryRootPath: snapshot.rootPath,
            options: [
                IDEOpenOption(
                    application: .xcode,
                    targetPath: "/tmp/projects/repo-open/App.xcodeproj",
                    reason: "Open detected Xcode project App.xcodeproj.",
                    isRecommended: true
                ),
                IDEOpenOption(
                    application: .visualStudioCode,
                    targetPath: "/tmp/projects/repo-open",
                    reason: "Open the repository root in a code editor.",
                    isRecommended: false
                )
            ]
        )),
        recentRepositoryStore: InMemoryRecentRepositoryStore(),
        projectOpener: projectOpener
    )
    viewModel.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
    viewModel.refresh()
    await waitUntilIdle(viewModel)

    viewModel.openProject(with: .xcode)

    #expect(projectOpener.openCalls == [
        MockIDEProjectOpener.OpenCall(
            targetURL: URL(fileURLWithPath: "/tmp/projects/repo-open/App.xcodeproj"),
            application: .xcode
        )
    ])
}

@MainActor
@Test func openRecommendedProjectFallsBackToInstalledOption() async throws {
    let snapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-open-primary",
        currentBranch: "main",
        branches: [GitBranch(name: "main", isCurrent: true)],
        changedFiles: []
    )
    let service = MockGitRepositoryService(loadSnapshots: [snapshot])
    let projectOpener = MockIDEProjectOpener(availableApplications: [.visualStudioCode])
    let viewModel = RepositoryViewModel(
        service: service,
        openPlanner: MockRepositoryOpenPlanner(plan: RepositoryOpenPlan(
            repositoryRootPath: snapshot.rootPath,
            options: [
                IDEOpenOption(
                    application: .xcode,
                    targetPath: "/tmp/projects/repo-open-primary/App.xcodeproj",
                    reason: "Open detected Xcode project App.xcodeproj.",
                    isRecommended: true
                ),
                IDEOpenOption(
                    application: .visualStudioCode,
                    targetPath: "/tmp/projects/repo-open-primary",
                    reason: "Open the repository root in a code editor.",
                    isRecommended: false
                )
            ]
        )),
        recentRepositoryStore: InMemoryRecentRepositoryStore(),
        projectOpener: projectOpener
    )
    viewModel.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
    viewModel.refresh()
    await waitUntilIdle(viewModel)

    #expect(viewModel.primaryOpenButtonTitle == "Open in VS Code")

    viewModel.openRecommendedProject()

    #expect(projectOpener.openCalls == [
        MockIDEProjectOpener.OpenCall(
            targetURL: URL(fileURLWithPath: "/tmp/projects/repo-open-primary"),
            application: .visualStudioCode
        )
    ])
}

@MainActor
@Test func openProjectReportsUnavailableApplication() async throws {
    let snapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-open-two",
        currentBranch: "main",
        branches: [GitBranch(name: "main", isCurrent: true)],
        changedFiles: []
    )
    let service = MockGitRepositoryService(loadSnapshots: [snapshot])
    let projectOpener = MockIDEProjectOpener(availableApplications: [])
    let viewModel = RepositoryViewModel(
        service: service,
        openPlanner: MockRepositoryOpenPlanner(plan: RepositoryOpenPlan(
            repositoryRootPath: snapshot.rootPath,
            options: [
                IDEOpenOption(
                    application: .cursor,
                    targetPath: "/tmp/projects/repo-open-two",
                    reason: "Open the repository root in a code editor.",
                    isRecommended: false
                )
            ]
        )),
        recentRepositoryStore: InMemoryRecentRepositoryStore(),
        projectOpener: projectOpener
    )
    viewModel.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
    viewModel.refresh()
    await waitUntilIdle(viewModel)

    viewModel.openProject(with: .cursor)

    #expect(viewModel.errorMessage == "Cursor is not available on this Mac.")
    #expect(projectOpener.openCalls.isEmpty)
}

@MainActor
@Test func stageAllFilesRunsAddAllAndRefreshesSnapshot() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-three",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: [
            GitChangedFile(path: "README.md", status: "M")
        ]
    )
    let refreshedSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-three",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: []
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [refreshedSnapshot],
        performResults: [
            .success(GitCommandResult(standardOutput: "", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.snapshot = initialSnapshot

    viewModel.stageAllFiles()
    await waitUntilIdle(viewModel)

    #expect(service.performedCommands == [.addAll])
    #expect(viewModel.changedFiles.isEmpty)
}

@MainActor
@Test func stageFilesRunsAddWithNormalizedPaths() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-four",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: [
            GitChangedFile(path: "README.md", status: "M"),
            GitChangedFile(path: "Sources/UIFriendlyGitTerminal/ContentView.swift", status: "A")
        ]
    )
    let refreshedSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-four",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: initialSnapshot.changedFiles
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [refreshedSnapshot],
        performResults: [
            .success(GitCommandResult(standardOutput: "", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.snapshot = initialSnapshot

    viewModel.stageFiles([" README.md ", "Sources/UIFriendlyGitTerminal/ContentView.swift", "README.md"])
    await waitUntilIdle(viewModel)

    #expect(service.performedCommands == [
        .add(paths: ["README.md", "Sources/UIFriendlyGitTerminal/ContentView.swift"])
    ])
}

@MainActor
@Test func commitRequiresStagedChangesBeforeRunningGitCommit() async throws {
    let snapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-commit-guard",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: [
            GitChangedFile(path: "README.md", status: "M", isStaged: false, hasUnstagedChanges: true)
        ]
    )
    let service = MockGitRepositoryService(loadSnapshots: [])
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
    viewModel.snapshot = snapshot
    viewModel.commitMessage = "Ship it"

    viewModel.commit()

    #expect(service.performedCommands.isEmpty)
    #expect(viewModel.errorMessage == "Add files before committing.")
}

@MainActor
@Test func stageAllFilesAndCommitRunsBothCommandsAndClearsMessage() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-stage-and-commit",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: [
            GitChangedFile(path: "README.md", status: "M", isStaged: false, hasUnstagedChanges: true)
        ]
    )
    let refreshedSnapshot = GitRepositorySnapshot(
        rootPath: initialSnapshot.rootPath,
        currentBranch: "main",
        branches: initialSnapshot.branches,
        changedFiles: []
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [refreshedSnapshot],
        performResults: [
            .success(GitCommandResult(standardOutput: "", standardError: "", terminationStatus: 0)),
            .success(GitCommandResult(standardOutput: "[main abc123] Ship it", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.snapshot = initialSnapshot
    viewModel.commitMessage = "Ship it"

    viewModel.stageAllFilesAndCommit()
    await waitUntilIdle(viewModel)

    #expect(service.performedCommands == [
        .addAll,
        .commit(message: "Ship it")
    ])
    #expect(viewModel.commitMessage.isEmpty)
}

@MainActor
@Test func stageFilesAndCommitStagesNormalizedPathsThenCommits() async throws {
    let initialSnapshot = GitRepositorySnapshot(
        rootPath: "/tmp/projects/repo-select-and-commit",
        currentBranch: "main",
        branches: [
            GitBranch(name: "main", isCurrent: true)
        ],
        changedFiles: [
            GitChangedFile(path: "README.md", status: "M", isStaged: false, hasUnstagedChanges: true),
            GitChangedFile(path: "Sources/UIFriendlyGitTerminal/ContentView.swift", status: "A", isStaged: false, hasUnstagedChanges: true)
        ]
    )
    let refreshedSnapshot = GitRepositorySnapshot(
        rootPath: initialSnapshot.rootPath,
        currentBranch: "main",
        branches: initialSnapshot.branches,
        changedFiles: []
    )
    let service = MockGitRepositoryService(
        loadSnapshots: [refreshedSnapshot],
        performResults: [
            .success(GitCommandResult(standardOutput: "", standardError: "", terminationStatus: 0)),
            .success(GitCommandResult(standardOutput: "[main def456] Ship selected", standardError: "", terminationStatus: 0))
        ]
    )
    let viewModel = RepositoryViewModel(service: service, recentRepositoryStore: InMemoryRecentRepositoryStore())
    viewModel.selectedFolderURL = URL(fileURLWithPath: initialSnapshot.rootPath, isDirectory: true)
    viewModel.snapshot = initialSnapshot
    viewModel.commitMessage = "Ship selected"

    viewModel.stageFilesAndCommit([" README.md ", "Sources/UIFriendlyGitTerminal/ContentView.swift", "README.md"])
    await waitUntilIdle(viewModel)

    #expect(service.performedCommands == [
        .add(paths: ["README.md", "Sources/UIFriendlyGitTerminal/ContentView.swift"]),
        .commit(message: "Ship selected")
    ])
    #expect(viewModel.commitMessage.isEmpty)
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

private final class MockNPMProjectService: NPMProjectServicing, @unchecked Sendable {
    var projectInfo: NPMProjectInfo?
    var runResults: [Result<GitCommandResult, Error>]
    var launchedProcessIdentifier: ProcessIdentifier
    private(set) var runCommands: [NPMCommand] = []
    private(set) var launchCommands: [NPMCommand] = []

    init(
        projectInfo: NPMProjectInfo?,
        runResults: [Result<GitCommandResult, Error>] = [],
        launchedProcessIdentifier: ProcessIdentifier = 1337
    ) {
        self.projectInfo = projectInfo
        self.runResults = runResults
        self.launchedProcessIdentifier = launchedProcessIdentifier
    }

    func inspectProject(in repositoryRoot: URL) throws -> NPMProjectInfo? {
        projectInfo
    }

    func run(_ command: NPMCommand, in projectDirectory: URL) throws -> GitCommandResult {
        runCommands.append(command)
        return try runResults.removeFirst().get()
    }

    func launch(_ command: NPMCommand, in projectDirectory: URL) throws -> ProcessIdentifier {
        launchCommands.append(command)
        return launchedProcessIdentifier
    }
}

private final class MockBrowserOpener: BrowserOpening, @unchecked Sendable {
    private(set) var openedURLs: [String] = []

    func open(_ url: URL) {
        openedURLs.append(url.absoluteString)
    }
}

private final class MockRepositoryOpenPlanner: RepositoryOpenPlanning, @unchecked Sendable {
    var plan: RepositoryOpenPlan

    init(plan: RepositoryOpenPlan) {
        self.plan = plan
    }

    func planOpenOptions(for repositoryRoot: URL) throws -> RepositoryOpenPlan {
        plan
    }
}

private final class MockIDEProjectOpener: IDEProjectOpening, @unchecked Sendable {
    struct OpenCall: Equatable {
        let targetURL: URL
        let application: IDEApplication
    }

    let availableApplications: Set<IDEApplication>
    private(set) var openCalls: [OpenCall] = []

    init(availableApplications: Set<IDEApplication>) {
        self.availableApplications = availableApplications
    }

    func isAvailable(_ application: IDEApplication) -> Bool {
        availableApplications.contains(application)
    }

    func openProject(at targetURL: URL, with application: IDEApplication) throws {
        openCalls.append(OpenCall(targetURL: targetURL, application: application))
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

private extension RepositoryViewModel {
    func runTaskForTestsToLoadNPM() {
        if selectedFolderURL == nil, let snapshot {
            selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
        }
        refresh()
    }
}
