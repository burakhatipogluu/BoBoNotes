import Foundation

/// Represents a symbol extracted from source code (function, class, struct, etc.)
struct SymbolItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let kind: SymbolKind
    let lineNumber: Int  // 1-based

    enum SymbolKind: String {
        case function = "function"
        case classDecl = "class"
        case structDecl = "struct"
        case enumDecl = "enum"
        case protocolDecl = "protocol"
        case property = "property"
        case method = "method"
        case interfaceDecl = "interface"
        case moduleDecl = "module"

        var icon: String {
            switch self {
            case .function, .method: return "f.square"
            case .classDecl: return "c.square"
            case .structDecl: return "s.square"
            case .enumDecl: return "e.square"
            case .protocolDecl, .interfaceDecl: return "p.square"
            case .property: return "v.square"
            case .moduleDecl: return "m.square"
            }
        }
    }
}

/// Extracts symbols (functions, classes, etc.) from source code using regex patterns.
/// Patterns are selected based on the detected language.
final class FunctionListService {
    static let shared = FunctionListService()
    private init() {}

    /// Extract symbols from the given source code for the specified language.
    func extractSymbols(from content: String, languageID: String?) -> [SymbolItem] {
        let patterns = symbolPatterns(for: languageID)
        guard !patterns.isEmpty else { return [] }

        var results: [SymbolItem] = []
        let lines = content.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comments
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("#") && languageID != "python" {
                continue
            }

            for (pattern, kind) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
                let range = NSRange(location: 0, length: (line as NSString).length)
                if let match = regex.firstMatch(in: line, range: range) {
                    // Extract the name from the first capture group
                    if match.numberOfRanges >= 2 {
                        let nameRange = match.range(at: 1)
                        if nameRange.location != NSNotFound {
                            let name = (line as NSString).substring(with: nameRange)
                            results.append(SymbolItem(name: name, kind: kind, lineNumber: index + 1))
                        }
                    }
                    break // Only match one pattern per line
                }
            }
        }

        return results
    }

    // MARK: - Language-specific patterns

    /// Returns an array of (regex pattern, symbol kind) tuples for the given language.
    private func symbolPatterns(for languageID: String?) -> [(String, SymbolItem.SymbolKind)] {
        switch languageID {
        case "swift":
            return swiftPatterns
        case "javascript", "typescript":
            return jstsPatterns
        case "python":
            return pythonPatterns
        case "java", "csharp":
            return javaCSharpPatterns
        case "c", "cpp":
            return cCppPatterns
        case "go":
            return goPatterns
        case "rust":
            return rustPatterns
        case "ruby":
            return rubyPatterns
        case "php":
            return phpPatterns
        default:
            return genericPatterns
        }
    }

    // MARK: - Swift
    private var swiftPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:override\s+)?(?:static\s+|class\s+)?func\s+(\w+)"#, .function),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?(?:final\s+)?class\s+(\w+)"#, .classDecl),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?struct\s+(\w+)"#, .structDecl),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?enum\s+(\w+)"#, .enumDecl),
            (#"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+|open\s+)?protocol\s+(\w+)"#, .protocolDecl),
        ]
    }

    // MARK: - JavaScript / TypeScript
    private var jstsPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*(?:export\s+)?(?:async\s+)?function\s+(\w+)"#, .function),
            (#"^\s*(?:export\s+)?class\s+(\w+)"#, .classDecl),
            (#"^\s*(?:export\s+)?interface\s+(\w+)"#, .interfaceDecl),
            (#"^\s*(?:export\s+)?enum\s+(\w+)"#, .enumDecl),
            (#"^\s*(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\("#, .function),
            (#"^\s*(?:export\s+)?type\s+(\w+)"#, .structDecl),
        ]
    }

    // MARK: - Python
    private var pythonPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*(?:async\s+)?def\s+(\w+)"#, .function),
            (#"^\s*class\s+(\w+)"#, .classDecl),
        ]
    }

    // MARK: - Java / C#
    private var javaCSharpPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*(?:public|private|protected|internal)?\s*(?:static\s+)?(?:abstract\s+)?(?:virtual\s+)?(?:override\s+)?(?:async\s+)?(?:\w+(?:<[^>]+>)?)\s+(\w+)\s*\("#, .function),
            (#"^\s*(?:public|private|protected|internal)?\s*(?:abstract\s+)?(?:static\s+)?class\s+(\w+)"#, .classDecl),
            (#"^\s*(?:public|private|protected|internal)?\s*interface\s+(\w+)"#, .interfaceDecl),
            (#"^\s*(?:public|private|protected|internal)?\s*enum\s+(\w+)"#, .enumDecl),
            (#"^\s*(?:public|private|protected|internal)?\s*struct\s+(\w+)"#, .structDecl),
        ]
    }

    // MARK: - C / C++
    private var cCppPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*(?:\w+(?:\s*\*)?)\s+(\w+)\s*\([^)]*\)\s*\{"#, .function),
            (#"^\s*class\s+(\w+)"#, .classDecl),
            (#"^\s*struct\s+(\w+)"#, .structDecl),
            (#"^\s*enum\s+(?:class\s+)?(\w+)"#, .enumDecl),
            (#"^\s*namespace\s+(\w+)"#, .moduleDecl),
        ]
    }

    // MARK: - Go
    private var goPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^func\s+(?:\([^)]+\)\s+)?(\w+)"#, .function),
            (#"^type\s+(\w+)\s+struct"#, .structDecl),
            (#"^type\s+(\w+)\s+interface"#, .interfaceDecl),
        ]
    }

    // MARK: - Rust
    private var rustPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?fn\s+(\w+)"#, .function),
            (#"^\s*(?:pub(?:\([^)]+\))?\s+)?struct\s+(\w+)"#, .structDecl),
            (#"^\s*(?:pub(?:\([^)]+\))?\s+)?enum\s+(\w+)"#, .enumDecl),
            (#"^\s*(?:pub(?:\([^)]+\))?\s+)?trait\s+(\w+)"#, .protocolDecl),
            (#"^\s*(?:pub(?:\([^)]+\))?\s+)?mod\s+(\w+)"#, .moduleDecl),
            (#"^\s*impl(?:<[^>]+>)?\s+(\w+)"#, .classDecl),
        ]
    }

    // MARK: - Ruby
    private var rubyPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*def\s+(\w+)"#, .function),
            (#"^\s*class\s+(\w+)"#, .classDecl),
            (#"^\s*module\s+(\w+)"#, .moduleDecl),
        ]
    }

    // MARK: - PHP
    private var phpPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*(?:public|private|protected)?\s*(?:static\s+)?function\s+(\w+)"#, .function),
            (#"^\s*class\s+(\w+)"#, .classDecl),
            (#"^\s*interface\s+(\w+)"#, .interfaceDecl),
            (#"^\s*trait\s+(\w+)"#, .protocolDecl),
        ]
    }

    // MARK: - Generic fallback
    private var genericPatterns: [(String, SymbolItem.SymbolKind)] {
        [
            (#"^\s*(?:public\s+|private\s+)?(?:static\s+)?(?:async\s+)?func(?:tion)?\s+(\w+)"#, .function),
            (#"^\s*class\s+(\w+)"#, .classDecl),
            (#"^\s*struct\s+(\w+)"#, .structDecl),
            (#"^\s*enum\s+(\w+)"#, .enumDecl),
            (#"^\s*def\s+(\w+)"#, .function),
        ]
    }
}
