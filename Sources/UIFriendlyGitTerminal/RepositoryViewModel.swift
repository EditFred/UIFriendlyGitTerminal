import AppKit
import Foundation
import GitVibesCore
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published var selectedFolderURL: URL?
    @Published var snapshot: GitRepositorySnapshot?
    @Published var selectedBranchName = ""
    @Published var mergeSourceBranchName = ""
    @Published var mergeTargetBranchName = ""
    @Published var commitMessage = ""
    @Published var cloneRepositoryURL = ""
    @Published var cloneDestinationURL: URL?
    @Published var outputLog = "Choose a local repository to begin.\n"
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published private(set) var recentRepositories: [RecentRepository]

    private let service: any GitRepositoryServicing
    private let recentRepositoryStore: any RecentRepositoryStoring

    init(
        service: any GitRepositoryServicing = GitRepositoryService(),
        recentRepositoryStore: any RecentRepositoryStoring = UserDefaultsRecentRepositoryStore()
    ) {
        self.service = service
        self.recentRepositoryStore = recentRepositoryStore
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
                self.snapshot = snapshot
                self.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
                self.selectedBranchName = snapshot.currentBranch
                self.syncMergeBranchSelections(with: snapshot)
                self.rememberRepository(at: snapshot.rootPath)
                self.appendLog("Loaded repository at \(snapshot.rootPath)")
            }
        }
    }

    func revealInFinder() {
        guard let url = selectedFolderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func pull() {
        runGitCommand(.pull)
    }

    func push() {
        runGitCommand(.push)
    }

    func commit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            errorMessage = "Enter a commit message first."
            return
        }

        runGitCommand(.commit(message: message)) {
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
                self.snapshot = snapshot
                self.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
                self.selectedBranchName = snapshot.currentBranch
                self.syncMergeBranchSelections(with: snapshot)
                self.rememberRepository(at: snapshot.rootPath)
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
                self.snapshot = snapshot
                self.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
                self.selectedBranchName = snapshot.currentBranch
                self.syncMergeBranchSelections(with: snapshot, preferredSourceBranch: sourceBranch, preferredTargetBranch: targetBranch)
                self.appendLog(logEntries.joined(separator: "\n\n"))
            }
        }
    }

    private func runGitCommand(_ command: GitCommand, afterSuccess: @escaping @MainActor () -> Void = {}) {
        guard let folder = selectedFolderURL else {
            errorMessage = "Choose a repository first."
            return
        }

        runTask(label: command.label) {
            let result = try self.service.perform(command, in: folder)
            let snapshot = try self.service.loadSnapshot(for: folder)

            await MainActor.run {
                self.snapshot = snapshot
                self.selectedFolderURL = URL(fileURLWithPath: snapshot.rootPath, isDirectory: true)
                self.selectedBranchName = snapshot.currentBranch
                self.syncMergeBranchSelections(with: snapshot)
                self.rememberRepository(at: snapshot.rootPath)
                self.appendLog(self.render(command: command, result: result))
                afterSuccess()
            }
        }
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

    private func renderResultOutput(_ result: GitCommandResult, fallback: String) -> String {
        let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? fallback : output
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
