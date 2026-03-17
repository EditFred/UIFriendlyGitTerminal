import Foundation

public enum GitCommand: Sendable, Equatable {
    case resolveTopLevel
    case currentBranch
    case listBranches
    case statusShort
    case clone(repositoryURL: String)
    case addAll
    case add(paths: [String])
    case pull
    case push
    case commit(message: String)
    case switchBranch(name: String)
    case merge(branch: String)
    case deleteBranch(name: String)

    public var arguments: [String] {
        switch self {
        case .resolveTopLevel:
            return ["rev-parse", "--show-toplevel"]
        case .currentBranch:
            return ["rev-parse", "--abbrev-ref", "HEAD"]
        case .listBranches:
            return ["branch", "--format=%(refname:short)|%(HEAD)"]
        case .statusShort:
            return ["status", "--short"]
        case let .clone(repositoryURL):
            return ["clone", repositoryURL]
        case .addAll:
            return ["add", "."]
        case let .add(paths):
            return ["add", "--"] + paths
        case .pull:
            return ["pull"]
        case .push:
            return ["push"]
        case let .commit(message):
            return ["commit", "-m", message]
        case let .switchBranch(name):
            return ["switch", name]
        case let .merge(branch):
            return ["merge", branch]
        case let .deleteBranch(name):
            return ["branch", "-d", name]
        }
    }

    public var label: String {
        switch self {
        case .resolveTopLevel:
            return "Resolve Top Level"
        case .currentBranch:
            return "Current Branch"
        case .listBranches:
            return "List Branches"
        case .statusShort:
            return "Repo Status"
        case .clone:
            return "Clone Repository"
        case .addAll:
            return "Add All"
        case .add:
            return "Add Selected Files"
        case .pull:
            return "Pull"
        case .push:
            return "Push"
        case .commit:
            return "Commit"
        case .switchBranch:
            return "Switch Branch"
        case .merge:
            return "Merge"
        case .deleteBranch:
            return "Delete Branch"
        }
    }
}
