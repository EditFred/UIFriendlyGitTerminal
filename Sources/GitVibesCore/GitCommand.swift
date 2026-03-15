import Foundation

public enum GitCommand: Sendable, Equatable {
    case resolveTopLevel
    case currentBranch
    case listBranches
    case statusShort
    case pull
    case push
    case commit(message: String)
    case switchBranch(name: String)
    case merge(branch: String)

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
        }
    }
}
