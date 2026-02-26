import Foundation

/// Configuration for a search query.
struct SearchQuery: Equatable {
    var searchText: String = ""
    var replaceText: String = ""
    var matchCase: Bool = false
    var wholeWord: Bool = false
    var useRegex: Bool = false
    var wrapAround: Bool = true
    var searchBackward: Bool = false
    var inSelection: Bool = false

    var isEmpty: Bool { searchText.isEmpty }

    /// Build NSRegularExpression or nil for plain search
    func buildRegex() throws -> NSRegularExpression? {
        guard !searchText.isEmpty else { return nil }

        var pattern: String
        if useRegex {
            pattern = searchText
        } else {
            pattern = NSRegularExpression.escapedPattern(for: searchText)
        }

        if wholeWord {
            pattern = "\\b\(pattern)\\b"
        }

        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if !matchCase {
            options.insert(.caseInsensitive)
        }

        return try NSRegularExpression(pattern: pattern, options: options)
    }
}

/// A single search match result.
struct SearchMatch: Identifiable, Hashable {
    let id = UUID()
    let range: NSRange
    let lineNumber: Int
    let lineContent: String      // Full line text
    let matchText: String        // The actual matched text
    let columnStart: Int         // Column offset within line

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SearchMatch, rhs: SearchMatch) -> Bool {
        lhs.id == rhs.id
    }
}

/// Grouped results for a single file/document.
struct FileSearchResult: Identifiable {
    let id = UUID()
    let documentID: UUID
    let documentTitle: String
    let fileURL: URL?
    var matches: [SearchMatch]
    var isExpanded: Bool = true
    var languageID: String?      // For syntax-highlighted search results

    var matchCount: Int { matches.count }
}

/// Scope for search operations.
enum SearchScope {
    case currentDocument
    case allOpenDocuments
    case folder(URL)
}
