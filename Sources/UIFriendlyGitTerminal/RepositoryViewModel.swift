import AppKit
import Foundation
import GitVibesCore
import SwiftUI

@MainActor
final class RepositoryViewModel: ObservableObject {
    @Published var selectedFolderURL: URL?
    @Published var snapshot: GitRepositorySnapshot?
    @Published var selectedBranchName = ""
    @Published var mergeBranchName = ""
    @Published var commitMessage = ""
    @Published var outputLog = "Choose a local repository to begin.\n"
    @Published var errorMessage: String?
    @Published var isBusy = false

    private let service: GitRepositoryService

    init(service: GitRepositoryService = GitRepositoryService()) {
        self.service = service
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
                if self.mergeBranchName.isEmpty || self.mergeBranchName == snapshot.currentBranch {
                    self.mergeBranchName = snapshot.branches.first(where: { !$0.isCurrent })?.name ?? ""
                }
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

    func mergeSelectedBranch() {
        guard !mergeBranchName.isEmpty else {
            errorMessage = "Choose a branch to merge into the current branch."
            return
        }

        runGitCommand(.merge(branch: mergeBranchName))
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
        let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            return "\(command.label) completed successfully."
        }
        return "\(command.label)\n\(output)"
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
