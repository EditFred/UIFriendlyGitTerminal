import Foundation

public enum NPMCommand: String, CaseIterable, Equatable, Sendable {
    case test
    case build
    case start

    public var arguments: [String] {
        switch self {
        case .test:
            return ["test"]
        case .build:
            return ["run", "build"]
        case .start:
            return ["start"]
        }
    }

    public var label: String {
        switch self {
        case .test:
            return "NPM Test"
        case .build:
            return "NPM Build"
        case .start:
            return "NPM Start"
        }
    }

    public var scriptName: String {
        rawValue
    }
}
