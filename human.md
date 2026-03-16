# Human Notes

## Summary
- Implemented issue #4 across the macOS app UI, view model, and git service.
- Added a recent-projects quick-switch section in the left repository panel, backed by persisted repository roots.
- Reworked merge so users choose both branches explicitly as `source -> target`, with the first picker auto-filled from the currently selected branch.
- Added a toolbar-driven clone flow that accepts an HTTPS or SSH remote URL plus a destination folder, then opens the cloned repository automatically.
- Added tests for clone command/service behavior and view-model coverage for refresh, explicit merge flow, and cloning.

## HUMHERE Locations
- `Config/AppSigning.xcconfig` — provide the final bundle identifier used for local signing or App Store distribution.
- `Config/AppSigning.xcconfig` — provide the Apple Developer Team ID before signing or archiving.
- `Sources/UIFriendlyGitTerminal/RecentRepositoryStore.swift` — adjust the maximum number of quick-switch recent repositories if product requirements change.

## Verification
- `swift test` was attempted, but this environment cannot complete Swift package builds because the active compiler does not match the installed macOS SDK and the sandbox cannot write to the default module cache path.
