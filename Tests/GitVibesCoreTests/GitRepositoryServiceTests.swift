import Foundation
import GitVibesCore
import Testing

@Test func cloneRepositoryRunsGitCloneInDestinationFolder() throws {
    let runner = MockShellCommandRunner(results: [
        GitCommandResult(standardOutput: "Cloning into 'UIFriendlyGitTerminal'...", standardError: "", terminationStatus: 0)
    ])
    let service = GitRepositoryService(runner: runner)
    let destination = URL(fileURLWithPath: "/tmp/projects", isDirectory: true)

    let clonedRepositoryURL = try service.cloneRepository(
        from: "git@github.com:EditFred/UIFriendlyGitTerminal.git",
        into: destination
    )

    #expect(runner.calls == [
        MockShellCommandRunner.Call(
            arguments: ["clone", "git@github.com:EditFred/UIFriendlyGitTerminal.git"],
            workingDirectory: destination
        )
    ])
    #expect(clonedRepositoryURL.path == "/tmp/projects/UIFriendlyGitTerminal")
}

private final class MockShellCommandRunner: ShellCommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        let arguments: [String]
        let workingDirectory: URL?
    }

    private(set) var calls: [Call] = []
    private var results: [GitCommandResult]

    init(results: [GitCommandResult]) {
        self.results = results
    }

    func run(arguments: [String], workingDirectory: URL?) throws -> GitCommandResult {
        calls.append(Call(arguments: arguments, workingDirectory: workingDirectory))
        return results.removeFirst()
    }
}
