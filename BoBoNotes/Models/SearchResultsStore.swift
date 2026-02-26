import Foundation
import Combine

/// Observable store for search results, driving the bottom results panel.
@MainActor
final class SearchResultsStore: ObservableObject {
    @Published var query: SearchQuery = SearchQuery()
    @Published var results: [FileSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var statusMessage: String = ""
    @Published var isPanelVisible: Bool = false

    private let searchService = SearchService()
    private var currentTask: Task<Void, Never>?

    var totalMatchCount: Int {
        results.reduce(0) { $0 + $1.matchCount }
    }

    // MARK: - Find All in Current Document

    func findAllInDocument(_ document: EditorDocument) {
        guard !query.isEmpty else {
            results = []
            statusMessage = ""
            return
        }

        currentTask?.cancel()
        currentTask = Task {
            isSearching = true
            defer { isSearching = false }

            do {
                let result = try await searchService.searchDocument(document, query: query)
                if !Task.isCancelled {
                    if result.matches.isEmpty {
                        results = []
                        statusMessage = "No matches found"
                    } else {
                        results = [result]
                        statusMessage = "\(result.matchCount) match\(result.matchCount == 1 ? "" : "es") found"
                    }
                    isPanelVisible = true
                }
            } catch {
                if !Task.isCancelled {
                    results = []
                    statusMessage = "Search error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Find All in Open Documents

    func findAllInOpenDocuments(_ documents: [EditorDocument]) {
        guard !query.isEmpty else {
            results = []
            statusMessage = ""
            return
        }

        currentTask?.cancel()
        currentTask = Task {
            isSearching = true
            defer { isSearching = false }

            do {
                let fileResults = try await searchService.searchDocuments(documents, query: query)
                if !Task.isCancelled {
                    results = fileResults
                    let total = fileResults.reduce(0) { $0 + $1.matchCount }
                    let fileCount = fileResults.count
                    if total == 0 {
                        statusMessage = "No matches found"
                    } else {
                        statusMessage = "\(total) match\(total == 1 ? "" : "es") in \(fileCount) file\(fileCount == 1 ? "" : "s")"
                    }
                    isPanelVisible = true
                }
            } catch {
                if !Task.isCancelled {
                    results = []
                    statusMessage = "Search error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Find in Folder

    func findInFolder(at url: URL, extensions: [String]? = nil) {
        guard !query.isEmpty else {
            results = []
            statusMessage = ""
            return
        }

        currentTask?.cancel()
        currentTask = Task {
            isSearching = true
            statusMessage = "Searching in \(url.lastPathComponent)..."
            defer { isSearching = false }

            do {
                let fileResults = try await searchService.searchFolder(at: url, query: query, fileExtensions: extensions)
                if !Task.isCancelled {
                    results = fileResults
                    let total = fileResults.reduce(0) { $0 + $1.matchCount }
                    let fileCount = fileResults.count
                    if total == 0 {
                        statusMessage = "No matches found in folder"
                    } else {
                        statusMessage = "\(total) match\(total == 1 ? "" : "es") in \(fileCount) file\(fileCount == 1 ? "" : "s")"
                    }
                    isPanelVisible = true
                }
            } catch {
                if !Task.isCancelled {
                    results = []
                    statusMessage = "Search error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Find Next / Previous

    func findNext(in document: EditorDocument, fromLocation: Int) async -> SearchMatch? {
        guard !query.isEmpty else { return nil }
        return try? await searchService.findNext(in: document.content, query: query, fromLocation: fromLocation)
    }

    func findPrevious(in document: EditorDocument, fromLocation: Int) async -> SearchMatch? {
        guard !query.isEmpty else { return nil }
        return try? await searchService.findPrevious(in: document.content, query: query, fromLocation: fromLocation)
    }

    // MARK: - Replace

    func replaceAllInDocument(_ document: EditorDocument) async -> Int {
        guard !query.isEmpty else { return 0 }
        do {
            let result = try await searchService.replaceAll(in: document.content, query: query)
            document.content = result.newText
            document.isDirty = true
            statusMessage = "Replaced \(result.count) occurrence\(result.count == 1 ? "" : "s")"
            return result.count
        } catch {
            statusMessage = "Replace error: \(error.localizedDescription)"
            return 0
        }
    }

    // MARK: - Toggle / Clear

    func togglePanel() {
        isPanelVisible.toggle()
    }

    func clearResults() {
        results = []
        statusMessage = ""
        currentTask?.cancel()
        // Auto-hide panel when not pinned
        if !AppSettings.shared.searchPanelPinned {
            isPanelVisible = false
        }
    }

    func cancel() {
        currentTask?.cancel()
        isSearching = false
    }

    // MARK: - Expand/Collapse

    func toggleExpanded(for resultID: UUID) {
        if let index = results.firstIndex(where: { $0.id == resultID }) {
            results[index].isExpanded.toggle()
        }
    }
}
