import GitVibesCore
import Testing

@Test func parseBranchesMarksCurrentBranch() {
    let parsed = GitParsing.parseBranches(
        """
        main|*
        feature/refactor|
        bugfix/login|
        """
    )

    #expect(parsed.count == 3)
    #expect(parsed.first?.name == "main")
    #expect(parsed.first?.isCurrent == true)
}

@Test func parseChangedFilesHandlesTrackedAndUntrackedEntries() {
    let parsed = GitParsing.parseChangedFiles(
        """
         M Sources/App.swift
        ?? README.md
        """
    )

    #expect(parsed == [
        GitChangedFile(path: "Sources/App.swift", status: "M"),
        GitChangedFile(path: "README.md", status: "??")
    ])
}
