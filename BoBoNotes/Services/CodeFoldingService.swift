import Foundation

/// Represents a foldable region in the document.
struct FoldableRegion {
    let startLine: Int      // 0-based line index
    let endLine: Int        // 0-based line index
    let startOffset: Int    // Character offset of the opening brace
    let endOffset: Int      // Character offset of the closing brace
    var isFolded: Bool = false
}

/// Detects foldable code regions based on brace matching.
final class CodeFoldingService {

    /// Analyze text and return foldable regions (brace-based: `{ }`)
    /// Skips braces inside string literals and comments for more accurate folding.
    func detectFoldableRegions(in text: String) -> [FoldableRegion] {
        let nsStr = text as NSString
        guard nsStr.length > 0 else { return [] }

        var regions: [FoldableRegion] = []
        var stack: [(offset: Int, line: Int)] = []
        var currentLine = 0
        var inLineComment = false
        var inBlockComment = false
        var inString = false
        var stringDelimiter: unichar = 0

        var i = 0
        while i < nsStr.length {
            let ch = nsStr.character(at: i)

            // Newline resets line comment
            if ch == 0x0A { // \n
                currentLine += 1
                inLineComment = false
                i += 1
                continue
            }

            // Skip characters inside line comments
            if inLineComment { i += 1; continue }

            // Block comment end: */
            if inBlockComment {
                if ch == 0x2A && i + 1 < nsStr.length && nsStr.character(at: i + 1) == 0x2F {
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1; continue
            }

            // String literal tracking
            if inString {
                if ch == 0x5C { // backslash — skip next char
                    i += 2; continue
                }
                if ch == stringDelimiter {
                    inString = false
                }
                i += 1; continue
            }

            // Line comment start: //
            if ch == 0x2F && i + 1 < nsStr.length && nsStr.character(at: i + 1) == 0x2F {
                inLineComment = true
                i += 2; continue
            }

            // Block comment start: /*
            if ch == 0x2F && i + 1 < nsStr.length && nsStr.character(at: i + 1) == 0x2A {
                inBlockComment = true
                i += 2; continue
            }

            // String start: " or '
            if ch == 0x22 || ch == 0x27 { // " or '
                inString = true
                stringDelimiter = ch
                i += 1; continue
            }

            if ch == 0x7B { // {
                stack.append((offset: i, line: currentLine))
            } else if ch == 0x7D { // }
                if let open = stack.popLast() {
                    // Only create a foldable region if it spans multiple lines
                    if currentLine > open.line {
                        let region = FoldableRegion(
                            startLine: open.line,
                            endLine: currentLine,
                            startOffset: open.offset,
                            endOffset: i
                        )
                        regions.append(region)
                    }
                }
            }
            i += 1
        }

        // Sort by start offset
        regions.sort { $0.startOffset < $1.startOffset }
        return regions
    }

    /// Get the foldable region that starts on a given line
    func region(atLine line: Int, in regions: [FoldableRegion]) -> FoldableRegion? {
        return regions.first { $0.startLine == line }
    }
}
