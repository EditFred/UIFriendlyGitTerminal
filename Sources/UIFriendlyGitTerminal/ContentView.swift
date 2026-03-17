import GitVibesCore
import SwiftUI

struct ContentView: View {
    private enum StageSheetMode {
        case stageOnly
        case stageAndCommit

        var actionTitle: String {
            switch self {
            case .stageOnly:
                return "Add Selected"
            case .stageAndCommit:
                return "Add Selected and Commit"
            }
        }
    }

    @StateObject private var viewModel = RepositoryViewModel()
    @State private var isCloneSheetPresented = false
    @State private var isStageSheetPresented = false
    @State private var isCommitPreparationDialogPresented = false
    @State private var isNPMPopoverPresented = false
    @State private var stagedFileSelection = Set<String>()
    @State private var stageSheetMode: StageSheetMode = .stageOnly

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

                Button("Clone Repo") {
                    isCloneSheetPresented = true
                }
                .disabled(viewModel.isBusy)

                Button("Refresh") {
                    viewModel.refresh()
                }
                .disabled(viewModel.selectedFolderURL == nil || viewModel.isBusy)
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .sheet(isPresented: $isCloneSheetPresented) {
            cloneSheet
        }
        .sheet(isPresented: $isStageSheetPresented) {
            stageFilesSheet
        }
        .sheet(isPresented: $viewModel.isDeleteMergedBranchConfirmationPresented) {
            deleteMergedBranchSheet
        }
        .confirmationDialog(
            "Stage Files Before Commit",
            isPresented: $isCommitPreparationDialogPresented,
            titleVisibility: .visible
        ) {
            // HUMHERE: if product wants a safer default, prefer "Select Files to Add" over the current add-all-first ordering in this prompt.
            Button("Add All and Commit") {
                viewModel.stageAllFilesAndCommit()
            }

            Button("Select Files to Add") {
                presentStageSheet(mode: .stageAndCommit)
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No files are staged yet. Add all changes or choose specific files before committing.")
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

                Button(viewModel.primaryOpenButtonTitle) {
                    viewModel.openRecommendedProject()
                }
                .disabled(viewModel.selectedFolderURL == nil || viewModel.isBusy || viewModel.primaryOpenOption == nil)

                Menu("Open With") {
                    if viewModel.openOptions.isEmpty {
                        Text("Open a repository to see IDE options.")
                    } else {
                        ForEach(viewModel.openOptions) { option in
                            Button {
                                viewModel.openProject(with: option.application)
                            } label: {
                                let menuTitle = option.isAvailable ? option.application.displayName : "\(option.application.displayName) Not Installed"
                                if option.isRecommended {
                                    Label("\(menuTitle) Recommended", systemImage: "star.fill")
                                } else {
                                    Text(menuTitle)
                                }
                            }
                            .disabled(!option.isAvailable || viewModel.isBusy)
                        }
                    }
                }
                .disabled(viewModel.selectedFolderURL == nil)

                Button("Reveal in Finder") {
                    viewModel.revealInFinder()
                }
                .disabled(viewModel.selectedFolderURL == nil)
            }

            if let primaryOpenOption = viewModel.primaryOpenOption {
                Text(primaryOpenOption.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            recentRepositoriesSection

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
        Group {
            if #available(macOS 14.0, *) {
                ModernBranchesEmptyState()
            } else {
                legacyBranchesEmptyState
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private var recentRepositoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Projects")
                .font(.headline)

            if viewModel.recentRepositories.isEmpty {
                Text("Previously opened repositories will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.recentRepositories) { repository in
                    Button {
                        viewModel.selectRecentRepository(repository)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repository.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(repository.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

            HStack {
                Button("Add All") {
                    viewModel.stageAllFiles()
                }
                .disabled(viewModel.isBusy || viewModel.stageableFiles.isEmpty)

                Button("Select Files") {
                    presentStageSheet(mode: .stageOnly)
                }
                .disabled(viewModel.isBusy || viewModel.stageableFiles.isEmpty)

                Spacer()

                Button("Commit") {
                    if viewModel.hasStagedChanges {
                        viewModel.commit()
                    } else {
                        isCommitPreparationDialogPresented = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    viewModel.isBusy ||
                    viewModel.commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    viewModel.changedFiles.isEmpty
                )
            }

            Text(viewModel.hasStagedChanges ? "Commit will use the files already staged in git." : "Commit will prompt you to stage all changes or choose specific files first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var mergeCard: some View {
        card("Merge") {
            Text("Merge one branch into another. The app will switch to the target branch before running the merge when needed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Source branch", selection: $viewModel.mergeSourceBranchName) {
                ForEach(viewModel.branches) { branch in
                    Text(branch.name).tag(branch.name)
                }
            }
            .disabled(viewModel.branches.count < 2)

            Picker("Target branch", selection: $viewModel.mergeTargetBranchName) {
                ForEach(viewModel.branches.filter { $0.name != viewModel.mergeSourceBranchName }) { branch in
                    Text(branch.name).tag(branch.name)
                }
            }
            .disabled(viewModel.branches.count < 2)

            Button("Merge Selected Branches") {
                viewModel.mergeSelectedBranches()
            }
            .disabled(
                viewModel.isBusy ||
                viewModel.mergeSourceBranchName.isEmpty ||
                viewModel.mergeTargetBranchName.isEmpty ||
                viewModel.mergeSourceBranchName == viewModel.mergeTargetBranchName
            )

            if let branchName = viewModel.postMergeDeleteBranchName {
                Divider()

                Text("`\(branchName)` was merged into `main`. Delete the local branch if you no longer need it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Delete Branch \(branchName)", role: .destructive) {
                    viewModel.promptToDeleteMergedBranch()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isBusy)
            }
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
        VStack(spacing: 0) {
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
            npmBar
        }
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.06), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var npmBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Project Tools")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.hasNPMProject ? "NPM controls are available for this repository." : "No package.json detected in this repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("NPM") {
                isNPMPopoverPresented.toggle()
            }
            .disabled(viewModel.selectedFolderURL == nil)
            .popover(isPresented: $isNPMPopoverPresented, arrowEdge: .bottom) {
                npmPopover
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.thinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var npmPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NPM")
                .font(.title3.weight(.semibold))

            if let projectInfo = viewModel.npmProjectInfo {
                Text(projectInfo.projectDirectoryPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack {
                    Button("Test") {
                        viewModel.runNPMCommand(.test)
                        isNPMPopoverPresented = false
                    }
                    .disabled(viewModel.isBusy || !viewModel.supports(.test))

                    Button("Build") {
                        viewModel.runNPMCommand(.build)
                        isNPMPopoverPresented = false
                    }
                    .disabled(viewModel.isBusy || !viewModel.supports(.build))

                    Button("Start") {
                        viewModel.runNPMCommand(.start)
                        isNPMPopoverPresented = false
                    }
                    .disabled(viewModel.isBusy || !viewModel.supports(.start))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Open in Browser")
                        .font(.headline)

                    TextField("http://localhost:3000", text: $viewModel.npmBrowserURL)
                        .textFieldStyle(.roundedBorder)

                    Button("Open Browser") {
                        viewModel.openNPMProjectInBrowser()
                        isNPMPopoverPresented = false
                    }
                    .disabled(viewModel.npmBrowserURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text("Open a repository with a package.json file to use npm actions from here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
    }

    private var cloneSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Clone Repository")
                .font(.title2.weight(.semibold))

            TextField("https://github.com/org/repo.git or git@github.com:org/repo.git", text: $viewModel.cloneRepositoryURL)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Destination Folder")
                    .font(.headline)

                HStack {
                    Text(viewModel.cloneDestinationURL?.path ?? "No destination selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Choose Folder") {
                        viewModel.chooseCloneDestination()
                    }
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isCloneSheetPresented = false
                }

                Button("Clone") {
                    viewModel.cloneRepository()
                    isCloneSheetPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    viewModel.isBusy ||
                    viewModel.cloneRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    viewModel.cloneDestinationURL == nil
                )
            }
        }
        .padding(24)
        .frame(minWidth: 520)
    }

    private var deleteMergedBranchSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Merged Branch")
                .font(.title2.weight(.semibold))

            if let branchName = viewModel.postMergeDeleteBranchName {
                Text("Type `\(branchName)` to confirm deleting the local branch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // HUMHERE: Keep this as a typed confirmation because branch deletion is destructive; only relax it if product explicitly accepts a lower-friction safety check.
                TextField(branchName, text: $viewModel.deleteMergedBranchConfirmationText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    viewModel.cancelDeleteMergedBranch()
                }

                Button("Delete Branch", role: .destructive) {
                    viewModel.deleteMergedBranch()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isBusy || !viewModel.canConfirmMergedBranchDeletion)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var stageFilesSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Files to Add")
                .font(.title2.weight(.semibold))

            Text("Choose the working tree files to stage before committing.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(viewModel.stageableFiles) { file in
                Toggle(isOn: binding(for: file.path)) {
                    HStack {
                        Text(file.status)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)
                        Text(file.path)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .frame(minWidth: 520, minHeight: 260)

            HStack {
                Spacer()

                Button("Cancel") {
                    isStageSheetPresented = false
                }

                Button(stageSheetMode.actionTitle) {
                    submitStageSheet()
                    isStageSheetPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isBusy || stagedFileSelection.isEmpty)
            }
        }
        .padding(24)
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

    private func binding(for path: String) -> Binding<Bool> {
        Binding(
            get: { stagedFileSelection.contains(path) },
            set: { isSelected in
                if isSelected {
                    stagedFileSelection.insert(path)
                } else {
                    stagedFileSelection.remove(path)
                }
            }
        )
    }

    private func presentStageSheet(mode: StageSheetMode) {
        stageSheetMode = mode
        // HUMHERE: confirm whether the selection sheet should start with every stageable file selected or none selected by default.
        stagedFileSelection = Set(viewModel.stageableFiles.map(\.path))
        isStageSheetPresented = true
    }

    private func submitStageSheet() {
        let selectedPaths = Array(stagedFileSelection)

        switch stageSheetMode {
        case .stageOnly:
            viewModel.stageFiles(selectedPaths)
        case .stageAndCommit:
            viewModel.stageFilesAndCommit(selectedPaths)
        }
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
