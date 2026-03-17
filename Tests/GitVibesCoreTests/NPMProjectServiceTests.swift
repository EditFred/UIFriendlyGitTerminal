import Foundation
import GitVibesCore
import Testing

@Test func inspectProjectDetectsAvailableScriptsAndSuggestedBrowserURL() throws {
    let repositoryRoot = try makeTemporaryPackageJSON(
        """
        {
          "scripts": {
            "test": "vitest run",
            "build": "vite build",
            "start": "vite --host localhost --port 4310"
          }
        }
        """
    )

    let service = NPMProjectService()
    let projectInfo = try #require(try service.inspectProject(in: repositoryRoot))

    #expect(projectInfo.projectDirectoryPath == repositoryRoot.path)
    #expect(projectInfo.availableScripts == [.test, .build, .start])
    #expect(projectInfo.suggestedBrowserURL == "http://localhost:4310")
}

@Test func inspectProjectFallsBackToDefaultBrowserURLWhenNoPortIsDeclared() throws {
    let repositoryRoot = try makeTemporaryPackageJSON(
        """
        {
          "scripts": {
            "start": "react-scripts start"
          }
        }
        """
    )

    let service = NPMProjectService()
    let projectInfo = try #require(try service.inspectProject(in: repositoryRoot))

    #expect(projectInfo.suggestedBrowserURL == "http://localhost:3000")
}

@Test func inspectProjectAcceptsPackageJSONWithoutScripts() throws {
    let repositoryRoot = try makeTemporaryPackageJSON(
        """
        {
          "name": "example-app"
        }
        """
    )

    let service = NPMProjectService()
    let projectInfo = try #require(try service.inspectProject(in: repositoryRoot))

    #expect(projectInfo.availableScripts.isEmpty)
    #expect(projectInfo.suggestedBrowserURL == "http://localhost:3000")
}

@Test func inspectProjectReturnsNilWhenPackageJSONIsMissing() throws {
    let repositoryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)

    let service = NPMProjectService()

    #expect(try service.inspectProject(in: repositoryRoot) == nil)
}

private func makeTemporaryPackageJSON(_ contents: String) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try contents.write(
        to: directoryURL.appendingPathComponent("package.json"),
        atomically: true,
        encoding: .utf8
    )
    return directoryURL
}
