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
        M  Sources/Committed.swift
        MM Sources/PartiallyStaged.swift
        """
    )

    #expect(parsed == [
        GitChangedFile(path: "Sources/App.swift", status: "M", isStaged: false, hasUnstagedChanges: true),
        GitChangedFile(path: "README.md", status: "??", isStaged: false, hasUnstagedChanges: true),
        GitChangedFile(path: "Sources/Committed.swift", status: "M", isStaged: true, hasUnstagedChanges: false),
        GitChangedFile(path: "Sources/PartiallyStaged.swift", status: "MM", isStaged: true, hasUnstagedChanges: true)
    ])
}
