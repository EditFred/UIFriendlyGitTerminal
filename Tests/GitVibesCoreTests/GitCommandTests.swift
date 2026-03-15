import GitVibesCore
import Testing

@Test func commitCommandBuildsExpectedArguments() {
    #expect(GitCommand.commit(message: "Ship it").arguments == ["commit", "-m", "Ship it"])
}

@Test func switchCommandBuildsExpectedArguments() {
    #expect(GitCommand.switchBranch(name: "feature/test").arguments == ["switch", "feature/test"])
}
