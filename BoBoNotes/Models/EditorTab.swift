import Foundation
import Combine

/// Represents a tab in the editor, wrapping an EditorDocument.
final class EditorTab: ObservableObject, Identifiable, Hashable {
    let id: UUID
    @Published var document: EditorDocument
    @Published var isSelected: Bool = false

    /// Cursor position
    @Published var cursorLine: Int = 1
    @Published var cursorColumn: Int = 1
    @Published var selectedRange: NSRange = NSRange(location: 0, length: 0)

    /// Scroll position preservation
    @Published var scrollOffset: CGFloat = 0

    /// Text statistics
    @Published var wordCount: Int = 0
    @Published var charCount: Int = 0

    /// Zoom level (1.0 = 100%)
    @Published var zoomLevel: CGFloat = 1.0

    /// Bookmarked lines (0-indexed)
    @Published var bookmarkedLines: Set<Int> = []

    func toggleBookmark(line: Int) {
        if bookmarkedLines.contains(line) {
            bookmarkedLines.remove(line)
        } else {
            bookmarkedLines.insert(line)
        }
    }

    func nextBookmark(from currentLine: Int) -> Int? {
        guard !bookmarkedLines.isEmpty else { return nil }
        let sorted = bookmarkedLines.sorted()
        // Find first bookmark after current line
        if let next = sorted.first(where: { $0 > currentLine }) {
            return next
        }
        // Wrap around to first bookmark
        return sorted.first
    }

    func previousBookmark(from currentLine: Int) -> Int? {
        guard !bookmarkedLines.isEmpty else { return nil }
        let sorted = bookmarkedLines.sorted()
        // Find last bookmark before current line
        if let prev = sorted.last(where: { $0 < currentLine }) {
            return prev
        }
        // Wrap around to last bookmark
        return sorted.last
    }

    func clearBookmarks() {
        bookmarkedLines.removeAll()
    }

    /// Tab identity is coupled to document identity. This means re-opening a file
    /// that was previously closed will create a new tab with a new ID, which is correct.
    /// The duplicate-open guard in TabsStore.openFile checks fileURL, not ID.
    init(document: EditorDocument) {
        self.id = document.id
        self.document = document
    }

    static func == (lhs: EditorTab, rhs: EditorTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayTitle: String {
        let dirty = document.isDirty ? "● " : ""
        return dirty + document.title
    }
}
