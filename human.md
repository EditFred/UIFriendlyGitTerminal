# Human Notes

## Summary
- Added a native macOS Xcode project at `UIFriendlyGitTerminal.xcodeproj` with three targets that mirror the existing Swift package structure: `UIFriendlyGitTerminal` app, `GitVibesCore` framework, and `GitVibesCoreTests`.
- Added a shared Xcode scheme so the app can be opened, run, and tested directly from Xcode without creating an extra workspace.
- Added `Config/AppSigning.xcconfig` so the bundle identifier and signing team are easy to set without editing the project file by hand.

## HUMHERE Locations
- `Config/AppSigning.xcconfig` — set the final app bundle identifier so it matches your signing/App Store configuration.
- `Config/AppSigning.xcconfig` — set the Apple Developer Team ID before signing or archiving from Xcode.

## Tests
- No new source tests were added for issue #1 because the change is project metadata rather than app logic, and the existing `GitVibesCoreTests` target is now included in the Xcode project.
- Validation in this environment was limited to `plutil -lint UIFriendlyGitTerminal.xcodeproj/project.pbxproj` and XML linting for the shared scheme/workspace files.
- `xcodebuild` could not be run here because the active developer directory is Command Line Tools only, not a full Xcode installation, and `swift test` also failed due a local toolchain/SDK mismatch outside the repo.
