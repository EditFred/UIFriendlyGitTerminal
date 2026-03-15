import Foundation

public enum GitParsing {
    public static func parseBranches(_ output: String) -> [GitBranch] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard let name = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    return nil
                }

                let isCurrent = parts.count > 1 && parts[1].contains("*")
                return GitBranch(name: name, isCurrent: isCurrent)
            }
            .sorted {
                if $0.isCurrent != $1.isCurrent {
                    return $0.isCurrent && !$1.isCurrent
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    public static func parseChangedFiles(_ output: String) -> [GitChangedFile] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let rawLine = String(line)
                guard rawLine.count >= 3 else {
                    return nil
                }

                let status = String(rawLine.prefix(2)).trimmingCharacters(in: .whitespaces)
                let path = String(rawLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else {
                    return nil
                }

                return GitChangedFile(path: path, status: status.isEmpty ? "--" : status)
            }
    }
}
