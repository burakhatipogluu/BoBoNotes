import AppKit

/// A standalone gutter view that displays line numbers and code folding indicators.
/// Positioned side-by-side with the NSScrollView (NOT as an NSRulerView) to avoid
/// macOS Tahoe's broken ruler offset mechanism.
final class LineNumberGutterView: NSView {

    private weak var editorTextView: NSTextView?
    private weak var editorScrollView: NSScrollView?
    private var font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)

    /// Must be flipped to match NSTextView's flipped coordinate system
    override var isFlipped: Bool { true }

    // MARK: - Computed colors

    private var gutterBackgroundColor: NSColor {
        guard let textView = editorTextView, let srgb = textView.backgroundColor.usingColorSpace(.sRGB) else {
            return .controlBackgroundColor
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        if luminance < 0.5 {
            return NSColor(calibratedRed: min(r + 0.03, 1), green: min(g + 0.03, 1), blue: min(b + 0.03, 1), alpha: a)
        } else {
            return NSColor(calibratedRed: max(r - 0.04, 0), green: max(g - 0.04, 0), blue: max(b - 0.04, 0), alpha: a)
        }
    }

    private var mutedLineNumberColor: NSColor {
        guard let textView = editorTextView, let srgb = textView.backgroundColor.usingColorSpace(.sRGB) else {
            return .tertiaryLabelColor
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.5
            ? NSColor(calibratedWhite: 0.45, alpha: 1.0)
            : NSColor(calibratedWhite: 0.65, alpha: 1.0)
    }

    private var activeLineNumberColor: NSColor {
        guard let textView = editorTextView, let srgb = textView.backgroundColor.usingColorSpace(.sRGB) else {
            return .labelColor
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.5
            ? NSColor(calibratedWhite: 0.95, alpha: 1.0)
            : NSColor(calibratedWhite: 0.15, alpha: 1.0)
    }

    private let foldingService = CodeFoldingService()
    private(set) var foldableRegions: [FoldableRegion] = []
    var onFoldToggle: ((Int) -> Void)?

    // MARK: - Hover-Only Fold Indicators
    private var isMouseInGutter = false
    private var mouseHoverLineIndex: Int? = nil
    private var trackingArea: NSTrackingArea?
    /// Callback to highlight the fold region range in the editor (startLine, endLine) or nil to clear
    var onFoldRegionHighlight: ((Int, Int)?) -> Void = { _ in }

    var currentLineIndex: Int = 0 {
        didSet {
            if oldValue != currentLineIndex {
                needsDisplay = true
            }
        }
    }

    /// Bookmarked lines (0-indexed) — synced from EditorTab
    var bookmarkedLines: Set<Int> = [] {
        didSet {
            if oldValue != bookmarkedLines {
                needsDisplay = true
            }
        }
    }

    /// Callback when a bookmark is toggled via gutter click
    var onBookmarkToggle: ((Int) -> Void)?

    // MARK: - Gutter Lane Widths
    private let bookmarkLaneWidth: CGFloat = 14
    private let foldLaneWidth: CGFloat = 14
    private let gutterPadding: CGFloat = 8  // left + right padding combined

    /// Current computed width of the gutter
    private(set) var gutterWidth: CGFloat = 48

    /// Line number mode: "absolute", "relative", "interval"
    var lineNumberMode: String = "absolute" {
        didSet { needsDisplay = true }
    }

    /// Callback when gutter width changes (wrapper view needs to re-layout)
    var onWidthChanged: ((CGFloat) -> Void)?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.editorTextView = textView
        self.editorScrollView = scrollView
        super.init(frame: .zero)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )
        // Note: scroll sync is handled synchronously by BoBoClipView.scroll(to:)
        // — no boundsDidChange notification observer needed here.
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInGutter = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInGutter = false
        mouseHoverLineIndex = nil
        onFoldRegionHighlight(nil)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        guard isMouseInGutter else { return }
        let point = convert(event.locationInWindow, from: nil)

        // Only track hover in fold lane area
        guard point.x >= foldLaneX else {
            if mouseHoverLineIndex != nil {
                mouseHoverLineIndex = nil
                onFoldRegionHighlight(nil)
                needsDisplay = true
            }
            return
        }

        let hoveredLine = lineIndexAtPoint(point)
        if hoveredLine != mouseHoverLineIndex {
            mouseHoverLineIndex = hoveredLine
            // Check if this line has a fold region
            if let line = hoveredLine,
               let region = foldableRegions.first(where: { $0.startLine == line && !$0.isFolded }) {
                onFoldRegionHighlight((region.startLine, region.endLine))
            } else {
                onFoldRegionHighlight(nil)
            }
            needsDisplay = true
        }
    }

    @objc private func textDidChange(_ notification: Notification) {
        updateFoldableRegions()
        needsDisplay = true
        updateGutterWidth()
    }

    func updateFoldableRegions() {
        guard let textView = editorTextView else { return }
        foldableRegions = foldingService.detectFoldableRegions(in: textView.string)
    }

    func updateLineNumberFont(_ newFont: NSFont) {
        let size = min(newFont.pointSize, 11)
        self.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        cachedMaxDigitWidth = nil  // Invalidate digit width cache
        updateGutterWidth()
        needsDisplay = true
    }

    /// Cached widest digit width — invalidated when font changes
    private var cachedMaxDigitWidth: CGFloat?

    /// Measure the widest digit (0-9) in the current font for accurate width calculation
    private var maxDigitWidth: CGFloat {
        if let cached = cachedMaxDigitWidth { return cached }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var maxWidth: CGFloat = 0
        for digit in 0...9 {
            let w = ("\(digit)" as NSString).size(withAttributes: attrs).width
            if w > maxWidth { maxWidth = w }
        }
        cachedMaxDigitWidth = maxWidth
        return maxWidth
    }

    /// Fast newline count without allocating a [String] array.
    private static func fastLineCount(_ string: String) -> Int {
        var count = 1
        for byte in string.utf8 {
            if byte == 0x0A { count += 1 }
        }
        return count
    }

    private func updateGutterWidth() {
        guard let textView = editorTextView else { return }
        let lineCount = max(Self.fastLineCount(textView.string), 1)
        let digitCount = max(String(lineCount).count, 5) // minimum 5 chars width
        let lineNumberWidth = CGFloat(digitCount) * maxDigitWidth
        let newWidth = bookmarkLaneWidth + lineNumberWidth + foldLaneWidth + gutterPadding
        if abs(gutterWidth - newWidth) > 1 {
            gutterWidth = newWidth
            onWidthChanged?(gutterWidth)
        }
    }

    // MARK: - Active line highlight color (slightly brighter/darker than gutter bg)

    private var activeLineHighlightColor: NSColor {
        guard let textView = editorTextView, let srgb = textView.backgroundColor.usingColorSpace(.sRGB) else {
            return NSColor.controlAccentColor.withAlphaComponent(0.05)
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        if luminance < 0.5 {
            // Dark theme: lighten
            return NSColor(calibratedRed: min(r + 0.06, 1), green: min(g + 0.06, 1), blue: min(b + 0.06, 1), alpha: a)
        } else {
            // Light theme: darken
            return NSColor(calibratedRed: max(r - 0.06, 0), green: max(g - 0.06, 0), blue: max(b - 0.06, 0), alpha: a)
        }
    }

    // MARK: - Lane layout helpers

    /// X offset where line number lane starts
    private var lineNumberLaneX: CGFloat { bookmarkLaneWidth }

    /// Width available for line numbers
    private var lineNumberLaneWidth: CGFloat {
        gutterWidth - bookmarkLaneWidth - foldLaneWidth - gutterPadding
    }

    /// X offset where fold lane starts
    private var foldLaneX: CGFloat { gutterWidth - foldLaneWidth }

    // MARK: - Display string for line number mode

    private func displayString(forLine lineNumber: Int) -> String {
        let lineIdx = lineNumber - 1
        switch lineNumberMode {
        case "relative":
            if lineIdx == currentLineIndex {
                return "\(lineNumber)"  // Current line shows absolute
            }
            return "\(abs(lineIdx - currentLineIndex))"
        case "interval":
            if lineIdx == currentLineIndex {
                return "\(lineNumber)"  // Current line shows absolute
            }
            if lineNumber % 10 == 0 {
                return "\(lineNumber)"  // Every 10th line shows absolute
            }
            return "\(abs(lineIdx - currentLineIndex))"
        default: // "absolute"
            return "\(lineNumber)"
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let textView = editorTextView,
              let scrollView = editorScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // Draw gutter background — use bounds intersection to guarantee we never
        // paint outside our frame, even if dirtyRect is unexpectedly large.
        gutterBackgroundColor.set()
        bounds.intersection(dirtyRect).fill()

        // Draw subtle separator line on the right edge
        NSColor.separatorColor.withAlphaComponent(0.15).set()
        let separatorRect = NSRect(x: bounds.maxX - 0.5, y: dirtyRect.minY, width: 0.5, height: dirtyRect.height)
        separatorRect.fill()

        let string = textView.string as NSString
        let containerOrigin = textView.textContainerOrigin
        let clipBounds = scrollView.contentView.bounds
        let scrollY = clipBounds.origin.y

        guard string.length > 0 else {
            // Draw active line highlight for empty document
            let y = containerOrigin.y - scrollY
            let lineH = font.pointSize + 4
            drawActiveLineBackground(y: y, height: lineH)

            let lineStr = "1" as NSString
            let drawAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold),
                .foregroundColor: activeLineNumberColor
            ]
            let size = lineStr.size(withAttributes: drawAttrs)
            let x = lineNumberLaneX + lineNumberLaneWidth - size.width
            lineStr.draw(at: NSPoint(x: x, y: y), withAttributes: drawAttrs)
            return
        }

        // Get visible range from scroll position
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: clipBounds, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var lineNumber = 1

        // Count lines before visible range
        if visibleCharRange.location > 0 {
            let prefixRange = NSRange(location: 0, length: visibleCharRange.location)
            string.enumerateSubstrings(in: prefixRange, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                lineNumber += 1
            }
        }

        // Text attributes
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: mutedLineNumberColor
        ]
        let currentAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .semibold),
            .foregroundColor: activeLineNumberColor
        ]

        var index = visibleCharRange.location
        let endIndex = NSMaxRange(visibleCharRange)

        while index <= endIndex && index <= string.length {
            let lineRange: NSRange
            if index < string.length {
                lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            } else {
                lineRange = NSRange(location: index, length: 0)
            }

            let safeCharIndex = min(index, max(0, string.length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeCharIndex)
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

            // Convert text document Y to gutter view Y (subtract scroll offset)
            let yPos = containerOrigin.y + lineFragmentRect.origin.y - scrollY

            let lineIdx = lineNumber - 1
            let isCurrent = lineIdx == currentLineIndex

            // --- Lane 0: Active line highlight (full gutter width) ---
            if isCurrent {
                drawActiveLineBackground(y: yPos, height: lineFragmentRect.height)
            }

            // --- Lane 1: Bookmark indicator ---
            if bookmarkedLines.contains(lineIdx) {
                let dotSize: CGFloat = 6
                let dotX = (bookmarkLaneWidth - dotSize) / 2
                let dotY = yPos + (lineFragmentRect.height - dotSize) / 2
                let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                NSColor.systemBlue.withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }

            // --- Lane 2: Line number ---
            let displayStr = displayString(forLine: lineNumber)
            let lineStr = displayStr as NSString
            let drawAttrs = isCurrent ? currentAttrs : attrs
            let size = lineStr.size(withAttributes: drawAttrs)
            let y = yPos + (lineFragmentRect.height - size.height) / 2.0
            let x = lineNumberLaneX + lineNumberLaneWidth - size.width  // Right-aligned in lane
            lineStr.draw(at: NSPoint(x: x, y: y), withAttributes: drawAttrs)

            // --- Lane 3: Fold indicator (hover-only for expanded, always for folded) ---
            if let region = foldableRegions.first(where: { $0.startLine == lineIdx }) {
                let shouldShow = region.isFolded || isMouseInGutter
                if shouldShow {
                    let indicatorSize: CGFloat = 8
                    let ix = foldLaneX + (foldLaneWidth - indicatorSize) / 2
                    let iy = yPos + (lineFragmentRect.height - indicatorSize) / 2
                    let isHovered = mouseHoverLineIndex == lineIdx

                    let indicatorRect = NSRect(x: ix, y: iy, width: indicatorSize, height: indicatorSize)
                    let path = NSBezierPath()

                    if region.isFolded {
                        // Right-pointing triangle (folded)
                        path.move(to: NSPoint(x: indicatorRect.minX, y: indicatorRect.minY))
                        path.line(to: NSPoint(x: indicatorRect.maxX, y: indicatorRect.midY))
                        path.line(to: NSPoint(x: indicatorRect.minX, y: indicatorRect.maxY))
                        path.close()
                    } else {
                        // Down-pointing triangle (expanded)
                        path.move(to: NSPoint(x: indicatorRect.minX, y: indicatorRect.minY))
                        path.line(to: NSPoint(x: indicatorRect.maxX, y: indicatorRect.minY))
                        path.line(to: NSPoint(x: indicatorRect.midX, y: indicatorRect.maxY))
                        path.close()
                    }

                    let alpha: CGFloat = isHovered ? 0.9 : 0.5
                    NSColor.secondaryLabelColor.withAlphaComponent(alpha).setFill()
                    path.fill()
                }
            }

            // --- Lane 3b: Fold scope vertical line ---
            // Draw a thin vertical line in the fold lane for lines that are inside a fold region
            if isMouseInGutter {
                for region in foldableRegions where !region.isFolded {
                    if lineIdx > region.startLine && lineIdx <= region.endLine {
                        let lineX = foldLaneX + foldLaneWidth / 2
                        NSColor.secondaryLabelColor.withAlphaComponent(0.2).setFill()
                        NSRect(x: lineX - 0.5, y: yPos, width: 1, height: lineFragmentRect.height).fill()
                        break  // Only draw for the innermost containing region
                    }
                }
            }

            lineNumber += 1

            if lineRange.length == 0 {
                break
            }
            index = NSMaxRange(lineRange)
        }
    }

    /// Draw the active line highlight across the full gutter width
    private func drawActiveLineBackground(y: CGFloat, height: CGFloat) {
        activeLineHighlightColor.setFill()
        NSRect(x: 0, y: y, width: bounds.width, height: height).fill()
    }

    // MARK: - Line index from point

    /// Given a point in the gutter's coordinate system, determine the 0-indexed line number.
    private func lineIndexAtPoint(_ point: NSPoint) -> Int? {
        guard let textView = editorTextView,
              let scrollView = editorScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return nil }

        let string = textView.string as NSString
        guard string.length > 0 else { return nil }

        let clipBounds = scrollView.contentView.bounds
        let containerOrigin = textView.textContainerOrigin
        let scrollY = clipBounds.origin.y
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: clipBounds, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        if visibleCharRange.location > 0 {
            let prefixRange = NSRange(location: 0, length: visibleCharRange.location)
            string.enumerateSubstrings(in: prefixRange, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                lineNumber += 1
            }
        }

        var index = visibleCharRange.location
        let endIndex = NSMaxRange(visibleCharRange)

        while index <= endIndex && index <= string.length {
            let lineRange: NSRange
            if index < string.length {
                lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            } else {
                lineRange = NSRange(location: index, length: 0)
            }

            let safeCharIndex = min(index, max(0, string.length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeCharIndex)
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let yPos = containerOrigin.y + lineFragmentRect.origin.y - scrollY

            if point.y >= yPos && point.y <= yPos + lineFragmentRect.height {
                return lineNumber - 1  // 0-indexed
            }

            lineNumber += 1
            if lineRange.length == 0 { break }
            index = NSMaxRange(lineRange)
        }
        return nil
    }

    // MARK: - Click handling for fold toggling

    override func mouseDown(with event: NSEvent) {
        guard let textView = editorTextView,
              let scrollView = editorScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)

        // Determine click zone: bookmark lane (left) vs fold lane (right) vs line number (middle)
        let isInFoldArea = point.x >= foldLaneX
        let isInBookmarkArea = point.x < bookmarkLaneWidth

        // Determine which line was clicked
        let string = textView.string as NSString
        guard string.length > 0 else { return }

        let clipBounds = scrollView.contentView.bounds
        let containerOrigin = textView.textContainerOrigin
        let scrollY = clipBounds.origin.y
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: clipBounds, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        var lineNumber = 1
        if visibleCharRange.location > 0 {
            let prefixRange = NSRange(location: 0, length: visibleCharRange.location)
            string.enumerateSubstrings(in: prefixRange, options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                lineNumber += 1
            }
        }

        var index = visibleCharRange.location
        let endIndex = NSMaxRange(visibleCharRange)

        while index <= endIndex && index <= string.length {
            let lineRange: NSRange
            if index < string.length {
                lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            } else {
                lineRange = NSRange(location: index, length: 0)
            }

            let safeCharIndex = min(index, max(0, string.length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeCharIndex)
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let yPos = containerOrigin.y + lineFragmentRect.origin.y - scrollY

            if point.y >= yPos && point.y <= yPos + lineFragmentRect.height {
                let lineIdx = lineNumber - 1
                if isInFoldArea {
                    if foldableRegions.contains(where: { $0.startLine == lineIdx }) {
                        onFoldToggle?(lineIdx)
                    }
                } else if isInBookmarkArea {
                    onBookmarkToggle?(lineIdx)
                }
                return
            }

            lineNumber += 1
            if lineRange.length == 0 { break }
            index = NSMaxRange(lineRange)
        }
    }
}
