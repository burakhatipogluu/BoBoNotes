import AppKit

/// Regex-based syntax highlighting service.
/// Uses LanguageDefinition token rules (keywords, comments, strings, numbers, types)
/// to produce deterministic, dependency-free syntax coloring.
///
/// All highlighting is synchronous on the caller's thread.
///
/// **Usage:**
/// - Each `EditorTextView.Coordinator` creates its own instance so that per-tab
///   language and cache state are independent.
/// - The `shared` singleton is used only for stateless snippet highlighting
///   (e.g. search results panel) where per-tab state is irrelevant.
final class HighlightrSyntaxService {

    /// Shared instance for snippet highlighting (search results panel, etc.).
    /// Do NOT use this for per-document highlighting — create a new instance instead.
    static let shared = HighlightrSyntaxService()

    private var currentLanguageID: String?
    private var lastThemeWasDark: Bool?
    private var lastAppliedTheme: String?

    /// Cached parse result — allows cheap re-application with force=true
    /// when text hasn't changed but textStorage attributes were externally corrupted
    /// (e.g. by showFindIndicator, NSTextFinder, or system layout passes).
    private var cachedHighlightText: String?
    private var cachedHighlightResult: [(NSRange, NSColor)]?


    /// Exposed for comment toggle (lineComment, blockCommentStart/End)
    private(set) var currentLanguage: LanguageDefinition?

    /// Compiled regex for current language (rebuilt on language change)
    private var compiledRules: [(regex: NSRegularExpression, tokenType: TokenType)] = []

    init() {
        updateTheme()
    }

    // MARK: - Theme

    /// Returns true if theme actually changed (caller should force re-highlight)
    @discardableResult
    func updateTheme() -> Bool {
        let isDark = AppSettings.shared.isDarkMode
        let theme = AppSettings.shared.currentSyntaxTheme
        if theme == lastAppliedTheme && isDark == lastThemeWasDark { return false }
        lastThemeWasDark = isDark
        lastAppliedTheme = theme
        cachedHighlightText = nil
        cachedHighlightResult = nil
        lastViewportRange = nil

        return true
    }

    // MARK: - Language

    func setLanguage(_ lang: LanguageDefinition?) {
        currentLanguage = lang
        currentLanguageID = lang?.id
        cachedHighlightText = nil
        cachedHighlightResult = nil
        compileRules(for: lang)
    }

    // MARK: - Full Document Highlighting

    /// Maximum file size (in characters) for full-document syntax highlighting.
    /// Files larger than this use viewport-only highlighting instead.
    private static let maxFullHighlightLength = 500_000  // ~500KB

    /// Maximum characters to highlight for viewport-only mode.
    /// Viewport + generous buffer (±200 lines worth) for smooth scrolling.
    private static let maxViewportHighlightLength = 50_000

    /// Highlights the full document synchronously and applies colors to textStorage.
    ///
    /// When `force=true` and the text hasn't changed, re-applies cached parse
    /// output without re-parsing.  This is cheap and fixes attribute corruption
    /// caused by `showFindIndicator`, `NSTextFinder`, or system layout passes.
    func highlightFullDocument(textStorage: NSTextStorage, font: NSFont, force: Bool = false) {
        let text = textStorage.string
        guard !text.isEmpty else { return }

        // For large files, use viewport-only highlighting
        if text.count > Self.maxFullHighlightLength {
            return
        }

        let result: [(NSRange, NSColor)]

        if text == cachedHighlightText, let cached = cachedHighlightResult {
            if !force { return }
            result = cached
        } else {
            result = tokenize(text)
            cachedHighlightResult = result
            cachedHighlightText = text
        }

        applyHighlighting(result, to: textStorage, font: font)
    }

    // MARK: - Viewport-Only Highlighting (Large Files)

    private var lastViewportRange: NSRange?

    /// Highlights only the visible viewport region of a large file.
    func highlightViewport(
        textStorage: NSTextStorage,
        visibleCharRange: NSRange,
        font: NSFont,
        force: Bool = false
    ) {
        let text = textStorage.string
        guard !text.isEmpty else { return }

        let bufferChars = 5000
        let expandedStart = max(0, visibleCharRange.location - bufferChars)
        let expandedEnd = min(text.count, NSMaxRange(visibleCharRange) + bufferChars)
        let expandedRange = NSRange(location: expandedStart, length: expandedEnd - expandedStart)

        if !force, let last = lastViewportRange {
            let overlap = NSIntersectionRange(last, expandedRange)
            if overlap.length > 0, Double(overlap.length) / Double(expandedRange.length) > 0.8 {
                return
            }
        }

        let highlightRange: NSRange
        if expandedRange.length > Self.maxViewportHighlightLength {
            let center = visibleCharRange.location + visibleCharRange.length / 2
            let halfLen = Self.maxViewportHighlightLength / 2
            let start = max(0, center - halfLen)
            let end = min(text.count, start + Self.maxViewportHighlightLength)
            highlightRange = NSRange(location: start, length: end - start)
        } else {
            highlightRange = expandedRange
        }

        let nsText = text as NSString
        let substring = nsText.substring(with: highlightRange)
        let tokens = tokenize(substring)

        // Offset tokens to document coordinates
        let offsetTokens = tokens.map { (NSRange(location: $0.0.location + highlightRange.location, length: $0.0.length), $0.1) }

        applyHighlighting(offsetTokens, to: textStorage, font: font, affectedRange: highlightRange)
        lastViewportRange = highlightRange
    }

