# Human Notes

## Summary
- Updated `Sources/UIFriendlyGitTerminal/ContentView.swift` so the branch empty state uses `ContentUnavailableView` only on macOS 14 or newer and falls back to a compatible custom SwiftUI view on macOS 13.
- Kept the empty-state copy and icon consistent across both code paths so the UI behavior stays the same on the current minimum deployment target.
- Reviewed the other app-side SwiftUI sources involved in issue #2 and did not find additional source changes needed beyond the macOS availability fix.

## HUMHERE Locations
- `Config/AppSigning.xcconfig` — set the final app bundle identifier so it matches your signing/App Store configuration.
- `Config/AppSigning.xcconfig` — set the Apple Developer Team ID before signing or archiving from Xcode.

## Tests
- No new tests were added for issue #2 because the repo only has `GitVibesCoreTests`, and this fix is isolated to macOS SwiftUI view availability in the app target.
- `xcodebuild` was attempted but could not run because the active developer directory is `/Library/Developer/CommandLineTools`, not a full Xcode installation.
- `swift test` was attempted but failed in this environment due an external Swift toolchain/SDK mismatch and a restricted module cache path, so app-side build validation could not be completed locally.

## Issue #2

### What Changed
- Reworked `Sources/UIFriendlyGitTerminal/ContentView.swift` so the macOS 14-only `ContentUnavailableView` now lives in a separate `@available(macOS 14.0, *)` view type.
- Kept the existing macOS 13 fallback empty state in place and routed the sidebar through an `if #available(macOS 14.0, *)` check, which avoids referencing the newer symbol from the minimum-target code path.
- Rechecked the app-side files directly related to this screen and did not find any other narrow compile-time fixes required for issue #2.

### Assumptions
- The supported minimum deployment target remains macOS 13.0, as declared in both `Package.swift` and `UIFriendlyGitTerminal.xcodeproj/project.pbxproj`.
- The current `GitVibesCoreTests` target is still the only automated test target in the repo, so no meaningful automated coverage could be added for this SwiftUI availability fix without introducing a new app/UI test target.

### HUMHERE Locations
- `Config/AppSigning.xcconfig` — provide the final bundle identifier for local signing/App Store distribution.
- `Config/AppSigning.xcconfig` — provide the Apple Developer Team ID before signing or archiving.
