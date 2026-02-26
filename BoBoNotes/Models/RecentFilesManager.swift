import Foundation

/// Manages the list of recently opened files.
final class RecentFilesManager: ObservableObject {
    static let shared = RecentFilesManager()

    private let maxFiles = 15
    private let userDefaultsKey = "recentFileBookmarks"

    @Published private(set) var recentFiles: [URL] = []

    private init() {
        loadRecentFiles()
    }

    func addFile(url: URL) {
        // Remove if already exists (to move to top)
        recentFiles.removeAll { $0 == url }
        // Insert at beginning
        recentFiles.insert(url, at: 0)
        // Trim to max
        if recentFiles.count > maxFiles {
            recentFiles = Array(recentFiles.prefix(maxFiles))
        }
        saveRecentFiles()
    }

    func clearAll() {
        recentFiles.removeAll()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    private func saveRecentFiles() {
        let bookmarks = recentFiles.compactMap { url -> Data? in
            try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: userDefaultsKey)
    }

    private func loadRecentFiles() {
        guard let bookmarks = UserDefaults.standard.array(forKey: userDefaultsKey) as? [Data] else { return }
        let originalCount = bookmarks.count
        recentFiles = bookmarks.compactMap { data -> URL? in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
                return nil
            }
            if isStale { return nil }
            return url
        }
        // Persist the cleaned list if stale bookmarks were removed
        if recentFiles.count < originalCount {
            saveRecentFiles()
        }
    }
}
