# Human Notes

## Summary
- Updated `Sources/UIFriendlyGitTerminal/ContentView.swift` for issue #3 so the branch empty-state view wraps the `if #available` split in a concrete `Group` before applying `.frame` and `.padding`.
- This fixes the SwiftUI compile error at `ContentView.swift:113` where the modifiers were being resolved against the protocol type `View` instead of a concrete composed view.
- Existing macOS 13 and macOS 14 empty-state behavior remains unchanged.

## HUMHERE Locations
- `Config/AppSigning.xcconfig` — set the final app bundle identifier so it matches your signing/App Store configuration.
- `Config/AppSigning.xcconfig` — set the Apple Developer Team ID before signing or archiving from Xcode.

## Tests
- No new tests were added for issue #3 because the repo only has `GitVibesCoreTests`, and this fix is isolated to SwiftUI view composition in the app target.
- `swift test` was attempted but failed in this environment because the active Command Line Tools Swift compiler does not match the installed macOS SDK, and the process also cannot write to the default module cache path.
- App-side compile validation therefore could not be completed locally from this sandboxed environment.

## Issue #3

### What Changed
- Wrapped the `if #available(macOS 14.0, *)` branch in `Sources/UIFriendlyGitTerminal/ContentView.swift` inside a `Group`.
- Left the shared `.frame(maxWidth: .infinity)` and `.padding(.vertical, 28)` modifiers in place after the `Group`, which gives SwiftUI a concrete view to modify and resolves the compile failure.
- Did not change the empty-state content or branch-loading behavior.

### Assumptions
- The supported minimum deployment target remains macOS 13.0, as declared in both `Package.swift` and `UIFriendlyGitTerminal.xcodeproj/project.pbxproj`.
- The current `GitVibesCoreTests` target is still the only automated test target in the repo, so no meaningful automated coverage could be added for this SwiftUI availability fix without introducing a new app/UI test target.

### HUMHERE Locations
- `Config/AppSigning.xcconfig` — provide the final bundle identifier for local signing/App Store distribution.
- `Config/AppSigning.xcconfig` — provide the Apple Developer Team ID before signing or archiving.
