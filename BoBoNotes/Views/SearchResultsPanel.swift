import SwiftUI

/// Bottom panel showing search results grouped by file, with match highlighting.
struct SearchResultsPanel: View {
    @ObservedObject var searchStore: SearchResultsStore
    @ObservedObject private var settings = AppSettings.shared
    var onMatchSelected: (FileSearchResult, SearchMatch) -> Void
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: metrics.uiFontSize))
                    .foregroundColor(.secondary)

                Text("Search Results")
                    .font(.system(size: metrics.uiFontSize, weight: .semibold))

                // Total match count badge
                if !searchStore.results.isEmpty {
                    let totalMatches = searchStore.results.reduce(0) { $0 + $1.matchCount }
                    Text("\(totalMatches)")
                        .font(.system(size: metrics.uiFontSizeSmall - 1, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }

                if searchStore.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }

                Text(searchStore.statusMessage)
                    .font(.system(size: metrics.uiFontSizeSmall))
                    .foregroundColor(.secondary)

                Spacer()

                // Pin toggle
                Button(action: { settings.searchPanelPinned.toggle() }) {
                    Image(systemName: settings.searchPanelPinned ? "pin.fill" : "pin.slash")
                        .font(.system(size: metrics.uiFontSizeSmall))
                        .foregroundColor(settings.searchPanelPinned ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(settings.searchPanelPinned
                    ? "Pinned (stays open even when results are cleared)"
                    : "Unpinned (closes when results are cleared)")

                Button(action: { searchStore.clearResults() }) {
                    Image(systemName: "trash")
                        .font(.system(size: metrics.uiFontSizeSmall))
                }
                .buttonStyle(.plain)
                .help("Clear Results")

                Button(action: {
                    searchStore.isPanelVisible = false
                    // If not pinned, also clear results
                    if !settings.searchPanelPinned {
                        searchStore.results = []
                        searchStore.statusMessage = ""
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: metrics.uiFontSizeSmall, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Close Panel")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(nsColor: .separatorColor)),
                alignment: .top
            )

            Divider()

            // Results list
            if searchStore.results.isEmpty && !searchStore.isSearching {
                VStack {
                    Spacer()
                    Text(searchStore.statusMessage.isEmpty ? "No search performed" : searchStore.statusMessage)
                        .font(.system(size: metrics.uiFontSizeMedium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(searchStore.results) { fileResult in
                            FileResultSection(
                                fileResult: fileResult,
                                onToggle: { searchStore.toggleExpanded(for: fileResult.id) },
                                onMatchSelected: { match in
                                    onMatchSelected(fileResult, match)
                                }
                            )
                        }
                    }
                    .listStyle(.sidebar)
                    .font(.system(size: metrics.uiFontSize))
                }
            }
        }
        .frame(minHeight: 100)
    }
}

// MARK: - File Result Section

struct FileResultSection: View {
    let fileResult: FileSearchResult
    let onToggle: () -> Void
    let onMatchSelected: (SearchMatch) -> Void
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        Section {
            if fileResult.isExpanded {
                ForEach(fileResult.matches) { match in
                    MatchRow(match: match, languageID: fileResult.languageID)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onMatchSelected(match)
                        }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Image(systemName: fileResult.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: metrics.uiFontSizeSmall - 2, weight: .bold))
                    .foregroundColor(.secondary)

                Image(systemName: "doc.text")
                    .font(.system(size: metrics.uiFontSizeSmall))
                    .foregroundColor(.secondary)

                Text(fileResult.documentTitle)
                    .font(.system(size: metrics.uiFontSize, weight: .medium))
                    .lineLimit(1)

                Text("(\(fileResult.matchCount))")
                    .font(.system(size: metrics.uiFontSizeSmall))
                    .foregroundColor(.secondary)

                if let url = fileResult.fileURL {
                    Text(url.deletingLastPathComponent().path)
                        .font(.system(size: metrics.uiFontSizeSmall - 1))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }
        }
    }
}

// MARK: - Match Row

struct MatchRow: View {
    let match: SearchMatch
    let languageID: String?

    @State private var isHovered = false
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        HStack(spacing: 6) {
            // Line number
            Text("\(match.lineNumber)")
                .font(.system(size: metrics.uiFontSizeSmall, design: .monospaced))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .frame(width: 40, alignment: .trailing)

            // Line content with syntax highlighting + match highlighted
            SyntaxHighlightedMatchText(
                text: match.lineContent,
                highlight: match.matchText,
                columnStart: match.columnStart,
                languageID: languageID
            )
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer()
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(3)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Syntax Highlighted Match Text

/// Displays a line of code with syntax highlighting,
/// plus a yellow background highlight on the search match.
struct SyntaxHighlightedMatchText: View {
    let text: String
    let highlight: String
    let columnStart: Int
    let languageID: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        if let attrString = buildAttributedString() {
            Text(attrString)
                .font(.system(size: metrics.uiFontSize, design: .monospaced))
        } else {
            // Fallback: plain text with match highlight
            plainHighlightedText
        }
    }

    private func buildAttributedString() -> AttributedString? {
        guard !text.isEmpty else { return nil }

        let service = HighlightrSyntaxService.shared
        service.updateTheme()

        // Highlight the line with syntax colors
        guard let highlighted = service.highlightSnippet(text, languageID: languageID) else {
            return nil
        }

        // Convert NSAttributedString → AttributedString, keeping only foreground colors
        var result = AttributedString(text)

        // Apply syntax colors
        highlighted.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: highlighted.length), options: []) { color, range, _ in
            guard let nsColor = color as? NSColor else { return }
            if let swiftRange = Range(range, in: text),
               let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
               let upper = AttributedString.Index(swiftRange.upperBound, within: result) {
                result[lower..<upper].foregroundColor = Color(nsColor: nsColor)
            }
        }

        // Add match highlight (yellow background + bold)
        let nsText = text as NSString
        let matchStart = max(0, columnStart - 1)
        let matchLen = min((highlight as NSString).length, nsText.length - matchStart)
        if matchLen > 0 {
            let matchNSRange = NSRange(location: matchStart, length: matchLen)
            if let swiftRange = Range(matchNSRange, in: text),
               let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
               let upper = AttributedString.Index(swiftRange.upperBound, within: result) {
                let highlightBg: Color = colorScheme == .dark
                    ? Color(red: 0.65, green: 0.53, blue: 0.20).opacity(0.6)
                    : Color(red: 0.95, green: 0.85, blue: 0.40).opacity(0.7)
                result[lower..<upper].backgroundColor = highlightBg
                result[lower..<upper].font = .system(size: metrics.uiFontSize, design: .monospaced).bold()
            }
        }

        return result
    }

    // Fallback plain text with match highlight
    private var plainHighlightedText: some View {
        let nsText = text as NSString
        let matchStart = max(0, columnStart - 1)
        let matchEnd = min(nsText.length, matchStart + (highlight as NSString).length)

        let before = matchStart > 0 ? nsText.substring(to: matchStart) : ""
        let matched = matchEnd > matchStart ? nsText.substring(with: NSRange(location: matchStart, length: matchEnd - matchStart)) : highlight
        let after = matchEnd < nsText.length ? nsText.substring(from: matchEnd) : ""

        let highlightBackground: Color = colorScheme == .dark
            ? Color(red: 0.65, green: 0.53, blue: 0.20).opacity(0.6)
            : Color(red: 0.95, green: 0.85, blue: 0.40).opacity(0.7)

        return HStack(spacing: 0) {
            Text(before)
                .font(.system(size: metrics.uiFontSize, design: .monospaced))
                .foregroundColor(.primary)
            Text(matched)
                .font(.system(size: metrics.uiFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(highlightBackground)
                )
            Text(after)
                .font(.system(size: metrics.uiFontSize, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Legacy HighlightedText (kept for backward compat if needed)

struct HighlightedText: View {
    let text: String
    let highlight: String
    let columnStart: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutMetrics) private var metrics

    private var highlightBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.65, green: 0.53, blue: 0.20).opacity(0.6)
            : Color(red: 0.95, green: 0.85, blue: 0.40).opacity(0.7)
    }

    private var highlightForeground: Color {
        colorScheme == .dark
            ? .white
            : Color(red: 0.15, green: 0.15, blue: 0.15)
    }

    var body: some View {
        if highlight.isEmpty {
            Text(text)
                .font(.system(size: metrics.uiFontSize, design: .monospaced))
        } else {
            formattedText
        }
    }

    private var formattedText: some View {
        let nsText = text as NSString
        let matchStart = max(0, columnStart - 1)
        let matchEnd = min(nsText.length, matchStart + (highlight as NSString).length)

        let before = matchStart > 0 ? nsText.substring(to: matchStart) : ""
        let matched = matchEnd > matchStart ? nsText.substring(with: NSRange(location: matchStart, length: matchEnd - matchStart)) : highlight
        let after = matchEnd < nsText.length ? nsText.substring(from: matchEnd) : ""

        return HStack(spacing: 0) {
            Text(before)
                .font(.system(size: metrics.uiFontSize, design: .monospaced))
                .foregroundColor(.primary)
            Text(matched)
                .font(.system(size: metrics.uiFontSize, weight: .bold, design: .monospaced))
                .foregroundColor(highlightForeground)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(highlightBackground)
                )
            Text(after)
                .font(.system(size: metrics.uiFontSize, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}
