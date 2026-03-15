# Git Vibes

Git Vibes is a macOS SwiftUI app for common git actions without typing commands into Terminal.

## Current Scope
- Open a local git repository from the UI
- View the current branch and all local branches
- Pull, push, switch branches, merge a selected branch, and commit with a message
- Review working tree changes and recent command output

## Project Structure
- `Sources/GitVibesCore`: reusable git command and parsing layer
- `Sources/UIFriendlyGitTerminal`: SwiftUI macOS app
- `Tests/GitVibesCoreTests`: package tests for core git behavior

## Run
Open `Package.swift` in Xcode and run the `UIFriendlyGitTerminal` executable target on macOS.

From the command line, use `swift run UIFriendlyGitTerminal` once the local Xcode Command Line Tools environment is correctly configured.
