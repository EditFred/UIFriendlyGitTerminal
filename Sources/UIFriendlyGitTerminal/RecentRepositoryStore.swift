import Foundation

struct RecentRepository: Identifiable, Equatable {
    let path: String

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

protocol RecentRepositoryStoring {
    func load() -> [RecentRepository]
    func add(_ repositoryPath: String)
}

final class UserDefaultsRecentRepositoryStore: RecentRepositoryStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "recentRepositoryPaths") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [RecentRepository] {
        let paths = defaults.stringArray(forKey: key) ?? []
        return paths.map { RecentRepository(path: $0) }
    }

    func add(_ repositoryPath: String) {
        let normalizedPath = URL(fileURLWithPath: repositoryPath, isDirectory: true).path
        var paths = defaults.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == normalizedPath }
        paths.insert(normalizedPath, at: 0)
        // HUMHERE: Adjust this cap if product wants a different number of quick-switch repository entries.
        defaults.set(Array(paths.prefix(8)), forKey: key)
    }
}
