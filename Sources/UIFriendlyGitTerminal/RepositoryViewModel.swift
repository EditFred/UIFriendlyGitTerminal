import AppKit
import Foundation
import GitVibesCore
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    struct OpenOption: Identifiable, Equatable {
        let application: IDEApplication
        let targetPath: String
        let reason: String
        let isRecommended: Bool
        let isAvailable: Bool

        var id: String { application.id }
    }

    @Published var selectedFolderURL: URL?
    @Published var snapshot: GitRepositorySnapshot?
    @Published private(set) var npmProjectInfo: NPMProjectInfo?
    @Published private(set) var openOptions: [OpenOption] = []
    @Published var npmBrowserURL = ""
    @Published var selectedBranchName = ""
    @Published var mergeSourceBranchName = ""
    @Published var mergeTargetBranchName = ""
    @Published private(set) var postMergeDeleteBranchName: String?
    @Published var deleteMergedBranchConfirmationText = ""
    @Published var isDeleteMergedBranchConfirmationPresented = false
    @Published var commitMessage = ""
    @Published var cloneRepositoryURL = ""
    @Published var cloneDestinationURL: URL?
    @Published var outputLog = "Choose a local repository to begin.\n"
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published private(set) var recentRepositories: [RecentRepository]

    private let service: any GitRepositoryServicing
    private let npmService: any NPMProjectServicing
    private let openPlanner: any RepositoryOpenPlanning
    private let recentRepositoryStore: any RecentRepositoryStoring
    private let browserOpener: any BrowserOpening
    private let projectOpener: any IDEProjectOpening

    init(
        service: any GitRepositoryServicing = GitRepositoryService(),
        npmService: any NPMProjectServicing = NPMProjectService(),
        openPlanner: any RepositoryOpenPlanning = RepositoryOpenPlanner(),
        recentRepositoryStore: any RecentRepositoryStoring = UserDefaultsRecentRepositoryStore(),
        browserOpener: any BrowserOpening = BrowserOpener(),
        projectOpener: any IDEProjectOpening = WorkspaceIDEProjectOpener()
    ) {
        self.service = service
        self.npmService = npmService
        self.openPlanner = openPlanner
        self.recentRepositoryStore = recentRepositoryStore
        self.browserOpener = browserOpener
        self.projectOpener = projectOpener
        self.recentRepositories = recentRepositoryStore.load()
    }

    var repositoryPath: String {
        snapshot?.rootPath ?? selectedFolderURL?.path ?? "No repository selected"
    }

    var branches: [GitBranch] {
        snapshot?.branches ?? []
    }

    var changedFiles: [GitChangedFile] {
        snapshot?.changedFiles ?? []
    }

    var stageableFiles: [GitChangedFile] {
        changedFiles.filter(\.canStage)
    }

    var hasStagedChanges: Bool {
        changedFiles.contains(where: \.isStaged)
    }

    var hasNPMProject: Bool {
        npmProjectInfo != nil
    }

    var canConfirmMergedBranchDeletion: Bool {
        normalizedDeleteMergedBranchConfirmationText == postMergeDeleteBranchName
    }

    var primaryOpenOption: OpenOption? {
        if let recommendedAvailableOption = openOptions.first(where: { $0.isRecommended && $0.isAvailable }) {
            return recommendedAvailableOption
        }

        if let availableOption = openOptions.first(where: \.isAvailable) {
            return availableOption
        }

        return openOptions.first(where: \.isRecommended) ?? openOptions.first
    }

    var primaryOpenButtonTitle: String {
        guard let option = primaryOpenOption else {
            return "Open"
        }
        return "Open in \(option.application.displayName)"
    }

    func supports(_ command: NPMCommand) -> Bool {
        npmProjectInfo?.availableScripts.contains(command) == true
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Repository"
        panel.message = "Select any folder inside the git repository you want to control."

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolderURL = url
            appendLog("Selected folder: \(url.path)")
            refresh()
        }
    }

    func chooseCloneDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Destination"
        panel.message = "Select the parent folder where the new repository should be cloned."

        if panel.runModal() == .OK, let url = panel.url {
            cloneDestinationURL = url
        }
    }

    func refresh() {
        guard let folder = selectedFolderURL else {
            errorMessage = "Choose a repository first."
            return
        }

        runTask(label: "Refresh") {
            let snapshot = try self.service.loadSnapshot(for: folder)
            await MainActor.run {
                self.applySnapshot(snapshot)
                self.appendLog("Loaded repository at \(snapshot.rootPath)")
            }
        }
    }

    func revealInFinder() {
        guard let url = selectedFolderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openRecommendedProject() {
        guard let option = primaryOpenOption else {
            errorMessage = "Choose a repository first."
            return
        }

        openProject(with: option.application)
    }

    func openProject(with application: IDEApplication) {
        guard let option = openOptions.first(where: { $0.application == application }) else {
            errorMessage = "Choose a repository first."
            return
        }

        guard option.isAvailable else {
            errorMessage = "\(application.displayName) is not available on this Mac."
            return
        }

        do {
            try projectOpener.openProject(
                at: URL(fileURLWithPath: option.targetPath),
                with: application
            )
            appendLog("Open in \(application.displayName)\nOpened \(option.targetPath)")
        } catch {
            errorMessage = error.localizedDescription
            appendLog("Open in \(application.displayName) failed.\n\(error.localizedDescription)")
        }
    }

    func pull() {
        runGitCommand(.pull)
    }

    func push() {
        runGitCommand(.push)
    }

    func stageAllFiles() {
        guard !stageableFiles.isEmpty else {
            errorMessage = "No changed files to add."
            return
        }

        runGitCommand(.addAll)
    }

    func stageFiles(_ paths: [String]) {
        let normalizedPaths = Array(Set(paths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).sorted()
        guard !normalizedPaths.isEmpty else {
            errorMessage = "Choose at least one file to add."
            return
        }

        runGitCommand(.add(paths: normalizedPaths))
    }

    func commit() {
        guard let message = validatedCommitMessage() else {
            return
        }

        guard hasStagedChanges else {
            errorMessage = stageableFiles.isEmpty ? "No staged changes to commit." : "Add files before committing."
            return
        }

        runGitCommand(.commit(message: message)) {
            self.commitMessage = ""
        }
    }

    func stageAllFilesAndCommit() {
        guard let message = validatedCommitMessage() else {
            return
        }

        guard !stageableFiles.isEmpty else {
            errorMessage = hasStagedChanges ? "Files are already staged. Commit them directly." : "No changed files to add."
            return
        }

        runGitCommands([.addAll, .commit(message: message)]) {
            self.commitMessage = ""
        }
    }

    func stageFilesAndCommit(_ paths: [String]) {
        guard let message = validatedCommitMessage() else {
            return
        }

        let normalizedPaths = Array(Set(paths.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).sorted()
        guard !normalizedPaths.isEmpty else {
            errorMessage = "Choose at least one file to add."
            return
        }

        runGitCommands([.add(paths: normalizedPaths), .commit(message: message)]) {
            self.commitMessage = ""
        }
    }

    func switchBranch() {
        guard !selectedBranchName.isEmpty else {
            errorMessage = "Choose a branch to switch to."
            return
        }

        runGitCommand(.switchBranch(name: selectedBranchName))
    }

    func selectRecentRepository(_ repository: RecentRepository) {
        selectedFolderURL = URL(fileURLWithPath: repository.path, isDirectory: true)
        appendLog("Switched to recent repository: \(repository.path)")
        refresh()
    }

    func cloneRepository() {
        let repositoryURL = cloneRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryURL.isEmpty else {
            errorMessage = "Paste an HTTPS or SSH repository URL first."
            return
        }

        guard let destinationFolder = cloneDestinationURL else {
            errorMessage = "Choose a destination folder first."
            return
        }

        runTask(label: "Clone Repository") {
            let repositoryRoot = try self.service.cloneRepository(from: repositoryURL, into: destinationFolder)
            let snapshot = try self.service.loadSnapshot(for: repositoryRoot)

            await MainActor.run {
                self.cloneRepositoryURL = ""
                self.cloneDestinationURL = nil
                self.applySnapshot(snapshot)
                self.appendLog("Cloned \(repositoryURL) into \(snapshot.rootPath)")
            }
        }
    }

    func mergeSelectedBranches() {
        let sourceBranch = mergeSourceBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetBranch = mergeTargetBranchName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !sourceBranch.isEmpty, !targetBranch.isEmpty else {
            errorMessage = "Choose both the source and target branches."
            return
        }

        guard sourceBranch != targetBranch else {
            errorMessage = "Choose two different branches to merge."
            return
        }

        guard let folder = selectedFolderURL else {
            errorMessage = "Choose a repository first."
            return
        }

        let shouldSwitchToTarget = snapshot?.currentBranch != targetBranch

        runTask(label: "Merge") {
            var logEntries: [String] = []
            if shouldSwitchToTarget {
                let switchResult = try self.service.perform(.switchBranch(name: targetBranch), in: folder)
                let switchLog = await MainActor.run { self.render(command: .switchBranch(name: targetBranch), result: switchResult) }
                logEntries.append(switchLog)
            }

            let mergeResult = try self.service.perform(.merge(branch: sourceBranch), in: folder)
            let mergeResultOutput = await MainActor.run {
                let output = self.renderResultOutput(mergeResult, fallback: "Merge completed successfully.")
                return "Merge \(sourceBranch) into \(targetBranch)\n\(output)"
            }
            logEntries.append(mergeResultOutput)

            let snapshot = try self.service.loadSnapshot(for: folder)

            await MainActor.run {
                self.applySnapshot(snapshot)
                self.syncMergeBranchSelections(with: snapshot, preferredSourceBranch: sourceBranch, preferredTargetBranch: targetBranch)
                self.updatePostMergeDeleteBranchCandidate(
                    mergedBranch: sourceBranch,
                    targetBranch: targetBranch,
                    snapshot: snapshot
                )
                self.appendLog(logEntries.joined(separator: "\n\n"))
            }
        }
    }

    func promptToDeleteMergedBranch() {
        guard postMergeDeleteBranchName != nil else { return }
        deleteMergedBranchConfirmationText = ""
        isDeleteMergedBranchConfirmationPresented = true
    }

    func cancelDeleteMergedBranch() {
        deleteMergedBranchConfirmationText = ""
        isDeleteMergedBranchConfirmationPresented = false
    }

    func deleteMergedBranch() {
        guard let branchName = postMergeDeleteBranchName else {
            errorMessage = "There is no merged branch ready to delete."
            return
        }

        guard canConfirmMergedBranchDeletion else {
            errorMessage = "Type the branch name exactly to delete it."
            return
        }

        guard let folder = selectedFolderURL else {
            errorMessage = "Choose a repository first."
            return
        }

        runTask(label: "Delete Branch") {
            let result = try self.service.perform(.deleteBranch(name: branchName), in: folder)
            let snapshot = try self.service.loadSnapshot(for: folder)

            await MainActor.run {
                self.applySnapshot(snapshot)
                self.postMergeDeleteBranchName = nil
                self.cancelDeleteMergedBranch()
                self.appendLog(self.render(command: .deleteBranch(name: branchName), result: result))
            }
        }
    }

    func runNPMCommand(_ command: NPMCommand) {
        guard let projectInfo = npmProjectInfo else {
            errorMessage = "No package.json was found in this repository."
            return
        }

        let projectDirectory = URL(fileURLWithPath: projectInfo.projectDirectoryPath, isDirectory: true)

        if command == .start {
            runTask(label: command.label) {
                let processIdentifier = try self.npmService.launch(command, in: projectDirectory)
                let snapshot = try self.service.loadSnapshot(for: projectDirectory)

                await MainActor.run {
                    self.applySnapshot(snapshot)
                    self.appendLog("\(command.label)\nStarted in background with PID \(processIdentifier).")
                }
            }
            return
        }

        runTask(label: command.label) {
            let result = try self.npmService.run(command, in: projectDirectory)
            let snapshot = try self.service.loadSnapshot(for: projectDirectory)

            await MainActor.run {
                self.applySnapshot(snapshot)
                self.appendLog(self.renderNPM(command: command, result: result))
            }
        }
    }

    func openNPMProjectInBrowser() {
        guard hasNPMProject else {
            errorMessage = "No package.json was found in this repository."
            return
        }

        let trimmedURL = npmBrowserURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            errorMessage = "Enter a browser URL first."
            return
        }

        let normalizedURL = trimmedURL.contains("://") ? trimmedURL : "http://\(trimmedURL)"
        guard let url = URL(string: normalizedURL) else {
            errorMessage = "Enter a valid browser URL."
            return
        }

        browserOpener.open(url)
        appendLog("Open Browser\nOpened \(normalizedURL)")
    }

    private func runGitCommand(_ command: GitCommand, afterSuccess: @escaping @MainActor () -> Void = {}) {
        runGitCommands([command], afterSuccess: afterSuccess)
    }

    private func runGitCommands(_ commands: [GitCommand], afterSuccess: @escaping @MainActor () -> Void = {}) {
        guard let folder = selectedFolderURL else {
            errorMessage = "Choose a repository first."
            return
        }

        let label = commands.last?.label ?? "Git"

        runTask(label: label) {
            var logEntries: [String] = []

            for command in commands {
                let result = try self.service.perform(command, in: folder)
                let logEntry = await MainActor.run {
                    self.render(command: command, result: result)
                }
                logEntries.append(logEntry)
            }

            let snapshot = try self.service.loadSnapshot(for: folder)

            await MainActor.run {
                self.applySnapshot(snapshot)
                self.appendLog(logEntries.joined(separator: "\n\n"))
                afterSuccess()
            }
        }
    }

    private func validatedCommitMessage() -> String? {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "Enter a commit message first."
            return nil
        }

        return message
    }

    private func runTask(label: String, operation: @escaping @Sendable () async throws -> Void) {
        isBusy = true
        errorMessage = nil

        Task {
            do {
                try await operation()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.appendLog("\(label) failed.\n\(error.localizedDescription)")
                }
            }

            await MainActor.run {
                self.isBusy = false
            }
        }
    }

    private func render(command: GitCommand, result: GitCommandResult) -> String {
        "\(command.label)\n\(renderResultOutput(result, fallback: "\(command.label) completed successfully."))"
    }

    private func renderNPM(command: NPMCommand, result: GitCommandResult) -> String {
        "\(command.label)\n\(renderResultOutput(result, fallback: "\(command.label) completed successfully."))"
    }

    private func renderResultOutput(_ result: GitCommandResult, fallback: String) -> String {
        let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? fallback : output
    }

    private var normalizedDeleteMergedBranchConfirmationText: String {
        deleteMergedBranchConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applySnapshot(_ snapshot: GitRepositorySnapshot) {
        if self.snapshot?.rootPath != snapshot.rootPath {
            postMergeDeleteBranchName = nil
            cancelDeleteMergedBranch()
        } else if let postMergeDeleteBranchName,
                  !snapshot.branches.contains(where: { $0.name == postMergeDeleteBranchName }) {
            self.postMergeDeleteBranchName = nil
            cancelDeleteMergedBranch()
        }

        self.snapshot = snapshot
        self.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
        self.selectedBranchName = snapshot.currentBranch
        self.syncMergeBranchSelections(with: snapshot)
        self.rememberRepository(at: snapshot.rootPath)
        self.reloadOpenOptions(for: snapshot)
        self.reloadNPMProjectInfo(for: snapshot)
    }

    private func reloadOpenOptions(for snapshot: GitRepositorySnapshot) {
        do {
            let plan = try openPlanner.planOpenOptions(
                for: URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
            )
            openOptions = plan.options.map { option in
                OpenOption(
                    application: option.application,
                    targetPath: option.targetPath,
                    reason: option.reason,
                    isRecommended: option.isRecommended,
                    isAvailable: projectOpener.isAvailable(option.application)
                )
            }
        } catch {
            openOptions = []
            appendLog("Open Project\n\(error.localizedDescription)")
        }
    }

    private func reloadNPMProjectInfo(for snapshot: GitRepositorySnapshot) {
        do {
            let projectInfo = try npmService.inspectProject(
                in: URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
            )
            npmProjectInfo = projectInfo
            npmBrowserURL = projectInfo?.suggestedBrowserURL ?? ""
        } catch {
            npmProjectInfo = nil
            npmBrowserURL = ""
            appendLog("NPM Support\n\(error.localizedDescription)")
        }
    }

    private func syncMergeBranchSelections(
        with snapshot: GitRepositorySnapshot,
        preferredSourceBranch: String? = nil,
        preferredTargetBranch: String? = nil
    ) {
        let branchNames = Set(snapshot.branches.map(\.name))
        let selectedOrCurrentBranch = branchNames.contains(selectedBranchName) ? selectedBranchName : snapshot.currentBranch
        let fallbackSourceBranch = selectedOrCurrentBranch
        let fallbackTargetBranch = snapshot.branches.first(where: { $0.name != fallbackSourceBranch })?.name ?? snapshot.currentBranch

        if let preferredSourceBranch, branchNames.contains(preferredSourceBranch), preferredSourceBranch != mergeTargetBranchName {
            mergeSourceBranchName = preferredSourceBranch
        } else if branchNames.contains(mergeSourceBranchName), mergeSourceBranchName != mergeTargetBranchName {
            mergeSourceBranchName = mergeSourceBranchName
        } else {
            mergeSourceBranchName = fallbackSourceBranch
        }

        if let preferredTargetBranch, branchNames.contains(preferredTargetBranch), preferredTargetBranch != mergeSourceBranchName {
            mergeTargetBranchName = preferredTargetBranch
        } else if branchNames.contains(mergeTargetBranchName), mergeTargetBranchName != mergeSourceBranchName {
            mergeTargetBranchName = mergeTargetBranchName
        } else {
            mergeTargetBranchName = fallbackTargetBranch
        }

        if mergeSourceBranchName == mergeTargetBranchName {
            mergeTargetBranchName = snapshot.branches.first(where: { $0.name != mergeSourceBranchName })?.name ?? ""
        }
    }

    private func updatePostMergeDeleteBranchCandidate(
        mergedBranch: String,
        targetBranch: String,
        snapshot: GitRepositorySnapshot
    ) {
        guard targetBranch == "main" else {
            postMergeDeleteBranchName = nil
            cancelDeleteMergedBranch()
            return
        }

        // HUMHERE: Confirm whether this post-merge cleanup should stay limited to local branch deletion after merges into `main`, or later expand to support remote deletion and non-`main` targets.
        if snapshot.branches.contains(where: { $0.name == mergedBranch }) {
            postMergeDeleteBranchName = mergedBranch
        } else {
            postMergeDeleteBranchName = nil
        }
        cancelDeleteMergedBranch()
    }

    private func rememberRepository(at repositoryPath: String) {
        recentRepositoryStore.add(repositoryPath)
        recentRepositories = recentRepositoryStore.load()
    }

    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        outputLog += "[\(timestamp)] \(message)\n\n"
    }
}

private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