    // MARK: - Snippet Highlighting (for search results)

    func highlightSnippet(_ code: String, languageID: String? = nil) -> NSAttributedString? {
        guard !code.isEmpty else { return nil }

        // For snippets, temporarily use the given language if different
        let savedLang = currentLanguage
        let savedRules = compiledRules
        defer {
            if languageID != currentLanguageID {
                currentLanguage = savedLang
                compiledRules = savedRules
            }
        }

        if let langID = languageID, langID != currentLanguageID {
            if let lang = LanguageRegistry.shared.language(forID: langID) {
                compileRules(for: lang)
                currentLanguage = lang
            }
        }

        let tokens = tokenize(code)
        let isDark = AppSettings.shared.isDarkMode

        let result = NSMutableAttributedString(string: code, attributes: [
            .foregroundColor: AppSettings.shared.editorTextColor
        ])

        for (range, color) in tokens {
            guard NSMaxRange(range) <= result.length else { continue }
            let finalColor = isDark ? Self.boostColorIfNeeded(color, against: AppSettings.shared.editorBackgroundColor) : color
            result.addAttribute(.foregroundColor, value: finalColor, range: range)
        }

        return result
    }

    /// Language ID for a BoBoNotes language ID (public for search results).
    /// Now returns the ID as-is since we use LanguageRegistry directly.
    func highlightrLanguageID(for boboID: String) -> String {
        return boboID
    }

    // MARK: - Tokenization

    /// Tokenize text using the compiled regex rules for the current language.
    /// Returns an array of (range, color) pairs.
    private func tokenize(_ text: String) -> [(NSRange, NSColor)] {
        guard !compiledRules.isEmpty else { return [] }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let isDark = AppSettings.shared.isDarkMode

        // First pass: collect all matches with priority (earlier rules = higher priority).
        // Use sorted occupied ranges + binary search instead of a per-character Bool array
        // to reduce memory and iteration cost for large files with sparse tokens.
        var occupiedRanges: [(Int, Int)] = []  // sorted (start, end) pairs
        var tokens: [(NSRange, NSColor)] = []

        for rule in compiledRules {
            let matches = rule.regex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                let range = match.range
                guard range.length > 0, NSMaxRange(range) <= nsText.length else { continue }

                let start = range.location
                let end = NSMaxRange(range)

                // Binary search for overlap with any occupied range
                if hasOverlap(occupiedRanges, start: start, end: end) { continue }

                // Insert into sorted list maintaining order
                let insertIdx = occupiedRanges.firstIndex(where: { $0.0 >= start }) ?? occupiedRanges.count
                occupiedRanges.insert((start, end), at: insertIdx)

                let color = Self.color(for: rule.tokenType, isDark: isDark)
                tokens.append((range, color))
            }
        }

