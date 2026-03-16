// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UIFriendlyGitTerminal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "GitVibesCore",
            targets: ["GitVibesCore"]
        ),
        .executable(
            name: "UIFriendlyGitTerminal",
            targets: ["UIFriendlyGitTerminal"]
        )
    ],
    targets: [
        .target(
            name: "GitVibesCore"
        ),
        .executableTarget(
            name: "UIFriendlyGitTerminal",
            dependencies: ["GitVibesCore"]
        ),
        .testTarget(
            name: "GitVibesCoreTests",
            dependencies: ["GitVibesCore"]
        ),
        .testTarget(
            name: "UIFriendlyGitTerminalTests",
            dependencies: ["UIFriendlyGitTerminal", "GitVibesCore"]
        )
    ]
)
