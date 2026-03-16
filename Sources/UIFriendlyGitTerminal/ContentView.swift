import GitVibesCore
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RepositoryViewModel()

    var body: some View {
        NavigationSplitView {
            branchesSidebar
        } content: {
            actionPanel
        } detail: {
            outputPanel
        }
        .navigationTitle("Git Vibes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open Repo") {
                    viewModel.chooseRepository()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Refresh") {
                    viewModel.refresh()
                }
                .disabled(viewModel.selectedFolderURL == nil || viewModel.isBusy)
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .alert("Git Action Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.errorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .frame(minWidth: 1180, minHeight: 760)
    }

    private var branchesSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Repository")
                    .font(.headline)
                Text(viewModel.repositoryPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Choose Folder") {
                    viewModel.chooseRepository()
                }

                Button("Reveal in Finder") {
                    viewModel.revealInFinder()
                }
                .disabled(viewModel.selectedFolderURL == nil)
            }

            Divider()

            Text("Branches")
                .font(.headline)

            if viewModel.branches.isEmpty {
                branchesEmptyState
            } else {
                List(selection: $viewModel.selectedBranchName) {
                    ForEach(viewModel.branches) { branch in
                        HStack {
                            Image(systemName: branch.isCurrent ? "arrow.turn.down.right" : "arrow.right")
                                .foregroundStyle(branch.isCurrent ? .green : .secondary)
                            Text(branch.name)
                            Spacer()
                            if branch.isCurrent {
                                Text("current")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(branch.name)
                    }
                }
                .listStyle(.sidebar)
            }

            Spacer()
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    @ViewBuilder
    private var branchesEmptyState: some View {
        if #available(macOS 14.0, *) {
            ModernBranchesEmptyState()
        } else {
            legacyBranchesEmptyState
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var legacyBranchesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("No branches loaded")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Choose a repository, or refresh the current one to load branches.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var actionPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                remoteActionsCard
                commitCard
                mergeCard
                changedFilesCard
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .textBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var headerCard: some View {
        card("Branch Control") {
            Text("Current branch: \(viewModel.snapshot?.currentBranch ?? "Not loaded")")
                .font(.title3.weight(.semibold))

            Picker("Switch to", selection: $viewModel.selectedBranchName) {
                ForEach(viewModel.branches) { branch in
                    Text(branch.name).tag(branch.name)
                }
            }
            .labelsHidden()

            Button("Switch Branch") {
                viewModel.switchBranch()
            }
            .disabled(viewModel.isBusy || viewModel.selectedBranchName.isEmpty)
        }
    }

    private var remoteActionsCard: some View {
        card("Remote Actions") {
            HStack {
                Button("Pull") {
                    viewModel.pull()
                }
                .disabled(viewModel.isBusy || viewModel.selectedFolderURL == nil)

                Button("Push") {
                    viewModel.push()
                }
                .disabled(viewModel.isBusy || viewModel.selectedFolderURL == nil)
            }

            Text("These use your existing git and remote configuration on macOS.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var commitCard: some View {
        card("Commit") {
            TextField("Commit message", text: $viewModel.commitMessage)
                .textFieldStyle(.roundedBorder)

            Button("Commit") {
                viewModel.commit()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.isBusy || viewModel.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text("Commits staged changes with the message above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var mergeCard: some View {
        card("Merge") {
            Picker("Merge branch", selection: $viewModel.mergeBranchName) {
                ForEach(viewModel.branches.filter { !$0.isCurrent }) { branch in
                    Text(branch.name).tag(branch.name)
                }
            }
            .disabled(viewModel.branches.filter { !$0.isCurrent }.isEmpty)

            Button("Merge Into Current Branch") {
                viewModel.mergeSelectedBranch()
            }
            .disabled(viewModel.isBusy || viewModel.mergeBranchName.isEmpty)
        }
    }

    private var changedFilesCard: some View {
        card("Working Tree") {
            if viewModel.changedFiles.isEmpty {
                Text("Working tree is clean.")
                    .foregroundStyle(.secondary)
            } else {
                List(viewModel.changedFiles) { file in
                    HStack {
                        Text(file.status)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        Text(file.path)
                            .textSelection(.enabled)
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }

    private var outputPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Activity")
                        .font(.headline)
                    Spacer()
                    if viewModel.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(viewModel.outputLog)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.06), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
        )
    }
}

@available(macOS 14.0, *)
private struct ModernBranchesEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "No branches loaded",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text("Choose a repository, or refresh the current one to load branches.")
        )
    }
}
