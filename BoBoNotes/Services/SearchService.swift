import Foundation

/// Performs search operations in background using Swift Concurrency.
actor SearchService {

    // MARK: - Search in String

    /// Find all matches in a given text.
    func findAll(in text: String, query: SearchQuery) throws -> [SearchMatch] {
        guard let regex = try query.buildRegex() else { return [] }

        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let regexMatches = regex.matches(in: text, range: fullRange)

        var results: [SearchMatch] = []
        results.reserveCapacity(regexMatches.count)

        // Performance: build line-start index once, then O(log n) line lookup per match.
        let lineStarts = buildLineStartOffsets(in: nsString)

        for match in regexMatches {
            let range = match.range
            let matchText = nsString.substring(with: range)

            let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
            let lineContent = nsString.substring(with: lineRange).trimmingCharacters(in: .newlines)

            let lineNumber = lineNumber(for: range.location, lineStarts: lineStarts)
            let columnStart = range.location - lineRange.location + 1

            results.append(SearchMatch(
                range: range,
                lineNumber: lineNumber,
                lineContent: lineContent,
                matchText: matchText,
                columnStart: columnStart
            ))
        }

        return results
    }

    // MARK: - Search in Document

    func searchDocument(_ document: EditorDocument, query: SearchQuery) throws -> FileSearchResult {
        let matches = try findAll(in: document.content, query: query)
        return FileSearchResult(
            documentID: document.id,
            documentTitle: document.title,
            fileURL: document.fileURL,
            matches: matches,
            languageID: document.languageID
        )
    }

    // MARK: - Search in Multiple Documents

    func searchDocuments(_ documents: [EditorDocument], query: SearchQuery) async throws -> [FileSearchResult] {
        var results: [FileSearchResult] = []

        for doc in documents {
            if Task.isCancelled { break }
            let result = try searchDocument(doc, query: query)
            if !result.matches.isEmpty {
                results.append(result)
            }
        }

        return results
    }

    // MARK: - Search in Folder (file system)

    /// Directory names to skip during folder search
    private static let skipDirectories: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", "Pods",
        "DerivedData", "__pycache__", ".tox", "venv", ".venv",
        "dist", "build", ".next", ".nuxt", "vendor"
    ]

    /// Maximum number of files to scan in a single folder search
    private static let maxFilesToScan = 10_000

    func searchFolder(at folderURL: URL, query: SearchQuery, fileExtensions: [String]? = nil) async throws -> [FileSearchResult] {
        var results: [FileSearchResult] = []
        var filesScanned = 0

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return results }

        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            if filesScanned >= Self.maxFilesToScan { break }

            // Skip well-known non-source directories
            if Self.skipDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }

            // Filter by extensions if specified
            if let exts = fileExtensions, !exts.isEmpty {
                guard exts.contains(url.pathExtension.lowercased()) else { continue }
            }

            // Skip non-regular files and large files (>50MB)
            guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true else { continue }

            let fileSize = resourceValues.fileSize ?? 0
            if fileSize > 50_000_000 { continue } // Skip files > 50MB

            filesScanned += 1

            // Try to read as text — use memory-mapped I/O to avoid copying large
            // files into the process heap when most won't contain matches.
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                continue
            }

            // Quick binary-file heuristic: if the first 512 bytes contain a NUL,
            // this is almost certainly not a text file — skip without decoding.
            let probeLen = min(data.count, 512)
            if probeLen > 0 {
                let isBinary = data.withUnsafeBytes { ptr -> Bool in
                    let bytes = ptr.bindMemory(to: UInt8.self)
                    for i in 0..<probeLen {
                        if bytes[i] == 0 { return true }
                    }
                    return false
                }
                if isBinary { continue }
            }

            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                continue
            }

            let matches = try findAll(in: text, query: query)
            if !matches.isEmpty {
                let detectedLang = LanguageRegistry.shared.detectLanguage(for: url)
                results.append(FileSearchResult(
                    documentID: UUID(),
                    documentTitle: url.lastPathComponent,
                    fileURL: url,
                    matches: matches,
                    languageID: detectedLang?.id
                ))
            }
        }

        return results
    }

    // MARK: - Find Next / Find Previous

    func findNext(in text: String, query: SearchQuery, fromLocation: Int) throws -> SearchMatch? {
        guard let regex = try query.buildRegex() else { return nil }

        let nsString = text as NSString
        let searchStart = min(fromLocation, nsString.length)

        // Search from cursor to end
        let forwardRange = NSRange(location: searchStart, length: nsString.length - searchStart)
        if let match = regex.firstMatch(in: text, range: forwardRange) {
            return makeSearchMatch(nsString: nsString, matchRange: match.range)
        }

        // Wrap around
        if query.wrapAround && searchStart > 0 {
            let wrapRange = NSRange(location: 0, length: searchStart)
            if let match = regex.firstMatch(in: text, range: wrapRange) {
                return makeSearchMatch(nsString: nsString, matchRange: match.range)
            }
        }

        return nil
    }

    func findPrevious(in text: String, query: SearchQuery, fromLocation: Int) throws -> SearchMatch? {
        guard let regex = try query.buildRegex() else { return nil }

        let nsString = text as NSString
        let searchEnd = min(fromLocation, nsString.length)

        // Find all matches before cursor, take last one
        let backwardRange = NSRange(location: 0, length: searchEnd)
        let allMatches = regex.matches(in: text, range: backwardRange)

        if let lastMatch = allMatches.last {
            return makeSearchMatch(nsString: nsString, matchRange: lastMatch.range)
        }

        // Wrap around
        if query.wrapAround && searchEnd < nsString.length {
            let wrapRange = NSRange(location: searchEnd, length: nsString.length - searchEnd)
            let wrapMatches = regex.matches(in: text, range: wrapRange)
            if let lastMatch = wrapMatches.last {
                return makeSearchMatch(nsString: nsString, matchRange: lastMatch.range)
            }
        }

        return nil
    }

    // MARK: - Replace

    func replaceAll(in text: String, query: SearchQuery) throws -> (newText: String, count: Int) {
        guard let regex = try query.buildRegex() else { return (text, 0) }

        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matchCount = regex.numberOfMatches(in: text, range: fullRange)

        let newText = regex.stringByReplacingMatches(
            in: text,
            range: fullRange,
            withTemplate: query.useRegex ? query.replaceText : NSRegularExpression.escapedTemplate(for: query.replaceText)
        )

        return (newText, matchCount)
    }

    // MARK: - Helpers

    private func countLines(in nsString: NSString, upTo location: Int) -> Int {
        guard location > 0 else { return 1 }
        var lineCount = 1
        var index = 0
        while index < location && index < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            if NSMaxRange(lineRange) <= location {
                lineCount += 1
                index = NSMaxRange(lineRange)
            } else {
                break
            }
        }
        return lineCount
    }

    /// Build 0-based character offsets where each line starts.
    /// Example: first line always starts at 0.
    private func buildLineStartOffsets(in nsString: NSString) -> [Int] {
        var starts: [Int] = [0]
        guard nsString.length > 0 else { return starts }

        var idx = 0
        while idx < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: idx, length: 0))
            let next = NSMaxRange(lineRange)
            if next < nsString.length {
                starts.append(next)
            }
            if next <= idx { break }
            idx = next
        }
        return starts
    }

    /// Convert absolute character location into 1-based line number via binary search.
    private func lineNumber(for location: Int, lineStarts: [Int]) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        var ans = 0

        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                ans = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return ans + 1
    }

    private func makeSearchMatch(nsString: NSString, matchRange: NSRange) -> SearchMatch {
        let lineRange = nsString.lineRange(for: NSRange(location: matchRange.location, length: 0))
        let lineContent = nsString.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let lineNumber = countLines(in: nsString, upTo: matchRange.location)
        let columnStart = matchRange.location - lineRange.location + 1

        return SearchMatch(
            range: matchRange,
            lineNumber: lineNumber,
            lineContent: lineContent,
            matchText: nsString.substring(with: matchRange),
            columnStart: columnStart
        )
    }
}
