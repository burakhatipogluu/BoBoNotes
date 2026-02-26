import Foundation

/// Token categories for syntax highlighting.
enum TokenType: String, CaseIterable {
    case keyword
    case string
    case comment
    case number
    case type
    case function
    case `operator`
    case preprocessor
    case attribute
    case variable
    case plain
}

/// Defines syntax rules for a single language.
struct LanguageDefinition: Identifiable {
    let id: String          // e.g. "swift", "sql"
    let displayName: String // e.g. "Swift", "SQL"
    let extensions: [String]
    let lineComment: String?
    let blockCommentStart: String?
    let blockCommentEnd: String?
    let keywords: [String]
    let types: [String]
    let builtinFunctions: [String]
    let operators: [String]
    let stringDelimiters: [Character]
    let preprocessorPrefix: String?
    let numberPattern: String  // Regex for number literals
    let extraRules: [ExtraHighlightRule]

    struct ExtraHighlightRule {
        let pattern: String
        let tokenType: TokenType
    }

    init(
        id: String,
        displayName: String,
        extensions: [String],
        lineComment: String? = "//",
        blockCommentStart: String? = "/*",
        blockCommentEnd: String? = "*/",
        keywords: [String] = [],
        types: [String] = [],
        builtinFunctions: [String] = [],
        operators: [String] = ["+", "-", "*", "/", "=", "!", "<", ">", "&", "|", "^", "~", "%"],
        stringDelimiters: [Character] = ["\"", "'"],
        preprocessorPrefix: String? = nil,
        numberPattern: String = "\\b\\d+\\.?\\d*(?:[eE][+-]?\\d+)?\\b",
        extraRules: [ExtraHighlightRule] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.extensions = extensions
        self.lineComment = lineComment
        self.blockCommentStart = blockCommentStart
        self.blockCommentEnd = blockCommentEnd
        self.keywords = keywords
        self.types = types
        self.builtinFunctions = builtinFunctions
        self.operators = operators
        self.stringDelimiters = stringDelimiters
        self.preprocessorPrefix = preprocessorPrefix
        self.numberPattern = numberPattern
        self.extraRules = extraRules
    }
}
