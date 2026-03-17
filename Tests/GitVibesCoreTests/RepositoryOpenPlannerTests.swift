import Foundation
import GitVibesCore
import Testing

@Test func repositoryOpenPlannerPrefersWorkspaceForXcodeProjects() throws {
    let repositoryRoot = try makeTemporaryRepository()
    defer { try? FileManager.default.removeItem(at: repositoryRoot) }

    try FileManager.default.createDirectory(
        at: repositoryRoot.appendingPathComponent("UIFriendlyGitTerminal.xcodeproj", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: repositoryRoot.appendingPathComponent("App/UIFriendlyGitTerminal.xcworkspace", isDirectory: true),
        withIntermediateDirectories: true
    )

    let plan = try RepositoryOpenPlanner().planOpenOptions(for: repositoryRoot)

    #expect(plan.options.first(where: { $0.application == .xcode })?.targetPath == repositoryRoot.appendingPathComponent("App/UIFriendlyGitTerminal.xcworkspace").path)
    #expect(plan.options.first(where: { $0.application == .xcode })?.isRecommended == true)
    #expect(plan.options.first(where: { $0.application == .visualStudioCode })?.isRecommended == false)
}

@Test func repositoryOpenPlannerUsesCodeWorkspaceForEditors() throws {
    let repositoryRoot = try makeTemporaryRepository()
    defer { try? FileManager.default.removeItem(at: repositoryRoot) }

    let workspaceURL = repositoryRoot.appendingPathComponent("Workspace/project.code-workspace")
    try FileManager.default.createDirectory(at: workspaceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: workspaceURL.path, contents: Data())

    let plan = try RepositoryOpenPlanner().planOpenOptions(for: repositoryRoot)

    #expect(plan.options.first(where: { $0.application == .visualStudioCode })?.targetPath == workspaceURL.path)
    #expect(plan.options.first(where: { $0.application == .cursor })?.targetPath == workspaceURL.path)
    #expect(plan.options.first(where: { $0.application == .codex })?.targetPath == workspaceURL.path)
}

@Test func repositoryOpenPlannerRecommendsXcodeForSwiftPackagesWithoutProjectFiles() throws {
    let repositoryRoot = try makeTemporaryRepository()
    defer { try? FileManager.default.removeItem(at: repositoryRoot) }

    FileManager.default.createFile(
        atPath: repositoryRoot.appendingPathComponent("Package.swift").path,
        contents: Data("import PackageDescription".utf8)
    )

    let plan = try RepositoryOpenPlanner().planOpenOptions(for: repositoryRoot)

    #expect(plan.options.first(where: { $0.application == .xcode })?.targetPath == repositoryRoot.path)
    #expect(plan.options.first(where: { $0.application == .xcode })?.isRecommended == true)
}

@Test func repositoryOpenPlannerUsesPackageManifestDirectoryForEditors() throws {
    let repositoryRoot = try makeTemporaryRepository()
    defer { try? FileManager.default.removeItem(at: repositoryRoot) }

    let appDirectory = repositoryRoot.appendingPathComponent("apps/web", isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    FileManager.default.createFile(
        atPath: appDirectory.appendingPathComponent("package.json").path,
        contents: Data("{\"name\":\"web\"}".utf8)
    )

    let plan = try RepositoryOpenPlanner().planOpenOptions(for: repositoryRoot)

    #expect(plan.options.first(where: { $0.application == .visualStudioCode })?.targetPath == appDirectory.path)
    #expect(plan.options.first(where: { $0.application == .visualStudioCode })?.isRecommended == true)
    #expect(plan.options.first(where: { $0.application == .cursor })?.targetPath == appDirectory.path)
    #expect(plan.options.first(where: { $0.application == .codex })?.targetPath == appDirectory.path)
}

@Test func repositoryOpenPlannerRecommendsVSCodeForRepositoriesWithoutNativeProjectFiles() throws {
    let repositoryRoot = try makeTemporaryRepository()
    defer { try? FileManager.default.removeItem(at: repositoryRoot) }

    let plan = try RepositoryOpenPlanner().planOpenOptions(for: repositoryRoot)

    #expect(plan.options.first(where: { $0.application == .visualStudioCode })?.targetPath == repositoryRoot.path)
    #expect(plan.options.first(where: { $0.application == .visualStudioCode })?.isRecommended == true)
    #expect(plan.options.first(where: { $0.application == .xcode })?.isRecommended == false)
}

private func makeTemporaryRepository() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