        return tokens
    }

    /// Check if a range [start, end) overlaps any range in the sorted occupied list.
    private func hasOverlap(_ ranges: [(Int, Int)], start: Int, end: Int) -> Bool {
        guard !ranges.isEmpty else { return false }
        // Binary search: find the first range whose end > start
        var lo = 0, hi = ranges.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if ranges[mid].1 <= start {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        // Check from lo onward: any range that starts before our end overlaps
        if lo < ranges.count && ranges[lo].0 < end {
            return true
        }
        // Also check the range just before lo (it could extend into our range)
        if lo > 0 && ranges[lo - 1].1 > start {
            return true
        }
        return false
    }

    // MARK: - Rule Compilation

    private func compileRules(for lang: LanguageDefinition?) {
        guard let lang = lang else {
            compiledRules = []
            return
        }

        var rules: [(regex: NSRegularExpression, tokenType: TokenType)] = []

        // 1. Block comments (highest priority — must come before line comments)
        if let start = lang.blockCommentStart, let end = lang.blockCommentEnd {
            let startEsc = NSRegularExpression.escapedPattern(for: start)
            let endEsc = NSRegularExpression.escapedPattern(for: end)
            if let regex = try? NSRegularExpression(pattern: "\(startEsc)[\\s\\S]*?\(endEsc)", options: []) {
                rules.append((regex, .comment))
            }
        }

        // 2. Line comments
        if let lineComment = lang.lineComment {
            let escaped = NSRegularExpression.escapedPattern(for: lineComment)
            if let regex = try? NSRegularExpression(pattern: "\(escaped).*$", options: .anchorsMatchLines) {
                rules.append((regex, .comment))
            }
        }

        // 3. Strings (double-quoted and single-quoted with escape support)
        for delim in lang.stringDelimiters {
            let delimEsc = NSRegularExpression.escapedPattern(for: String(delim))
            // Match string with escape sequences
            if let regex = try? NSRegularExpression(pattern: "\(delimEsc)(?:[^\\\\\(delimEsc)\\n]|\\\\.)*\(delimEsc)", options: []) {
                rules.append((regex, .string))
            }
        }

        // Multi-line strings: triple-quoted (Python, Swift)
        if lang.stringDelimiters.contains("\"") {
            if let regex = try? NSRegularExpression(pattern: "\"\"\"[\\s\\S]*?\"\"\"", options: []) {
                // Insert before single-quote strings so triple-quotes take priority
                rules.insert((regex, .string), at: rules.count - lang.stringDelimiters.count)
            }
        }

        // Backtick strings (JavaScript/TypeScript template literals)
        if ["javascript", "typescript"].contains(lang.id) {
            if let regex = try? NSRegularExpression(pattern: "`(?:[^\\\\`]|\\\\.)*`", options: [.dotMatchesLineSeparators]) {
                rules.append((regex, .string))
            }
        }

        // 4. Preprocessor directives
        if let prefix = lang.preprocessorPrefix {
            let escaped = NSRegularExpression.escapedPattern(for: prefix)
            if let regex = try? NSRegularExpression(pattern: "^\(escaped)\\w+.*$", options: .anchorsMatchLines) {
                rules.append((regex, .preprocessor))
            }
        }

        // 5. Numbers
        if !lang.numberPattern.isEmpty {
            if let regex = try? NSRegularExpression(pattern: lang.numberPattern, options: []) {
                rules.append((regex, .number))
            }
        }

        // Hex numbers (0x...)
        if let regex = try? NSRegularExpression(pattern: "\\b0[xX][0-9a-fA-F_]+\\b", options: []) {
            rules.append((regex, .number))
        }

        // 6. Types (before keywords, typically PascalCase or explicit type names)
        if !lang.types.isEmpty {
            let escaped = lang.types.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                rules.append((regex, .type))
            }
        }

        // 7. Keywords
        if !lang.keywords.isEmpty {
            let escaped = lang.keywords.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                rules.append((regex, .keyword))
            }
        }

        // 8. Built-in functions
        if !lang.builtinFunctions.isEmpty {
            let escaped = lang.builtinFunctions.map { NSRegularExpression.escapedPattern(for: $0) }
            let pattern = "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                rules.append((regex, .function))
            }
        }

        // 9. Extra rules from LanguageDefinition
        for extra in lang.extraRules {
            if let regex = try? NSRegularExpression(pattern: extra.pattern, options: []) {
                rules.append((regex, extra.tokenType))
            }
        }

        // 10. Attributes (e.g. @objc, @IBOutlet in Swift, decorators in Python)
        if ["swift", "python", "java", "typescript", "kotlin"].contains(lang.id) {
            if let regex = try? NSRegularExpression(pattern: "@\\w+", options: []) {
                rules.append((regex, .attribute))
            }
        }

        compiledRules = rules
    }

    // MARK: - Color Palette

    /// VS Code-inspired deterministic colors for each token type (Dark+ / Light+).
    private static func color(for token: TokenType, isDark: Bool) -> NSColor {
        if isDark {
            switch token {
            case .keyword:      return NSColor(calibratedRed: 0.337, green: 0.612, blue: 0.839, alpha: 1.0) // #569CD6
            case .string:       return NSColor(calibratedRed: 0.808, green: 0.569, blue: 0.471, alpha: 1.0) // #CE9178
            case .comment:      return NSColor(calibratedRed: 0.416, green: 0.600, blue: 0.333, alpha: 1.0) // #6A9955
            case .number:       return NSColor(calibratedRed: 0.710, green: 0.808, blue: 0.659, alpha: 1.0) // #B5CEA8
            case .type:         return NSColor(calibratedRed: 0.306, green: 0.788, blue: 0.690, alpha: 1.0) // #4EC9B0
            case .function:     return NSColor(calibratedRed: 0.863, green: 0.863, blue: 0.667, alpha: 1.0) // #DCDCAA
            case .operator:     return NSColor(calibratedRed: 0.831, green: 0.831, blue: 0.831, alpha: 1.0) // #D4D4D4
            case .preprocessor: return NSColor(calibratedRed: 0.773, green: 0.525, blue: 0.753, alpha: 1.0) // #C586C0
            case .attribute:    return NSColor(calibratedRed: 0.612, green: 0.863, blue: 0.996, alpha: 1.0) // #9CDCFE
            case .variable:     return NSColor(calibratedRed: 0.612, green: 0.863, blue: 0.996, alpha: 1.0) // #9CDCFE
            case .plain:        return AppSettings.shared.editorTextColor
            }
        } else {
            switch token {
            case .keyword:      return NSColor(calibratedRed: 0.000, green: 0.000, blue: 1.000, alpha: 1.0) // #0000FF
            case .string:       return NSColor(calibratedRed: 0.639, green: 0.082, blue: 0.082, alpha: 1.0) // #A31515
            case .comment:      return NSColor(calibratedRed: 0.000, green: 0.502, blue: 0.000, alpha: 1.0) // #008000
            case .number:       return NSColor(calibratedRed: 0.035, green: 0.525, blue: 0.345, alpha: 1.0) // #098658
            case .type:         return NSColor(calibratedRed: 0.149, green: 0.498, blue: 0.600, alpha: 1.0) // #267F99
            case .function:     return NSColor(calibratedRed: 0.475, green: 0.369, blue: 0.149, alpha: 1.0) // #795E26
            case .operator:     return NSColor(calibratedRed: 0.000, green: 0.000, blue: 0.000, alpha: 1.0) // #000000
            case .preprocessor: return NSColor(calibratedRed: 0.686, green: 0.000, blue: 0.859, alpha: 1.0) // #AF00DB
            case .attribute:    return NSColor(calibratedRed: 0.000, green: 0.063, blue: 0.502, alpha: 1.0) // #001080
            case .variable:     return NSColor(calibratedRed: 0.000, green: 0.063, blue: 0.502, alpha: 1.0) // #001080
            case .plain:        return AppSettings.shared.editorTextColor
            }
        }
    }

    // MARK: - Apply

    private func applyHighlighting(
        _ tokens: [(NSRange, NSColor)],
        to textStorage: NSTextStorage,
        font: NSFont,
        affectedRange: NSRange? = nil
    ) {
        let defaultFg = AppSettings.shared.editorTextColor
        let isDark = AppSettings.shared.isDarkMode
        let bgColor = AppSettings.shared.editorBackgroundColor
        let range = affectedRange ?? NSRange(location: 0, length: textStorage.length)

        textStorage.beginEditing()

        // Reset foreground to default first
        textStorage.addAttribute(.foregroundColor, value: defaultFg, range: range)
        textStorage.addAttribute(.font, value: font, range: range)

        // Apply token colors — use per-color boost cache to avoid repeated
        // color space conversions (relativeLuminance → getHue → NSColor init).
        var localBoostCache: [NSColor: NSColor] = [:]
        for (tokenRange, color) in tokens {
            guard NSMaxRange(tokenRange) <= textStorage.length else { continue }
            let finalColor: NSColor
            if isDark {
                if let cached = localBoostCache[color] {
                    finalColor = cached
                } else {
                    let boosted = Self.boostColorIfNeeded(color, against: bgColor)
                    localBoostCache[color] = boosted
                    finalColor = boosted
                }
            } else {
                finalColor = color
            }
            textStorage.addAttribute(.foregroundColor, value: finalColor, range: tokenRange)
        }

        textStorage.endEditing()
    }

    // MARK: - Contrast Boost (WCAG Accessibility)

    private static func boostColorIfNeeded(_ color: NSColor, against bg: NSColor) -> NSColor {
        let fgLum = relativeLuminance(of: color)
        let bgLum = relativeLuminance(of: bg)
        let contrast = (max(fgLum, bgLum) + 0.05) / (min(fgLum, bgLum) + 0.05)

        if contrast < 4.0 {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard let srgb = color.usingColorSpace(.sRGB) else { return color }
            srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let boosted = max(b, 0.55)
            return NSColor(hue: h, saturation: s * 0.85, brightness: boosted, alpha: a)
        }
        return color
    }

    private static func relativeLuminance(of color: NSColor) -> CGFloat {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        func linearize(_ v: CGFloat) -> CGFloat {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(c.redComponent)
             + 0.7152 * linearize(c.greenComponent)
             + 0.0722 * linearize(c.blueComponent)
    }

    // MARK: - Invalidate

    func invalidateThemeCache() {
        lastThemeWasDark = nil
        lastAppliedTheme = nil
        cachedHighlightText = nil
        cachedHighlightResult = nil
        lastViewportRange = nil

        updateTheme()
    }
}
