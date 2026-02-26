import Foundation

/// Represents a single tab entry in a saved session.
struct SessionEntry: Codable {
    enum EntryType: String, Codable {
        case file       // Saved file with URL
        case unsaved    // Unsaved tab (content in memory)
    }

    let type: EntryType
    let title: String
    let content: String?        // Only for unsaved tabs
    let bookmarkData: Data?     // Only for file tabs
    let languageID: String?     // Language for syntax highlighting
}

/// Saves and restores the list of open tabs across app launches.
/// Supports both saved files (via security-scoped bookmarks) and unsaved tabs.
final class SessionManager {
    static let shared = SessionManager()

    private let sessionEntriesKey = "sessionEntries_v2"
    private let activeTabKey = "sessionActiveIndex"
    // Legacy key for migration
    private let legacyBookmarksKey = "sessionBookmarks"

    private init() {}

    // MARK: - Save

    /// Save current session — all open tabs including unsaved ones
    func saveSession(tabs: [EditorTab], activeIndex: Int) {
        var entries: [SessionEntry] = []

        for tab in tabs {
            if let url = tab.document.fileURL {
                let bookmark = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                entries.append(SessionEntry(
                    type: .file,
                    title: tab.document.title,
                    content: nil,
                    bookmarkData: bookmark,
                    languageID: tab.document.languageID
                ))
            } else {
                entries.append(SessionEntry(
                    type: .unsaved,
                    title: tab.document.title,
                    content: tab.document.content,
                    bookmarkData: nil,
                    languageID: tab.document.languageID
                ))
            }
        }

        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: sessionEntriesKey)
        }
        UserDefaults.standard.set(activeIndex, forKey: activeTabKey)
    }

    // MARK: - Restore

    /// Restored tab data
    struct RestoredTab {
        let document: EditorDocument
        let needsSecurityRelease: Bool  // true if startAccessingSecurityScopedResource was called
    }

    /// Restore session — returns list of restored documents and the active index
    func restoreSession() -> (tabs: [RestoredTab], activeIndex: Int) {
        // Try new format first
        if let data = UserDefaults.standard.data(forKey: sessionEntriesKey),
           let entries = try? JSONDecoder().decode([SessionEntry].self, from: data) {
            let tabs = restoreFromEntries(entries)
            let activeIndex = UserDefaults.standard.integer(forKey: activeTabKey)
            return (tabs, activeIndex)
        }

        // Fall back to legacy format (bookmark array)
        if let bookmarks = UserDefaults.standard.array(forKey: legacyBookmarksKey) as? [Data] {
            let tabs = restoreFromLegacyBookmarks(bookmarks)
            let activeIndex = UserDefaults.standard.integer(forKey: activeTabKey)
            return (tabs, activeIndex)
        }

        return ([], 0)
    }

    private func restoreFromEntries(_ entries: [SessionEntry]) -> [RestoredTab] {
        var tabs: [RestoredTab] = []

        for entry in entries {
            switch entry.type {
            case .file:
                guard let bookmarkData = entry.bookmarkData else { continue }
                var isStale = false
                guard let url = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) else { continue }
                if isStale { continue }

                let started = url.startAccessingSecurityScopedResource()
                if let doc = try? EditorDocument.load(from: url, encoding: .utf8) {
                    if let langID = entry.languageID {
                        doc.languageID = langID
                    }
                    tabs.append(RestoredTab(document: doc, needsSecurityRelease: started))
                } else if started {
                    url.stopAccessingSecurityScopedResource()
                }

            case .unsaved:
                let doc = EditorDocument(title: entry.title)
                doc.content = entry.content ?? ""
                if let langID = entry.languageID {
                    doc.languageID = langID
                }
                // Mark as dirty if there's actual content
                doc.isDirty = !(entry.content ?? "").isEmpty
                tabs.append(RestoredTab(document: doc, needsSecurityRelease: false))
            }
        }

        return tabs
    }

    private func restoreFromLegacyBookmarks(_ bookmarks: [Data]) -> [RestoredTab] {
        var tabs: [RestoredTab] = []

        for data in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            if isStale { continue }

            let started = url.startAccessingSecurityScopedResource()
            if let doc = try? EditorDocument.load(from: url, encoding: .utf8) {
                tabs.append(RestoredTab(document: doc, needsSecurityRelease: started))
            } else if started {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return tabs
    }

    // MARK: - Clear

    func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionEntriesKey)
        UserDefaults.standard.removeObject(forKey: legacyBookmarksKey)
        UserDefaults.standard.removeObject(forKey: activeTabKey)
    }
}
