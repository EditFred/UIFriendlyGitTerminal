import GitVibesCore
import Testing

@Test func commitCommandBuildsExpectedArguments() {
    #expect(GitCommand.commit(message: "Ship it").arguments == ["commit", "-m", "Ship it"])
}

@Test func addAllCommandBuildsExpectedArguments() {
    #expect(GitCommand.addAll.arguments == ["add", "."])
}

@Test func addSelectedFilesCommandBuildsExpectedArguments() {
    #expect(
        GitCommand.add(paths: ["Sources/UIFriendlyGitTerminal/ContentView.swift", "README.md"]).arguments ==
        ["add", "--", "Sources/UIFriendlyGitTerminal/ContentView.swift", "README.md"]
    )
}

@Test func switchCommandBuildsExpectedArguments() {
    #expect(GitCommand.switchBranch(name: "feature/test").arguments == ["switch", "feature/test"])
}

@Test func deleteBranchCommandBuildsExpectedArguments() {
    #expect(GitCommand.deleteBranch(name: "feature/test").arguments == ["branch", "-d", "feature/test"])
}

@Test func cloneCommandBuildsExpectedArguments() {
    #expect(
        GitCommand.clone(repositoryURL: "git@github.com:EditFred/UIFriendlyGitTerminal.git").arguments ==
        ["clone", "git@github.com:EditFred/UIFriendlyGitTerminal.git"]
    )
}

@Test func npmCommandsBuildExpectedArguments() {
    #expect(NPMCommand.test.arguments == ["test"])
    #expect(NPMCommand.build.arguments == ["run", "build"])
    #expect(NPMCommand.start.arguments == ["start"])
}
