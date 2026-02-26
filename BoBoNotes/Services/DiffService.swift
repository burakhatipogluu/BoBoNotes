import Foundation

// MARK: - Diff Models

enum DiffLineType {
    case unchanged  // Line exists in both documents
    case added      // Line only in right (new) document
    case removed    // Line only in left (old) document
}

struct DiffLine: Identifiable {
    let id = UUID()
    let leftLineNumber: Int?
    let rightLineNumber: Int?
    let text: String
    let type: DiffLineType
}

/// A single row on one side of the side-by-side diff view.
struct DiffSideRow {
    let lineNumber: Int?   // nil = empty spacer row
    let text: String
    let type: DiffLineType // .unchanged, .added, .removed
    var isEmpty: Bool { lineNumber == nil }
}

/// An aligned pair of rows for side-by-side display.
struct DiffRowPair: Identifiable {
    let id = UUID()
    let left: DiffSideRow
    let right: DiffSideRow
}

struct DiffResult {
    let lines: [DiffLine]
    let pairs: [DiffRowPair]   // Aligned left/right row pairs for side-by-side view
    let addedCount: Int
    let removedCount: Int
    let unchangedCount: Int
    let leftLineCount: Int     // Total lines in left document
    let rightLineCount: Int    // Total lines in right document
}

// MARK: - Diff Service (LCS-based line diff)

final class DiffService {

    /// Maximum number of lines per side before the LCS diff is skipped
    /// to avoid excessive memory use (O(m*n) table).
    static let maxDiffLines = 10_000

    /// Compute line-by-line diff between two strings using Longest Common Subsequence.
    static func diff(left: String, right: String) -> DiffResult {
        let leftLines = left.components(separatedBy: "\n")
        let rightLines = right.components(separatedBy: "\n")

        let m = leftLines.count
        let n = rightLines.count

        // Guard against excessive memory usage
        if m > maxDiffLines || n > maxDiffLines {
            // Fall back: treat everything as removed + added
            var lines: [DiffLine] = []
            for (i, line) in leftLines.enumerated() {
                lines.append(DiffLine(leftLineNumber: i + 1, rightLineNumber: nil, text: line, type: .removed))
            }
            for (j, line) in rightLines.enumerated() {
                lines.append(DiffLine(leftLineNumber: nil, rightLineNumber: j + 1, text: line, type: .added))
            }
            let pairs = buildPairs(from: lines)
            return DiffResult(lines: lines, pairs: pairs, addedCount: n, removedCount: m,
                              unchangedCount: 0, leftLineCount: m, rightLineCount: n)
        }

        // Build LCS table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 1...max(m, 1) {
            guard i <= m else { break }
            for j in 1...max(n, 1) {
                guard j <= n else { break }
                if leftLines[i - 1] == rightLines[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to produce diff lines
        var rawLines: [DiffLine] = []
        var i = m, j = n
        var added = 0, removed = 0, unchanged = 0

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && leftLines[i - 1] == rightLines[j - 1] {
                rawLines.append(DiffLine(leftLineNumber: i, rightLineNumber: j,
                                         text: leftLines[i - 1], type: .unchanged))
                unchanged += 1
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                rawLines.append(DiffLine(leftLineNumber: nil, rightLineNumber: j,
                                         text: rightLines[j - 1], type: .added))
                added += 1
                j -= 1
            } else if i > 0 {
                rawLines.append(DiffLine(leftLineNumber: i, rightLineNumber: nil,
                                         text: leftLines[i - 1], type: .removed))
                removed += 1
                i -= 1
            }
        }

        rawLines.reverse()

        // Build aligned row pairs for side-by-side view
        let pairs = buildPairs(from: rawLines)

        return DiffResult(
            lines: rawLines,
            pairs: pairs,
            addedCount: added,
            removedCount: removed,
            unchangedCount: unchanged,
            leftLineCount: m,
            rightLineCount: n
        )
    }

    /// Convert flat diff lines into aligned left/right row pairs.
    private static func buildPairs(from lines: [DiffLine]) -> [DiffRowPair] {
        let emptyRow = DiffSideRow(lineNumber: nil, text: "", type: .unchanged)
        var pairs: [DiffRowPair] = []

        for line in lines {
            switch line.type {
            case .unchanged:
                let left = DiffSideRow(lineNumber: line.leftLineNumber, text: line.text, type: .unchanged)
                let right = DiffSideRow(lineNumber: line.rightLineNumber, text: line.text, type: .unchanged)
                pairs.append(DiffRowPair(left: left, right: right))

            case .removed:
                let left = DiffSideRow(lineNumber: line.leftLineNumber, text: line.text, type: .removed)
                pairs.append(DiffRowPair(left: left, right: emptyRow))

            case .added:
                let right = DiffSideRow(lineNumber: line.rightLineNumber, text: line.text, type: .added)
                pairs.append(DiffRowPair(left: emptyRow, right: right))
            }
        }

        return pairs
    }
}
