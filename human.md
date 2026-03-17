# Human Notes

## Summary
- Issue #6: added npm project detection, script execution, background `npm start`, and a browser-launch affordance driven by `package.json` scripts.
- Issue #7: added repository open planning plus app-side “Open in …” actions for Xcode, VS Code, Cursor, and Codex with availability checks and a recommended default.
- Issue #8: after merging a branch into `main`, the UI now offers a typed-confirmation flow to delete the merged local branch.
- Issue #9: the Commit panel now supports explicit staging before commit with `Add All`, a file-selection sheet, and a commit-time prompt when nothing is staged yet.
- Parsed git status entries now track staged vs unstaged state so the commit flow can avoid redundant `git add` work and block empty commits earlier.
- Added tests for npm support, repository open planning, merged-branch cleanup, and guarded staging/commit flows.

## HUMHERE Locations
- `Sources/GitVibesCore/NPMProjectService.swift` — confirm whether default browser launch should stay on `http://localhost:3000` when no port can be inferred from `package.json`.
- `Sources/GitVibesCore/NPMProjectService.swift` — decide whether detached `npm start` is sufficient or if the app should later capture and surface long-running dev-server logs.
- `Sources/GitVibesCore/RepositoryOpenPlanner.swift` — confirm whether Swift packages without Xcode metadata should still recommend Xcode first or switch to an editor-first default.
- `Sources/UIFriendlyGitTerminal/IDEProjectOpening.swift` — confirm the production Codex macOS bundle identifier if app discovery should key off something other than `com.openai.codex`.
- `Sources/UIFriendlyGitTerminal/RepositoryViewModel.swift` — decide whether the post-merge cleanup flow should stay limited to local deletion after merges into `main` or expand to remote deletion and other target branches.
- `Sources/UIFriendlyGitTerminal/ContentView.swift` — `// HUMHERE` confirm whether the stage-selection sheet should default to all stageable files selected or start empty.
- `Sources/UIFriendlyGitTerminal/ContentView.swift` — decide whether the commit-time staging prompt should bias toward `Add All and Commit` or `Select Files to Add`.
- `Sources/UIFriendlyGitTerminal/ContentView.swift` — confirm typed branch-name entry should remain mandatory for destructive branch deletion instead of a lighter acknowledgement.

## Verification
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache swift test --disable-sandbox` passed on March 17, 2026.
