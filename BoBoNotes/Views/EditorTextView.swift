import SwiftUI
import AppKit

/// NSViewRepresentable wrapper for NSTextView with line numbers, undo/redo, and settings.
struct EditorTextView: NSViewRepresentable {
    @ObservedObject var tab: EditorTab
    @ObservedObject var settings: AppSettings

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        // --- ScrollView with custom ClipView for zero-lag gutter sync ---
        let scrollView = BoBoScrollView()
        let clipView = BoBoClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true

        // --- TextView (use default TextKit chain, no manual setup) ---
        let textView = BoBoTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = true           // Rich text for syntax highlighting
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = settings.enableSpellChecker
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false

        // --- Colors (MUST set BEFORE content) ---
        textView.drawsBackground = true
        textView.backgroundColor = settings.editorBackgroundColor
        // NOTE: Do NOT set textView.textColor — it overwrites all foreground attributes
        // in textStorage and wipes syntax highlighting. Use typingAttributes instead.
        textView.insertionPointColor = settings.editorCursorColor
        textView.font = settings.editorFont

        // --- Layout sizing ---
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = !settings.useSoftWrap
        textView.autoresizingMask = settings.useSoftWrap ? [.width] : []
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)

        // --- Delegate & undo ---
        textView.delegate = context.coordinator
        textView.customUndoManager = tab.document.undoManager

        // --- Add to scroll view ---
        scrollView.documentView = textView

        // --- Store refs ---
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        // --- Line number gutter (side-by-side with scroll view) ---
        let gutterView = LineNumberGutterView(textView: textView, scrollView: scrollView)
        context.coordinator.gutterView = gutterView
        clipView.gutterView = gutterView

        // --- Configure text container ---
        if settings.useSoftWrap {
            textView.textContainer?.widthTracksTextView = true
        } else {
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.layoutManager?.allowsNonContiguousLayout = true

        // --- Set content as attributed string with correct colors ---
        context.coordinator.isUpdating = true
        let contentAttrs: [NSAttributedString.Key: Any] = [
            .font: settings.editorFont,
            .foregroundColor: settings.editorTextColor,
        ]
        let attrStr = NSAttributedString(string: tab.document.content, attributes: contentAttrs)
        textView.textStorage?.setAttributedString(attrStr)
        context.coordinator.isUpdating = false

        // --- Now apply proper theme colors ---
        applyThemeColors(to: textView, scrollView: scrollView)

        // --- Store settings ref ---
        textView.settingsRef = settings
        textView.showInvisibles = settings.showInvisibles

        // --- Tab handling ---
        let coordinator = context.coordinator
        textView.tabHandler = { [weak coordinator] in
            guard let coord = coordinator else { return }
            if coord.parent.settings.useSpacesForTabs {
                let spaces = String(repeating: " ", count: coord.parent.settings.tabWidth)
                coord.textView?.insertText(spaces, replacementRange: coord.textView?.selectedRange() ?? NSRange())
            } else {
                coord.textView?.insertText("\t", replacementRange: coord.textView?.selectedRange() ?? NSRange())
            }
        }

        // --- Highlight recovery callbacks ---
        // Re-apply syntax colors when editor regains focus (e.g. after search panel)
        let coord2 = context.coordinator
        textView.onBecomeFirstResponder = { [weak coord2] in
            coord2?.scheduleHighlightRefresh(delay: 0.05)
        }
        // Re-apply after native find bar (Cmd+F) operations
        textView.onFindPanelAction = { [weak coord2] in
            coord2?.scheduleHighlightRefresh(delay: 0.15)
        }

        // --- Current line highlight ---
        textView.highlightColor = settings.currentLineHighlightColor
        if settings.highlightCurrentLine {
            context.coordinator.updateCurrentLineHighlight()
        }

        // --- Language detect ---
        context.coordinator.setupLanguage()

        // --- Drag & Drop ---
        textView.setupDragAndDrop()

        // --- Wrapper view: gutter + scroll view side by side ---
        let wrapperView = EditorWrapperView(gutterView: gutterView, scrollView: scrollView)
        wrapperView.isGutterVisible = settings.showLineNumbers
        context.coordinator.wrapperView = wrapperView

        // Re-layout when gutter width changes (e.g. line count 999→1000)
        gutterView.onWidthChanged = { [weak wrapperView] _ in
            wrapperView?.layoutSubviews()
        }

        // Bookmark toggle via gutter click
        let coord = context.coordinator
        gutterView.onBookmarkToggle = { [weak coord] lineIdx in
            guard let coord = coord else { return }
            coord.parent.tab.toggleBookmark(line: lineIdx)
            coord.gutterView?.bookmarkedLines = coord.parent.tab.bookmarkedLines
            coord.minimapView?.bookmarkedLines = coord.parent.tab.bookmarkedLines
            coord.overviewRulerView?.bookmarkedLines = coord.parent.tab.bookmarkedLines
            coord.overviewRulerView?.needsDisplay = true
        }

        // Sync initial bookmarks and line number mode
        gutterView.bookmarkedLines = tab.bookmarkedLines
        gutterView.lineNumberMode = settings.lineNumberMode

        // Fold region hover highlight callback
        gutterView.onFoldRegionHighlight = { [weak textView] range in
            guard let textView = textView else { return }
            if let (startLine, endLine) = range {
                // Calculate rect spanning startLine...endLine
                let string = textView.string as NSString
                guard string.length > 0,
                      let layoutManager = textView.layoutManager else {
                    textView.foldRegionHighlightRect = nil
                    textView.needsDisplay = true
                    return
                }

                // Find char index of startLine
                var line = 0
                var charIdx = 0
                while line < startLine && charIdx < string.length {
                    let lr = string.lineRange(for: NSRange(location: charIdx, length: 0))
                    charIdx = NSMaxRange(lr)
                    line += 1
                }
                let startGlyph = layoutManager.glyphIndexForCharacter(at: min(charIdx, max(0, string.length - 1)))
                let startRect = layoutManager.lineFragmentRect(forGlyphAt: startGlyph, effectiveRange: nil)

                // Find char index of endLine
                while line < endLine && charIdx < string.length {
                    let lr = string.lineRange(for: NSRange(location: charIdx, length: 0))
                    charIdx = NSMaxRange(lr)
                    line += 1
                }
                let endGlyph = layoutManager.glyphIndexForCharacter(at: min(charIdx, max(0, string.length - 1)))
                let endRect = layoutManager.lineFragmentRect(forGlyphAt: endGlyph, effectiveRange: nil)

                textView.foldRegionHighlightRect = NSRect(
                    x: 0,
                    y: startRect.origin.y,
                    width: textView.bounds.width,
                    height: endRect.maxY - startRect.origin.y
                )
            } else {
                textView.foldRegionHighlightRect = nil
            }
            textView.needsDisplay = true
        }

        // --- Minimap ---
        let minimapView = MinimapView(textView: textView, scrollView: scrollView)
        minimapView.bookmarkedLines = tab.bookmarkedLines
        wrapperView.installMinimap(minimapView)
        wrapperView.isMinimapVisible = settings.showMinimap
        (scrollView.contentView as? BoBoClipView)?.minimapView = minimapView
        context.coordinator.minimapView = minimapView

        // --- Overview Ruler ---
        let overviewRuler = OverviewRulerView(textView: textView, scrollView: scrollView)
        overviewRuler.bookmarkedLines = tab.bookmarkedLines
        overviewRuler.currentLineIndex = max(tab.cursorLine - 1, 0)
        overviewRuler.totalLineCount = Coordinator.fastLineCount(textView.string)
        wrapperView.installOverviewRuler(overviewRuler)
        wrapperView.isOverviewRulerVisible = settings.showOverviewRuler
        (scrollView.contentView as? BoBoClipView)?.overviewRulerView = overviewRuler
        context.coordinator.overviewRulerView = overviewRuler

        return wrapperView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = context.coordinator.textView,
              let scrollView = context.coordinator.scrollView else { return }

        // External content update only (Replace All, etc.)
        if context.coordinator.needsExternalContentUpdate && !context.coordinator.isUpdating {
            context.coordinator.isUpdating = true
            let cursor = textView.selectedRange()
            if let textStorage = textView.textStorage {
                let fullRange = NSRange(location: 0, length: textStorage.length)
                textStorage.beginEditing()
                textStorage.replaceCharacters(in: fullRange, with: tab.document.content)
                let newRange = NSRange(location: 0, length: textStorage.length)
                textStorage.addAttribute(.font, value: settings.editorFont, range: newRange)
                textStorage.addAttribute(.foregroundColor, value: settings.editorTextColor, range: newRange)
                textStorage.endEditing()
            }
            let safeLoc = min(cursor.location, (textView.string as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLoc, length: 0))
            context.coordinator.needsExternalContentUpdate = false
            context.coordinator.isUpdating = false
            // Synchronous highlighting — colors appear immediately
            context.coordinator.applySyntaxHighlighting(force: true)
        }

        // Keep syntax service in sync with currently displayed tab/document.
        // Without this, tab switches can momentarily show stale/default colors
        // until a later async pass re-highlights.
        let contextChanged = context.coordinator.syncLanguageAndDocumentIfNeeded()

        // Read appTheme so SwiftUI triggers updateNSView on theme change
        let _ = settings.appTheme

        // Apply theme colors every update (catches theme changes)
        applyThemeColors(to: textView, scrollView: scrollView)

        // Update syntax theme if light/dark changed
        let themeChanged = context.coordinator.syntaxService.updateTheme()
        if themeChanged || contextChanged {
            context.coordinator.applySyntaxHighlighting(force: true)
            // A short second pass fixes delayed attribute overrides from macOS find/layout.
            context.coordinator.scheduleHighlightRefresh(delay: 0.12)
        }

        // Font
        let newFont = settings.editorFont
        if textView.font != newFont {
            textView.font = newFont
            context.coordinator.gutterView?.updateLineNumberFont(newFont)
        }

        // Line numbers
        if let wrapperView = context.coordinator.wrapperView {
            wrapperView.isGutterVisible = settings.showLineNumbers
        }
        context.coordinator.gutterView?.lineNumberMode = settings.lineNumberMode

        // Wrap + container width (no gutter subtraction — scroll view is sized correctly)
        let shouldWrap = settings.useSoftWrap
        textView.isHorizontallyResizable = !shouldWrap
        if shouldWrap {
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: max(textView.frame.height, scrollView.contentSize.height)))
        } else {
            textView.autoresizingMask = []
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        // Minimap visibility
        if let wrapperView = context.coordinator.wrapperView {
            if wrapperView.isMinimapVisible != settings.showMinimap {
                wrapperView.isMinimapVisible = settings.showMinimap
            }
            if wrapperView.isOverviewRulerVisible != settings.showOverviewRuler {
                wrapperView.isOverviewRulerVisible = settings.showOverviewRuler
            }
        }

        // Show invisibles
        if textView.showInvisibles != settings.showInvisibles {
            textView.showInvisibles = settings.showInvisibles
            textView.needsDisplay = true
        }

        // Spell checker
        if textView.isContinuousSpellCheckingEnabled != settings.enableSpellChecker {
            textView.isContinuousSpellCheckingEnabled = settings.enableSpellChecker
        }

        textView.needsLayout = true
        textView.needsDisplay = true
    }

    /// Central place to apply all theme colors — called from both makeNSView and updateNSView
    private func applyThemeColors(to textView: BoBoTextView, scrollView: NSScrollView) {
        let bg = settings.editorBackgroundColor
        let fg = settings.editorTextColor
        let cursor = settings.editorCursorColor

        textView.backgroundColor = bg
        // NOTE: Do NOT set textView.textColor = fg — that overwrites all
        // foregroundColor attributes in textStorage and wipes syntax highlighting colors.
        // New text color is applied via typingAttributes (below).
        textView.insertionPointColor = cursor
        textView.highlightColor = settings.currentLineHighlightColor
        scrollView.backgroundColor = bg
        scrollView.drawsBackground = true

        // Also set typing attributes for new text
        textView.typingAttributes = [
            .font: settings.editorFont,
            .foregroundColor: fg,
        ]
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorTextView
        weak var textView: BoBoTextView?
        weak var scrollView: NSScrollView?
        weak var gutterView: LineNumberGutterView?
        weak var wrapperView: EditorWrapperView?
        weak var minimapView: MinimapView?
        weak var overviewRulerView: OverviewRulerView?
        var isUpdating = false
        var needsExternalContentUpdate = false
        let syntaxService = HighlightrSyntaxService()
        private var scrollObserver: Any?
        private var frameObserver: Any?
        private var textChangeHighlightWorkItem: DispatchWorkItem?
        private var viewportHighlightWorkItem: DispatchWorkItem?
        private var highlightRefreshWorkItem: DispatchWorkItem?
        private var textStatsWorkItem: DispatchWorkItem?
        private var activeDocumentID: UUID?
        private var activeLanguageID: String?

        init(_ parent: EditorTextView) {
            self.parent = parent
            super.init()
            setupNotificationObservers()
        }

        /// True when this coordinator's textView is the first responder (key editor).
        /// Used to guard notification handlers so broadcasts only affect the active editor.
        private var isFirstResponder: Bool {
            guard let tv = textView else { return false }
            return tv.window?.firstResponder === tv
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
            if let obs = scrollObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = frameObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            textChangeHighlightWorkItem?.cancel()
            viewportHighlightWorkItem?.cancel()
            highlightRefreshWorkItem?.cancel()
            textStatsWorkItem?.cancel()
        }

        private func setupNotificationObservers() {
            NotificationCenter.default.addObserver(self, selector: #selector(handleSelectRange(_:)), name: .selectRange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleFlashLine(_:)), name: .flashLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleTextContentDidChange(_:)), name: .textContentDidChange, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleGoToLine(_:)), name: .goToLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleLanguageDidChange(_:)), name: .languageDidChange, object: nil)
            // Line operations
            NotificationCenter.default.addObserver(self, selector: #selector(handleDuplicateLine), name: .duplicateLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleMoveLineUp), name: .moveLineUp, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleMoveLineDown), name: .moveLineDown, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleDeleteLine), name: .deleteLine, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleJoinLines), name: .joinLines, object: nil)
            // Comment toggle
            NotificationCenter.default.addObserver(self, selector: #selector(handleToggleComment), name: .toggleComment, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleToggleBlockComment), name: .toggleBlockComment, object: nil)
            // Trim whitespace
            NotificationCenter.default.addObserver(self, selector: #selector(handleTrimTrailingWhitespace), name: .trimTrailingWhitespace, object: nil)
            // Multi-cursor
            NotificationCenter.default.addObserver(self, selector: #selector(handleSelectNextOccurrence), name: .selectNextOccurrence, object: nil)
            // Go to matching bracket
            NotificationCenter.default.addObserver(self, selector: #selector(handleGoToMatchingBracket), name: .goToMatchingBracket, object: nil)
            // Convert case
            NotificationCenter.default.addObserver(self, selector: #selector(handleConvertToUppercase), name: .convertToUppercase, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleConvertToLowercase), name: .convertToLowercase, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleConvertToTitleCase), name: .convertToTitleCase, object: nil)
            // Sort lines
            NotificationCenter.default.addObserver(self, selector: #selector(handleSortLinesAscending), name: .sortLinesAscending, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleSortLinesDescending), name: .sortLinesDescending, object: nil)
            // Rich text formatting
            NotificationCenter.default.addObserver(self, selector: #selector(handleToggleBold), name: .toggleBold, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleToggleItalic), name: .toggleItalic, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleToggleUnderline), name: .toggleUnderline, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleToggleStrikethrough), name: .toggleStrikethrough, object: nil)
            // Bookmarks
            NotificationCenter.default.addObserver(self, selector: #selector(handleToggleBookmark), name: .toggleBookmark, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleNextBookmark), name: .nextBookmark, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handlePreviousBookmark), name: .previousBookmark, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleClearBookmarks), name: .clearBookmarks, object: nil)
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard let textView = textView, !isUpdating else { return }
            isUpdating = true
            parent.tab.document.content = textView.string
            parent.tab.document.isDirty = true
            isUpdating = false
            updateCursorInfo()
            updateCurrentLineHighlight()
            // Debounce syntax highlighting on text change (50ms)
            textChangeHighlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.applySyntaxHighlighting(force: true)
            }
            textChangeHighlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
            // Debounce text statistics (200ms) — word/char counting is O(n)
            textStatsWorkItem?.cancel()
            let statsWork = DispatchWorkItem { [weak self] in
                self?.updateTextStatistics()
            }
            textStatsWorkItem = statsWork
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: statsWork)
            // Update overview ruler line count — O(n) scan via fast byte count
            // (needsDisplay already set by updateCurrentLineHighlight above)
            overviewRulerView?.totalLineCount = Self.fastLineCount(textView.string)
        }

        /// Fast newline count without allocating a [String] array.
        static func fastLineCount(_ string: String) -> Int {
            var count = 1
            for byte in string.utf8 {
                if byte == 0x0A { count += 1 } // '\n'
            }
            return count
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updateCursorInfo()
            updateCurrentLineHighlight()
            updateBracketHighlighting()
            updateMarkOccurrences()
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            return parent.tab.document.undoManager
        }

        /// Keep typing attributes correct so new keystrokes get the right color
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            textView.typingAttributes = [
                .font: parent.settings.editorFont,
                .foregroundColor: parent.settings.editorTextColor,
            ]
            return true
        }

        // MARK: - Notification Handlers

        @objc private func handleSelectRange(_ notification: Notification) {
            guard let range = notification.object as? NSRange, let textView = textView else { return }
            // If notification carries a target tab ID, only respond if we're that tab
            if let userInfo = notification.userInfo,
               let tabID = userInfo["tabID"] as? UUID,
               tabID != parent.tab.id {
                return
            }
            // If no tabID, fall back to first responder check (for findNext/findPrevious)
            if notification.userInfo == nil && !isFirstResponder { return }
            // Grab focus if needed (e.g. clicking search result while panel has focus)
            if !isFirstResponder {
                textView.window?.makeFirstResponder(textView)
            }
            let len = (textView.string as NSString).length
            let safeLoc = min(range.location, len)
            let safeLen = min(range.length, len - safeLoc)
            let safeRange = NSRange(location: safeLoc, length: safeLen)
            textView.setSelectedRange(safeRange)
            textView.scrollRangeToVisible(safeRange)
            textView.showFindIndicator(for: safeRange)
            updateCursorInfo()
            updateCurrentLineHighlight()
            // showFindIndicator can corrupt foreground attributes on macOS Tahoe;
            // re-apply cached syntax colors after the animation finishes (~0.3s).
            scheduleHighlightRefresh()
        }

        @objc private func handleFlashLine(_ notification: Notification) {
            guard let textView = textView else { return }
            // If notification carries a target tab ID, only respond if we're that tab
            if let userInfo = notification.userInfo,
               let tabID = userInfo["tabID"] as? UUID,
               tabID != parent.tab.id {
                return
            }
            if notification.userInfo == nil && !isFirstResponder { return }
            let range = textView.selectedRange()
            let string = textView.string as NSString
            if range.location < string.length {
                let lineRange = string.lineRange(for: range)
                textView.showFindIndicator(for: lineRange)
                scheduleHighlightRefresh()
            }
        }

        @objc private func handleTextContentDidChange(_ notification: Notification) {
            guard isFirstResponder,
                  let newContent = notification.object as? String,
                  let textView = textView,
                  let textStorage = textView.textStorage else { return }
            isUpdating = true
            // Replace text content while preserving the text system chain
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: fullRange, with: newContent)
            let newRange = NSRange(location: 0, length: textStorage.length)
            textStorage.addAttribute(.font, value: parent.settings.editorFont, range: newRange)
            textStorage.addAttribute(.foregroundColor, value: parent.settings.editorTextColor, range: newRange)
            textStorage.endEditing()
            isUpdating = false
            // Highlight synchronously — colors appear immediately
            applySyntaxHighlighting(force: true)
        }

        @objc private func handleGoToLine(_ notification: Notification) {
            guard isFirstResponder, let lineNum = notification.object as? Int, let textView = textView else { return }
            let string = textView.string as NSString
            guard string.length > 0 else { return }
            var currentLine = 1
            var index = 0
            while currentLine < lineNum && index < string.length {
                let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
                currentLine += 1
                index = NSMaxRange(lineRange)
            }
            if currentLine == lineNum {
                let loc = min(index, string.length)
                let safeIdx = max(0, min(loc, string.length - 1))
                let lineRange = string.lineRange(for: NSRange(location: safeIdx, length: 0))
                textView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
                textView.scrollRangeToVisible(lineRange)
                textView.showFindIndicator(for: lineRange)
            }
        }

        @objc private func handleLanguageDidChange(_ notification: Notification) {
            guard isFirstResponder else { return }
            let doc = parent.tab.document
            if let langID = doc.languageID,
               let lang = LanguageRegistry.shared.language(forID: langID) {
                syntaxService.setLanguage(lang)
            } else {
                syntaxService.setLanguage(nil)
            }
            applySyntaxHighlighting()
        }

        // MARK: - Line Operation Handlers

        @objc private func handleSelectNextOccurrence() { guard isFirstResponder else { return }; textView?.selectNextOccurrence() }
        @objc private func handleGoToMatchingBracket() { guard isFirstResponder else { return }; textView?.goToMatchingBracket() }
        @objc private func handleConvertToUppercase() { guard isFirstResponder else { return }; textView?.convertToUppercase() }
        @objc private func handleConvertToLowercase() { guard isFirstResponder else { return }; textView?.convertToLowercase() }
        @objc private func handleConvertToTitleCase() { guard isFirstResponder else { return }; textView?.convertToTitleCase() }
        @objc private func handleSortLinesAscending() { guard isFirstResponder else { return }; textView?.sortLines(ascending: true) }
        @objc private func handleSortLinesDescending() { guard isFirstResponder else { return }; textView?.sortLines(ascending: false) }

        // MARK: - Rich Text Formatting Handlers

        @objc private func handleToggleBold() { guard isFirstResponder else { return }; textView?.toggleBold() }
        @objc private func handleToggleItalic() { guard isFirstResponder else { return }; textView?.toggleItalic() }
        @objc private func handleToggleUnderline() { guard isFirstResponder else { return }; textView?.toggleUnderline() }
        @objc private func handleToggleStrikethrough() { guard isFirstResponder else { return }; textView?.toggleStrikethrough() }

        // MARK: - Bookmark Handlers

        @objc private func handleToggleBookmark() {
            guard isFirstResponder else { return }
            let currentLine = parent.tab.cursorLine - 1  // 0-indexed
            parent.tab.toggleBookmark(line: currentLine)
            gutterView?.bookmarkedLines = parent.tab.bookmarkedLines
            minimapView?.bookmarkedLines = parent.tab.bookmarkedLines
            overviewRulerView?.bookmarkedLines = parent.tab.bookmarkedLines
            overviewRulerView?.needsDisplay = true
        }

        @objc private func handleNextBookmark() {
            guard isFirstResponder, let textView = textView else { return }
            let currentLine = parent.tab.cursorLine - 1
            guard let targetLine = parent.tab.nextBookmark(from: currentLine) else { return }
            goToLine(targetLine + 1, in: textView)  // goToLine expects 1-indexed
        }

        @objc private func handlePreviousBookmark() {
            guard isFirstResponder, let textView = textView else { return }
            let currentLine = parent.tab.cursorLine - 1
            guard let targetLine = parent.tab.previousBookmark(from: currentLine) else { return }
            goToLine(targetLine + 1, in: textView)
        }

        @objc private func handleClearBookmarks() {
            guard isFirstResponder else { return }
            parent.tab.clearBookmarks()
            gutterView?.bookmarkedLines = []
            minimapView?.bookmarkedLines = []
            overviewRulerView?.bookmarkedLines = []
            overviewRulerView?.needsDisplay = true
        }

        private func goToLine(_ lineNumber: Int, in textView: NSTextView) {
            let string = textView.string as NSString
            var currentLine = 1
            var index = 0
            while currentLine < lineNumber && index < string.length {
                let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
                currentLine += 1
                index = NSMaxRange(lineRange)
            }
            let targetRange = NSRange(location: min(index, string.length), length: 0)
            textView.setSelectedRange(targetRange)
            textView.scrollRangeToVisible(targetRange)
            updateCursorInfo()
            updateCurrentLineHighlight()
        }

        @objc private func handleDuplicateLine() { guard isFirstResponder else { return }; textView?.duplicateLine() }
        @objc private func handleMoveLineUp() { guard isFirstResponder else { return }; textView?.moveLineUp() }
        @objc private func handleMoveLineDown() { guard isFirstResponder else { return }; textView?.moveLineDown() }
        @objc private func handleDeleteLine() { guard isFirstResponder else { return }; textView?.deleteLine() }
        @objc private func handleJoinLines() { guard isFirstResponder else { return }; textView?.joinLines() }

        // MARK: - Comment Toggle Handlers

        @objc private func handleToggleComment() {
            guard isFirstResponder, let textView = textView else { return }
            let lang = syntaxService.currentLanguage
            guard let commentPrefix = lang?.lineComment, !commentPrefix.isEmpty else { return }

            let str = textView.string as NSString
            let sel = textView.selectedRange()
            let lineRange = str.lineRange(for: sel)
            let linesText = str.substring(with: lineRange)
            let lines = linesText.components(separatedBy: "\n")

            // Check if all non-empty lines are commented
            let nonEmptyLines = lines.enumerated().filter { $0.offset < lines.count - 1 || !$0.element.isEmpty }
            let allCommented = nonEmptyLines.allSatisfy { $0.element.trimmingCharacters(in: .whitespaces).hasPrefix(commentPrefix) }

            var result: [String] = []
            for (i, line) in lines.enumerated() {
                if i == lines.count - 1 && line.isEmpty {
                    result.append(line)
                    continue
                }
                if allCommented {
                    // Remove comment
                    if let range = line.range(of: commentPrefix + " ") {
                        var newLine = line
                        newLine.removeSubrange(range)
                        result.append(newLine)
                    } else if let range = line.range(of: commentPrefix) {
                        var newLine = line
                        newLine.removeSubrange(range)
                        result.append(newLine)
                    } else {
                        result.append(line)
                    }
                } else {
                    // Add comment - find leading whitespace and insert after it
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        result.append(line)
                    } else {
                        let wsCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                        let ws = String(line.prefix(wsCount))
                        let rest = String(line.dropFirst(wsCount))
                        result.append(ws + commentPrefix + " " + rest)
                    }
                }
            }

            let newText = result.joined(separator: "\n")
            if textView.shouldChangeText(in: lineRange, replacementString: newText) {
                let attrStr = NSAttributedString(string: newText, attributes: textView.typingAttributes)
                textView.textStorage?.replaceCharacters(in: lineRange, with: attrStr)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: lineRange.location, length: (newText as NSString).length))
            }
        }

        @objc private func handleToggleBlockComment() {
            guard isFirstResponder, let textView = textView else { return }
            let lang = syntaxService.currentLanguage
            guard let blockStart = lang?.blockCommentStart, let blockEnd = lang?.blockCommentEnd,
                  !blockStart.isEmpty, !blockEnd.isEmpty else { return }

            let sel = textView.selectedRange()
            let str = textView.string as NSString
            let selectedText = sel.length > 0 ? str.substring(with: sel) : ""

            if selectedText.hasPrefix(blockStart) && selectedText.hasSuffix(blockEnd) {
                // Remove block comment
                let inner = String(selectedText.dropFirst(blockStart.count).dropLast(blockEnd.count))
                if textView.shouldChangeText(in: sel, replacementString: inner) {
                    let attrStr = NSAttributedString(string: inner, attributes: textView.typingAttributes)
                    textView.textStorage?.replaceCharacters(in: sel, with: attrStr)
                    textView.didChangeText()
                    textView.setSelectedRange(NSRange(location: sel.location, length: (inner as NSString).length))
                }
            } else {
                // Add block comment
                let wrapped = blockStart + " " + selectedText + " " + blockEnd
                if textView.shouldChangeText(in: sel, replacementString: wrapped) {
                    let attrStr = NSAttributedString(string: wrapped, attributes: textView.typingAttributes)
                    textView.textStorage?.replaceCharacters(in: sel, with: attrStr)
                    textView.didChangeText()
                    textView.setSelectedRange(NSRange(location: sel.location, length: (wrapped as NSString).length))
                }
            }
        }

        // MARK: - Trim Trailing Whitespace Handler

        @objc private func handleTrimTrailingWhitespace() {
            guard isFirstResponder, let textView = textView else { return }
            let str = textView.string as NSString
            guard str.length > 0 else { return }

            guard let regex = try? NSRegularExpression(pattern: "[ \\t]+$", options: .anchorsMatchLines) else { return }
            let matches = regex.matches(in: textView.string, range: NSRange(location: 0, length: str.length))
            guard !matches.isEmpty else { return }

            // Apply replacements in reverse order to preserve ranges
            textView.undoManager?.beginUndoGrouping()
            for match in matches.reversed() {
                if textView.shouldChangeText(in: match.range, replacementString: "") {
                    textView.textStorage?.replaceCharacters(in: match.range, with: "")
                }
            }
            textView.didChangeText()
            textView.undoManager?.endUndoGrouping()
        }

        // MARK: - Cursor Info

        private func updateCursorInfo() {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange()
            let string = textView.string as NSString
            guard selectedRange.location <= string.length else { return }

            let location = selectedRange.location
            var lineNumber = 1
            var scanIndex = 0
            while scanIndex < location && scanIndex < string.length {
                let lineRange = string.lineRange(for: NSRange(location: scanIndex, length: 0))
                if NSMaxRange(lineRange) <= location {
                    lineNumber += 1
                    scanIndex = NSMaxRange(lineRange)
                } else {
                    break
                }
            }

            let safeIdx = string.length > 0 ? min(location, string.length - 1) : 0
            let lineRange = string.length > 0 ? string.lineRange(for: NSRange(location: safeIdx, length: 0)) : NSRange(location: 0, length: 0)
            let colNumber = location - lineRange.location + 1

            DispatchQueue.main.async { [weak self] in
                self?.parent.tab.cursorLine = lineNumber
                self?.parent.tab.cursorColumn = colNumber
                self?.parent.tab.selectedRange = selectedRange
            }
        }

        // MARK: - Text Statistics

        private func updateTextStatistics() {
            guard let textView = textView else { return }
            let text = textView.string
            let charCount = text.count
            let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            DispatchQueue.main.async { [weak self] in
                self?.parent.tab.charCount = charCount
                self?.parent.tab.wordCount = words.count
            }
        }

        // MARK: - Current Line Highlight

        func updateCurrentLineHighlight() {
            guard let textView = textView else { return }
            guard parent.settings.highlightCurrentLine else {
                textView.highlightedLineRect = nil
                textView.needsDisplay = true
                return
            }

            let selectedRange = textView.selectedRange()
            guard let layoutManager = textView.layoutManager,
                  (textView.string as NSString).length > 0 else {
                textView.highlightedLineRect = nil
                textView.needsDisplay = true
                return
            }

            let charIndex = min(selectedRange.location, max(0, (textView.string as NSString).length - 1))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

            textView.highlightedLineRect = NSRect(x: 0, y: lineRect.origin.y, width: textView.bounds.width, height: lineRect.height)
            textView.needsDisplay = true

            // Update ruler
            let string = textView.string as NSString
            var lineIndex = 0
            var idx = 0
            while idx < selectedRange.location && idx < string.length {
                let lr = string.lineRange(for: NSRange(location: idx, length: 0))
                if NSMaxRange(lr) <= selectedRange.location {
                    lineIndex += 1
                    idx = NSMaxRange(lr)
                } else {
                    break
                }
            }
            gutterView?.currentLineIndex = lineIndex
            minimapView?.currentLineIndex = lineIndex
            overviewRulerView?.currentLineIndex = lineIndex
            overviewRulerView?.needsDisplay = true
        }

        // MARK: - Safe Character Access

        /// Safely get a Character from an NSString at a UTF-16 index.
        /// Returns nil for unpaired surrogates (emoji, CJK extension B, etc.).
        private static func safeCharacter(at index: Int, in str: NSString) -> Character? {
            let code = str.character(at: index)
            guard let scalar = UnicodeScalar(code) else { return nil }
            return Character(scalar)
        }

        // MARK: - Bracket Matching

        private static let bracketHighlightKey = NSAttributedString.Key("BoBoNotesBracketHighlight")
        private var previousBracketRanges: [NSRange] = []

        private func updateBracketHighlighting() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  parent.settings.highlightMatchingBrackets else {
                clearBracketHighlights()
                return
            }

            // Clear previous highlights
            clearBracketHighlights()

            let str = textView.string as NSString
            guard str.length > 0 else { return }

            let cursorLoc = textView.selectedRange().location
            let bracketPairs: [(Character, Character)] = [("(", ")"), ("{", "}"), ("[", "]")]
            let openBrackets = bracketPairs.map { $0.0 }
            let closeBrackets = bracketPairs.map { $0.1 }

            // Check character at cursor and cursor-1
            for offset in [0, -1] {
                let checkLoc = cursorLoc + offset
                guard checkLoc >= 0, checkLoc < str.length else { continue }
                guard let ch = Self.safeCharacter(at: checkLoc, in: str) else { continue }

                if let pairIdx = openBrackets.firstIndex(of: ch) {
                    // Found opening bracket, search forward for matching close
                    let close = closeBrackets[pairIdx]
                    let open = openBrackets[pairIdx]
                    if let matchLoc = findMatchingBracketForward(in: str, from: checkLoc, open: open, close: close) {
                        highlightBrackets(at: [checkLoc, matchLoc], layoutManager: layoutManager, length: str.length)
                    }
                    return
                } else if let pairIdx = closeBrackets.firstIndex(of: ch) {
                    // Found closing bracket, search backward for matching open
                    let open = openBrackets[pairIdx]
                    let close = closeBrackets[pairIdx]
                    if let matchLoc = findMatchingBracketBackward(in: str, from: checkLoc, open: open, close: close) {
                        highlightBrackets(at: [matchLoc, checkLoc], layoutManager: layoutManager, length: str.length)
                    }
                    return
                }
            }
        }

        private func findMatchingBracketForward(in str: NSString, from: Int, open: Character, close: Character) -> Int? {
            var depth = 1
            var i = from + 1
            while i < str.length {
                guard let ch = Self.safeCharacter(at: i, in: str) else { i += 1; continue }
                if ch == open { depth += 1 }
                else if ch == close { depth -= 1; if depth == 0 { return i } }
                i += 1
            }
            return nil
        }

        private func findMatchingBracketBackward(in str: NSString, from: Int, open: Character, close: Character) -> Int? {
            var depth = 1
            var i = from - 1
            while i >= 0 {
                guard let ch = Self.safeCharacter(at: i, in: str) else { i -= 1; continue }
                if ch == close { depth += 1 }
                else if ch == open { depth -= 1; if depth == 0 { return i } }
                i -= 1
            }
            return nil
        }

        private func highlightBrackets(at positions: [Int], layoutManager: NSLayoutManager, length: Int) {
            let highlightColor = parent.settings.isDarkMode
                ? NSColor(calibratedRed: 0.4, green: 0.4, blue: 0.2, alpha: 0.5)
                : NSColor(calibratedRed: 0.85, green: 0.85, blue: 0.5, alpha: 0.7)
            for pos in positions {
                let range = NSRange(location: pos, length: 1)
                layoutManager.addTemporaryAttribute(.backgroundColor, value: highlightColor, forCharacterRange: range)
                previousBracketRanges.append(range)
            }
        }

        private func clearBracketHighlights() {
            guard let layoutManager = textView?.layoutManager else { return }
            for range in previousBracketRanges {
                let safeLen = (textView?.string as NSString?)?.length ?? 0
                if range.location + range.length <= safeLen {
                    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                }
            }
            previousBracketRanges.removeAll()
        }

        // MARK: - Mark Occurrences

        private var previousOccurrenceRanges: [NSRange] = []

        private func updateMarkOccurrences() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  parent.settings.markOccurrences else {
                clearOccurrenceHighlights()
                return
            }

            clearOccurrenceHighlights()

            let sel = textView.selectedRange()
            let str = textView.string as NSString
            guard sel.length > 0, sel.length < 100 else { return }

            let selectedText = str.substring(with: sel)
            // Only highlight if it's a word-like selection (no newlines)
            guard !selectedText.contains("\n"), !selectedText.contains("\r"),
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            // Search in visible range + buffer
            let visibleRect = textView.visibleRect
            guard let textContainer = textView.textContainer else { return }
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            // Expand range a bit for context
            let searchStart = max(0, charRange.location - 1000)
            let searchEnd = min(str.length, NSMaxRange(charRange) + 1000)
            let searchRange = NSRange(location: searchStart, length: searchEnd - searchStart)

            let highlightColor = parent.settings.isDarkMode
                ? NSColor(calibratedRed: 0.35, green: 0.35, blue: 0.15, alpha: 0.4)
                : NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.4, alpha: 0.5)

            var searchLoc = searchRange.location
            while searchLoc < NSMaxRange(searchRange) {
                let remaining = NSRange(location: searchLoc, length: NSMaxRange(searchRange) - searchLoc)
                let found = str.range(of: selectedText, options: [], range: remaining)
                guard found.location != NSNotFound else { break }

                // Don't highlight the original selection itself
                if found.location != sel.location || found.length != sel.length {
                    layoutManager.addTemporaryAttribute(.backgroundColor, value: highlightColor, forCharacterRange: found)
                    previousOccurrenceRanges.append(found)
                }
                searchLoc = NSMaxRange(found)
            }
        }

        private func clearOccurrenceHighlights() {
            guard let layoutManager = textView?.layoutManager else { return }
            let strLen = (textView?.string as NSString?)?.length ?? 0
            for range in previousOccurrenceRanges {
                if range.location + range.length <= strLen {
                    layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                }
            }
            previousOccurrenceRanges.removeAll()
        }

        // MARK: - Highlight Refresh (post-find-indicator / focus recovery)

        /// Schedule a delayed re-application of cached syntax colors.
        /// Used after operations that may corrupt foreground attributes
        /// (showFindIndicator, NSTextFinder, becomeFirstResponder).
        /// Cheap: re-applies cached token output without re-parsing.
        func scheduleHighlightRefresh(delay: TimeInterval = 0.3) {
            highlightRefreshWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.applySyntaxHighlighting(force: true)
            }
            highlightRefreshWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        // MARK: - Language & Syntax Highlighting

        @discardableResult
        func syncLanguageAndDocumentIfNeeded() -> Bool {
            let doc = parent.tab.document
            let docChanged = (activeDocumentID != doc.id)
            let langChanged = (activeLanguageID != doc.languageID)

            guard docChanged || langChanged else { return false }

            activeDocumentID = doc.id

            // Detect language from file extension if not already set
            if doc.languageID == nil {
                if let detected = LanguageRegistry.shared.detectLanguage(for: doc.fileURL) {
                    doc.languageID = detected.id
                    syntaxService.setLanguage(detected)
                } else {
                    syntaxService.setLanguage(nil)
                }
            } else if let langID = doc.languageID,
                      let lang = LanguageRegistry.shared.language(forID: langID) {
                syntaxService.setLanguage(lang)
            } else {
                syntaxService.setLanguage(nil)
            }

            activeLanguageID = doc.languageID
            return true
        }

        func setupLanguage() {
            _ = syncLanguageAndDocumentIfNeeded()

            // Highlight immediately (synchronous — no layout dependency)
            applySyntaxHighlighting(force: true)
            setupScrollObserver()
        }

        private func setupScrollObserver() {
            guard let scrollView = scrollView else { return }
            if let obs = scrollObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = frameObserver {
                NotificationCenter.default.removeObserver(obs)
            }

            // Observe clip view bounds changes (scroll) for viewport highlighting on large files
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                guard let self = self,
                      let textView = self.textView,
                      let textStorage = textView.textStorage,
                      textStorage.length > 500_000 else { return }
                // Debounce viewport highlighting (100ms after scroll stops)
                self.viewportHighlightWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak self] in
                    self?.applyViewportHighlighting(force: false)
                }
                self.viewportHighlightWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
            }
            scrollView.contentView.postsBoundsChangedNotifications = true

            // Observe clip view frame changes (window resize) to update gutter
            frameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.gutterView?.needsDisplay = true
            }
            scrollView.contentView.postsFrameChangedNotifications = true
        }

        func applySyntaxHighlighting(force: Bool = true) {
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  textStorage.length > 0,
                  syntaxService.currentLanguage != nil else { return }

            // Prevent recursive textDidChange triggers during highlighting
            isUpdating = true
            defer { isUpdating = false }

            if textStorage.length > 500_000 {
                // Large file: viewport-only highlighting
                applyViewportHighlighting(force: force)
            } else {
                syntaxService.highlightFullDocument(
                    textStorage: textStorage,
                    font: parent.settings.editorFont,
                    force: force
                )
            }
        }

        /// Highlight only the visible viewport for large files (>500K chars).
        func applyViewportHighlighting(force: Bool = false) {
            guard let textView = textView,
                  let textStorage = textView.textStorage,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = scrollView else { return }

            let clipBounds = scrollView.contentView.bounds
            let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: clipBounds, in: textContainer)
            let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

            syntaxService.highlightViewport(
                textStorage: textStorage,
                visibleCharRange: visibleCharRange,
                font: parent.settings.editorFont,
                force: force
            )
        }

    }
}

// MARK: - Custom ScrollView (ensures proper background drawing)

final class BoBoScrollView: NSScrollView {
    override var isOpaque: Bool { true }
}

// MARK: - Custom ClipView for synchronous gutter invalidation (zero-lag scroll sync)

final class BoBoClipView: NSClipView {
    weak var gutterView: LineNumberGutterView?
    weak var minimapView: MinimapView?
    weak var overviewRulerView: OverviewRulerView?

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: newOrigin)
        gutterView?.needsDisplay = true
        // Only invalidate minimap/ruler if minimap isn't currently drawing
        // (layout during minimap draw can trigger scroll, causing infinite recursion)
        if let minimap = minimapView, !minimap.isDrawing {
            minimap.needsDisplay = true
        }
        overviewRulerView?.needsDisplay = true
    }
}

// MARK: - Minimap (document overview with viewport indicator)

final class MinimapView: NSView {
    private weak var editorTextView: NSTextView?
    private weak var editorScrollView: NSScrollView?
    private var cachedLineColors: [(y: CGFloat, color: NSColor)] = []
    private var isDragging = false
    var isDrawing = false

    override var isFlipped: Bool { true }

    static let minimapWidth: CGFloat = 80

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.editorTextView = textView
        self.editorScrollView = scrollView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Bookmarked lines for minimap decoration (0-indexed)
    var bookmarkedLines: Set<Int> = []
    /// Current active line index (0-indexed)
    var currentLineIndex: Int = 0

    override func draw(_ dirtyRect: NSRect) {
        // Prevent recursive draw: layout can trigger scroll which triggers needsDisplay
        guard !isDrawing else { return }
        isDrawing = true
        defer { isDrawing = false }

        guard let textView = editorTextView,
              let scrollView = editorScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage else { return }

        // Background — slightly different from editor
        let bg = textView.backgroundColor.blended(withFraction: 0.05, of: .gray) ?? textView.backgroundColor
        bg.set()
        bounds.fill()

        // Separator on left edge
        NSColor.separatorColor.withAlphaComponent(0.15).set()
        NSRect(x: 0, y: dirtyRect.minY, width: 0.5, height: dirtyRect.height).fill()

        let string = textView.string as NSString
        guard string.length > 0 else { return }

        // Calculate scale: entire document height → minimap height
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        let fullRect = layoutManager.boundingRect(forGlyphRange: fullGlyphRange, in: textContainer)
        let docHeight = max(fullRect.height, 1)
        let scale = bounds.height / docHeight
        let lineHeight: CGFloat = max(1, 2 * scale)

        // Count total lines for sampling decision (fast byte scan, no allocation)
        let totalLines = EditorTextView.Coordinator.fastLineCount(textView.string)
        let sampleRate: Int
        if totalLines > 10000 { sampleRate = 4 }
        else if totalLines > 5000 { sampleRate = 2 }
        else { sampleRate = 1 }

        let defaultColor = (textView.textColor ?? .labelColor).withAlphaComponent(0.35)
        var lineIndex = 0
        var charIndex = 0

        while charIndex < string.length {
            let lineRange = string.lineRange(for: NSRange(location: charIndex, length: 0))

            // Line sampling for large files
            let shouldDraw = (sampleRate == 1 || lineIndex % sampleRate == 0)

            if shouldDraw {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
                let lineFragRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let y = lineFragRect.origin.y * scale

                // Token-colored minimap: read foreground colors from textStorage
                drawTokenColoredLine(
                    textStorage: textStorage,
                    lineRange: lineRange,
                    y: y,
                    lineHeight: lineHeight,
                    defaultColor: defaultColor
                )

                // Bookmark decoration (blue dot at left)
                if bookmarkedLines.contains(lineIndex) {
                    NSColor.systemBlue.withAlphaComponent(0.8).setFill()
                    NSRect(x: 0, y: y, width: 3, height: max(lineHeight, 2)).fill()
                }

                // Current line indicator
                if lineIndex == currentLineIndex {
                    NSColor.white.withAlphaComponent(0.3).setFill()
                    NSRect(x: 0, y: y, width: bounds.width, height: max(lineHeight, 1.5)).fill()
                }
            }

            lineIndex += 1
            charIndex = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
        }

        // Draw viewport indicator (semi-transparent rectangle showing visible area)
        let clipBounds = scrollView.contentView.bounds
        let viewportY = clipBounds.origin.y * scale
        let viewportH = max(clipBounds.height * scale, 10)
        let viewportRect = NSRect(x: 0, y: viewportY, width: bounds.width, height: viewportH)

        NSColor.white.withAlphaComponent(0.08).set()
        viewportRect.fill()
        NSColor.white.withAlphaComponent(0.2).set()
        NSBezierPath(rect: viewportRect).stroke()
    }

    /// Draw a single line with token colors from textStorage
    private func drawTokenColoredLine(
        textStorage: NSTextStorage,
        lineRange: NSRange,
        y: CGFloat,
        lineHeight: CGFloat,
        defaultColor: NSColor
    ) {
        guard lineRange.length > 0 else { return }

        let maxBarWidth = bounds.width - 8
        let charScale = min(maxBarWidth / max(CGFloat(lineRange.length), 1), 0.8)
        var xOffset: CGFloat = 4

        textStorage.enumerateAttribute(.foregroundColor, in: lineRange, options: []) { value, range, _ in
            let color: NSColor
            if let c = value as? NSColor {
                color = c.withAlphaComponent(0.5)
            } else {
                color = defaultColor
            }
            let tokenWidth = CGFloat(range.length) * charScale
            if tokenWidth > 0 {
                color.setFill()
                NSRect(x: xOffset, y: y, width: tokenWidth, height: lineHeight).fill()
                xOffset += tokenWidth
            }
        }
    }

    // Click to scroll editor
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        scrollToClick(event)
    }

    override func mouseDragged(with event: NSEvent) {
        if isDragging { scrollToClick(event) }
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    private func scrollToClick(_ event: NSEvent) {
        guard let textView = editorTextView,
              let scrollView = editorScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let point = convert(event.locationInWindow, from: nil)
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        let fullRect = layoutManager.boundingRect(forGlyphRange: fullGlyphRange, in: textContainer)
        let docHeight = max(fullRect.height, 1)
        let scale = bounds.height / docHeight

        let targetY = point.y / scale - scrollView.contentView.bounds.height / 2
        let clampedY = max(0, min(targetY, docHeight - scrollView.contentView.bounds.height))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - Overview Ruler (vertical marker strip alongside scrollbar)

final class OverviewRulerView: NSView {
    private weak var editorTextView: NSTextView?
    private weak var editorScrollView: NSScrollView?

    override var isFlipped: Bool { true }

    static let rulerWidth: CGFloat = 6

    /// Bookmarked lines for ruler markers (0-indexed)
    var bookmarkedLines: Set<Int> = []
    /// Current active line index (0-indexed)
    var currentLineIndex: Int = 0
    /// Total line count in document
    var totalLineCount: Int = 1

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.editorTextView = textView
        self.editorScrollView = scrollView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Background
        let bg: NSColor
        if let editorBg = editorTextView?.backgroundColor {
            bg = editorBg.blended(withFraction: 0.08, of: .gray) ?? editorBg
        } else {
            bg = .controlBackgroundColor
        }
        bg.set()
        bounds.fill()

        // Left separator
        NSColor.separatorColor.withAlphaComponent(0.2).set()
        NSRect(x: 0, y: 0, width: 0.5, height: bounds.height).fill()

        guard totalLineCount > 0 else { return }

        let lineCount = CGFloat(max(totalLineCount, 1))

        // Draw bookmark markers (blue)
        NSColor.systemBlue.withAlphaComponent(0.9).setFill()
        for line in bookmarkedLines {
            let y = (CGFloat(line) / lineCount) * bounds.height
            NSRect(x: 1, y: y, width: bounds.width - 2, height: max(2, bounds.height / lineCount)).fill()
        }

        // Draw current position marker (white/light)
        let cursorY = (CGFloat(currentLineIndex) / lineCount) * bounds.height
        NSColor.white.withAlphaComponent(0.7).setFill()
        NSRect(x: 0, y: cursorY - 1, width: bounds.width, height: 2).fill()
    }

    // Click to scroll editor to proportional position
    override func mouseDown(with event: NSEvent) {
        scrollToClick(event)
    }

    override func mouseDragged(with event: NSEvent) {
        scrollToClick(event)
    }

    private func scrollToClick(_ event: NSEvent) {
        guard let textView = editorTextView,
              let scrollView = editorScrollView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let point = convert(event.locationInWindow, from: nil)
        let fraction = max(0, min(point.y / bounds.height, 1))

        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        let fullRect = layoutManager.boundingRect(forGlyphRange: fullGlyphRange, in: textContainer)
        let docHeight = max(fullRect.height, 1)

        let targetY = fraction * docHeight - scrollView.contentView.bounds.height / 2
        let clampedY = max(0, min(targetY, docHeight - scrollView.contentView.bounds.height))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

// MARK: - Wrapper view: gutter + scroll view + minimap + overview ruler (frame-based layout)

final class EditorWrapperView: NSView {
    let gutterView: LineNumberGutterView
    let scrollView: BoBoScrollView
    var minimapView: MinimapView?
    var overviewRulerView: OverviewRulerView?

    var isGutterVisible: Bool = true {
        didSet {
            if oldValue != isGutterVisible {
                gutterView.isHidden = !isGutterVisible
                layoutSubviews()
            }
        }
    }

    var isMinimapVisible: Bool = false {
        didSet {
            if oldValue != isMinimapVisible {
                minimapView?.isHidden = !isMinimapVisible
                layoutSubviews()
            }
        }
    }

    var isOverviewRulerVisible: Bool = true {
        didSet {
            if oldValue != isOverviewRulerVisible {
                overviewRulerView?.isHidden = !isOverviewRulerVisible
                layoutSubviews()
            }
        }
    }

    init(gutterView: LineNumberGutterView, scrollView: BoBoScrollView) {
        self.gutterView = gutterView
        self.scrollView = scrollView
        super.init(frame: .zero)

        // Disable AppKit's default auto-resizing — we manage all subview frames
        // manually in layoutSubviews(). Without this, resizeSubviews(withOldSize:)
        // can resize subviews based on autoresizingMask, causing the gutter to
        // overlap the editor (the "overlay/blanking" bug on macOS Tahoe).
        autoresizesSubviews = false
        gutterView.autoresizingMask = []
        scrollView.autoresizingMask = []

        addSubview(scrollView)
        addSubview(gutterView)  // gutter on top for z-order
    }

    required init?(coder: NSCoder) { fatalError() }

    func installMinimap(_ minimap: MinimapView) {
        self.minimapView = minimap
        minimap.autoresizingMask = []
        addSubview(minimap)
        minimap.isHidden = !isMinimapVisible
    }

    func installOverviewRuler(_ ruler: OverviewRulerView) {
        self.overviewRulerView = ruler
        ruler.autoresizingMask = []
        addSubview(ruler)
        ruler.isHidden = !isOverviewRulerVisible
    }

    // Use AppKit's standard layout() entry point so the system drives layout
    // through the proper channel — not just frame.didSet which can race with
    // resizeSubviews(withOldSize:) on macOS Tahoe.
    override func layout() {
        super.layout()
        layoutSubviews()
    }

    // Belt-and-suspenders: also catch direct frame assignments from SwiftUI.
    override var frame: NSRect {
        didSet {
            if oldValue.size != frame.size {
                layoutSubviews()
            }
        }
    }

    // Prevent AppKit's default auto-resize from interfering with our layout.
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        layoutSubviews()
    }

    func layoutSubviews() {
        let rawGutterW: CGFloat = isGutterVisible ? gutterView.gutterWidth : 0
        // Safety cap — typical gutter is ~56-72pt; 120 is generous upper bound.
        let gutterW = max(0, min(rawGutterW, 120))

        let minimapW: CGFloat = isMinimapVisible ? MinimapView.minimapWidth : 0
        let rulerW: CGFloat = isOverviewRulerVisible ? OverviewRulerView.rulerWidth : 0
        let b = bounds

        let available = max(0, b.width - gutterW - minimapW - rulerW)
        let editorW = max(120, available)

        gutterView.frame = NSRect(x: 0, y: 0, width: gutterW, height: b.height)
        scrollView.frame = NSRect(x: gutterW, y: 0, width: editorW, height: b.height)
        minimapView?.frame = NSRect(x: gutterW + editorW, y: 0, width: minimapW, height: b.height)
        overviewRulerView?.frame = NSRect(x: gutterW + editorW + minimapW, y: 0, width: rulerW, height: b.height)
    }
}

// MARK: - Custom NSTextView subclass

final class BoBoTextView: NSTextView {
    var customUndoManager: UndoManager?
    var highlightedLineRect: NSRect?
    var highlightColor: NSColor = NSColor.black.withAlphaComponent(0.04)
    var foldRegionHighlightRect: NSRect?
    var tabHandler: (() -> Void)?
    weak var settingsRef: AppSettings?
    var showInvisibles: Bool = false

    /// Called when the editor regains focus — used to re-apply syntax colors
    /// that may have been corrupted by find indicator or system layout passes.
    var onBecomeFirstResponder: (() -> Void)?
    /// Called after native find bar actions — used to re-apply syntax colors.
    var onFindPanelAction: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onBecomeFirstResponder?() }
        return result
    }

    override func performFindPanelAction(_ sender: Any?) {
        super.performFindPanelAction(sender)
        onFindPanelAction?()
    }

    // MARK: - Multi-Cursor Support

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option) && !event.modifierFlags.contains(.shift) {
            // Option+Click: add cursor at clicked position
            let point = convert(event.locationInWindow, from: nil)
            let clickedIndex = characterIndexForInsertion(at: point)
            var ranges = selectedRanges.map { $0.rangeValue }
            let newRange = NSRange(location: clickedIndex, length: 0)
            // Don't add duplicate
            if !ranges.contains(newRange) {
                ranges.append(newRange)
                ranges.sort { $0.location < $1.location }
                setSelectedRanges(ranges.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
            }
            return
        }
        super.mouseDown(with: event)
    }

    func selectNextOccurrence() {
        let str = string as NSString
        guard str.length > 0 else { return }

        // Get the word under cursor or current selection
        let sel = selectedRange()
        var searchWord: String
        if sel.length > 0 {
            searchWord = str.substring(with: sel)
        } else {
            // Select the word at cursor
            let wordRange = selectionRange(forProposedRange: sel, granularity: .selectByWord)
            if wordRange.length > 0 {
                searchWord = str.substring(with: wordRange)
                // First Cmd+D: select the word
                setSelectedRange(wordRange)
                return
            }
            return
        }

        // Find next occurrence after the last selected range
        let allRanges = selectedRanges.map { $0.rangeValue }
        let lastRange = allRanges.last ?? sel
        let searchStart = NSMaxRange(lastRange)

        // Search forward from last selection, wrapping around
        var foundRange: NSRange?
        if searchStart < str.length {
            let searchRange = NSRange(location: searchStart, length: str.length - searchStart)
            let range = str.range(of: searchWord, options: [], range: searchRange)
            if range.location != NSNotFound {
                foundRange = range
            }
        }
        // Wrap around
        if foundRange == nil {
            let range = str.range(of: searchWord, options: [], range: NSRange(location: 0, length: searchStart))
            if range.location != NSNotFound && !allRanges.contains(range) {
                foundRange = range
            }
        }

        if let newRange = foundRange {
            var ranges = allRanges
            if !ranges.contains(newRange) {
                ranges.append(newRange)
                ranges.sort { $0.location < $1.location }
                setSelectedRanges(ranges.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
                scrollRangeToVisible(newRange)
            }
        }
    }

    private static let bracketPairs: [(String, String)] = [("(", ")"), ("{", "}"), ("[", "]")]
    private static let quotePairs: [(String, String)] = [("\"", "\""), ("'", "'"), ("`", "`")]
    private static let allPairs: [(String, String)] = bracketPairs + quotePairs

    override var undoManager: UndoManager? {
        return customUndoManager ?? super.undoManager
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        guard let settings = settingsRef, settings.autoCloseBrackets else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        let text = (insertString as? String) ?? String(describing: insertString)
        let str = string as NSString
        let sel = selectedRange()

        // Check if this is a closing bracket/quote and next char is the same — overtype
        for (_, close) in Self.allPairs {
            if text == close && sel.location < str.length {
                let nextChar = str.substring(with: NSRange(location: sel.location, length: 1))
                if nextChar == close {
                    // Just move cursor forward (overtype)
                    setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                    return
                }
            }
        }

        // If text is selected and user types an opening bracket, wrap selection
        if sel.length > 0 {
            for (open, close) in Self.allPairs {
                if text == open {
                    let selectedText = str.substring(with: sel)
                    let wrapped = open + selectedText + close
                    if shouldChangeText(in: sel, replacementString: wrapped) {
                        let attrStr = NSAttributedString(string: wrapped, attributes: typingAttributes)
                        textStorage?.replaceCharacters(in: sel, with: attrStr)
                        didChangeText()
                        // Select the inner text
                        setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
                    }
                    return
                }
            }
        }

        // Auto-close: insert pair and place cursor between
        for (open, close) in Self.bracketPairs {
            if text == open {
                let pair = open + close
                if shouldChangeText(in: sel, replacementString: pair) {
                    let attrStr = NSAttributedString(string: pair, attributes: typingAttributes)
                    textStorage?.replaceCharacters(in: sel, with: attrStr)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                }
                return
            }
        }

        // Auto-close quotes (only if not inside a word)
        for (open, close) in Self.quotePairs {
            if text == open {
                // Don't auto-close if previous char is alphanumeric (likely an apostrophe in English)
                if sel.location > 0 {
                    let prevChar = str.substring(with: NSRange(location: sel.location - 1, length: 1))
                    if prevChar.rangeOfCharacter(from: .alphanumerics) != nil && open == "'" {
                        super.insertText(insertString, replacementRange: replacementRange)
                        return
                    }
                }
                let pair = open + close
                if shouldChangeText(in: sel, replacementString: pair) {
                    let attrStr = NSAttributedString(string: pair, attributes: typingAttributes)
                    textStorage?.replaceCharacters(in: sel, with: attrStr)
                    didChangeText()
                    setSelectedRange(NSRange(location: sel.location + 1, length: 0))
                }
                return
            }
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if let settings = settingsRef, settings.autoCloseBrackets {
            let str = string as NSString
            let sel = selectedRange()
            // If cursor is between a pair, delete both
            if sel.length == 0 && sel.location > 0 && sel.location < str.length {
                let prevChar = str.substring(with: NSRange(location: sel.location - 1, length: 1))
                let nextChar = str.substring(with: NSRange(location: sel.location, length: 1))
                for (open, close) in Self.allPairs {
                    if prevChar == open && nextChar == close {
                        let deleteRange = NSRange(location: sel.location - 1, length: 2)
                        if shouldChangeText(in: deleteRange, replacementString: "") {
                            textStorage?.replaceCharacters(in: deleteRange, with: "")
                            didChangeText()
                            setSelectedRange(NSRange(location: sel.location - 1, length: 0))
                        }
                        return
                    }
                }
            }
        }
        super.deleteBackward(sender)
    }

    override func insertNewline(_ sender: Any?) {
        if let settings = settingsRef, settings.autoIndent {
            let str = string as NSString
            let cursorLoc = selectedRange().location
            let lineRange = str.lineRange(for: NSRange(location: cursorLoc, length: 0))
            let lineText = str.substring(with: lineRange)
            // Extract leading whitespace
            var leadingWhitespace = ""
            for ch in lineText {
                if ch == " " || ch == "\t" {
                    leadingWhitespace.append(ch)
                } else {
                    break
                }
            }
            super.insertNewline(sender)
            if !leadingWhitespace.isEmpty {
                insertText(leadingWhitespace, replacementRange: selectedRange())
            }
        } else {
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        let str = string as NSString
        // Multi-line indent: if selection spans multiple lines
        if sel.length > 0 {
            let selText = str.substring(with: sel)
            if selText.contains("\n") || selText.contains("\r") {
                indentSelectedLines()
                return
            }
        }
        if let handler = tabHandler {
            handler()
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        unindentSelectedLines()
    }

    private func indentSelectedLines() {
        let settings = settingsRef ?? AppSettings.shared
        let indent = settings.useSpacesForTabs ? String(repeating: " ", count: settings.tabWidth) : "\t"
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)
        let linesText = str.substring(with: lineRange)
        let lines = linesText.components(separatedBy: "\n")

        var result: [String] = []
        for (i, line) in lines.enumerated() {
            // Don't indent the trailing empty string after the last newline
            if i == lines.count - 1 && line.isEmpty {
                result.append(line)
            } else {
                result.append(indent + line)
            }
        }
        let newText = result.joined(separator: "\n")
        if shouldChangeText(in: lineRange, replacementString: newText) {
            let attrStr = NSAttributedString(string: newText, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: lineRange, with: attrStr)
            didChangeText()
            // Select the entire modified range
            setSelectedRange(NSRange(location: lineRange.location, length: (newText as NSString).length))
        }
    }

    private func unindentSelectedLines() {
        let settings = settingsRef ?? AppSettings.shared
        let tabW = settings.tabWidth
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)
        let linesText = str.substring(with: lineRange)
        let lines = linesText.components(separatedBy: "\n")

        var result: [String] = []
        for (i, line) in lines.enumerated() {
            if i == lines.count - 1 && line.isEmpty {
                result.append(line)
            } else {
                var removed = line
                if removed.hasPrefix("\t") {
                    removed = String(removed.dropFirst())
                } else {
                    // Remove up to tabWidth spaces
                    var count = 0
                    while count < tabW && removed.hasPrefix(" ") {
                        removed = String(removed.dropFirst())
                        count += 1
                    }
                }
                result.append(removed)
            }
        }
        let newText = result.joined(separator: "\n")
        if shouldChangeText(in: lineRange, replacementString: newText) {
            let attrStr = NSAttributedString(string: newText, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: lineRange, with: attrStr)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (newText as NSString).length))
        }
    }

    /// Strip rich formatting on paste — code editor should only have plain text with our colors
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let plainText = pb.string(forType: .string) {
            let settings = settingsRef ?? AppSettings.shared
            let attrs: [NSAttributedString.Key: Any] = [
                .font: settings.editorFont,
                .foregroundColor: settings.editorTextColor,
            ]
            let attrStr = NSAttributedString(string: plainText, attributes: attrs)
            let range = selectedRange()
            if shouldChangeText(in: range, replacementString: plainText) {
                textStorage?.replaceCharacters(in: range, with: attrStr)
                didChangeText()
                let newLoc = range.location + (plainText as NSString).length
                setSelectedRange(NSRange(location: newLoc, length: 0))
            }
        }
    }

    // MARK: - Zoom

    weak var zoomDelegate: AnyObject?  // Coordinator sets this
    var onZoomChanged: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            // Cmd+Scroll = Zoom
            let delta = event.scrollingDeltaY
            guard abs(delta) > 0.1 else { return }
            let settings = settingsRef ?? AppSettings.shared
            let currentSize = font?.pointSize ?? CGFloat(settings.fontSize)
            let newSize: CGFloat
            if delta > 0 {
                newSize = min(currentSize + 1, 72)
            } else {
                newSize = max(currentSize - 1, 8)
            }
            if newSize != currentSize {
                let newFont = NSFont(name: settings.fontName, size: newSize) ?? NSFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
                font = newFont
                settings.fontSize = Double(newSize)
            }
            return
        }
        super.scrollWheel(with: event)
    }

    // MARK: - Go to Matching Bracket

    func goToMatchingBracket() {
        let str = string as NSString
        guard str.length > 0 else { return }
        let cursorLoc = selectedRange().location
        let bracketPairsForMatch: [(Character, Character)] = [("(", ")"), ("{", "}"), ("[", "]")]
        let opens = bracketPairsForMatch.map { $0.0 }
        let closes = bracketPairsForMatch.map { $0.1 }

        for offset in [0, -1] {
            let checkLoc = cursorLoc + offset
            guard checkLoc >= 0, checkLoc < str.length else { continue }
            let code = str.character(at: checkLoc)
            guard let scalar = UnicodeScalar(code) else { continue }
            let ch = Character(scalar)

            if let idx = opens.firstIndex(of: ch) {
                let close = closes[idx]
                let open = opens[idx]
                var depth = 1
                var i = checkLoc + 1
                while i < str.length {
                    if let scalar = UnicodeScalar(str.character(at: i)) {
                        let c = Character(scalar)
                        if c == open { depth += 1 }
                        else if c == close { depth -= 1; if depth == 0 {
                            setSelectedRange(NSRange(location: i + 1, length: 0))
                            scrollRangeToVisible(NSRange(location: i, length: 1))
                            return
                        }}
                    }
                    i += 1
                }
                return
            } else if let idx = closes.firstIndex(of: ch) {
                let open = opens[idx]
                let close = closes[idx]
                var depth = 1
                var i = checkLoc - 1
                while i >= 0 {
                    if let scalar = UnicodeScalar(str.character(at: i)) {
                        let c = Character(scalar)
                        if c == close { depth += 1 }
                        else if c == open { depth -= 1; if depth == 0 {
                            setSelectedRange(NSRange(location: i, length: 0))
                            scrollRangeToVisible(NSRange(location: i, length: 1))
                            return
                        }}
                    }
                    i -= 1
                }
                return
            }
        }
    }

    // MARK: - Line Operations

    func duplicateLine() {
        let str = string as NSString
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)
        let lineText = str.substring(with: lineRange)
        // If line doesn't end with newline, add one before the duplicate
        let insertion = lineText.hasSuffix("\n") ? lineText : "\n" + lineText
        let insertLoc = NSMaxRange(lineRange)
        if shouldChangeText(in: NSRange(location: insertLoc, length: 0), replacementString: insertion) {
            let attrStr = NSAttributedString(string: insertion, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: NSRange(location: insertLoc, length: 0), with: attrStr)
            didChangeText()
            // Place cursor on the duplicated line at the same relative position
            let offset = sel.location - lineRange.location
            setSelectedRange(NSRange(location: insertLoc + offset, length: sel.length))
        }
    }

    func moveLineUp() {
        let str = string as NSString
        guard str.length > 0 else { return }
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)
        guard lineRange.location > 0 else { return } // Already at top

        let prevLineRange = str.lineRange(for: NSRange(location: lineRange.location - 1, length: 0))
        let currentText = str.substring(with: lineRange)
        let prevText = str.substring(with: prevLineRange)

        let combinedRange = NSRange(location: prevLineRange.location, length: lineRange.length + prevLineRange.length)
        // Ensure both end with newline properly
        var newText: String
        if currentText.hasSuffix("\n") {
            newText = currentText + prevText
            if !prevText.hasSuffix("\n") {
                // Last line of file: move newline from current to prev
                newText = String(currentText.dropLast()) + "\n" + prevText + "\n"
                // Remove trailing extra newline
                if newText.hasSuffix("\n\n") {
                    newText = String(newText.dropLast())
                }
            }
        } else {
            // Current line is last (no trailing newline)
            newText = currentText + "\n" + String(prevText.hasSuffix("\n") ? String(prevText.dropLast()) : prevText)
        }

        if shouldChangeText(in: combinedRange, replacementString: newText) {
            let attrStr = NSAttributedString(string: newText, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: combinedRange, with: attrStr)
            didChangeText()
            let offset = sel.location - lineRange.location
            setSelectedRange(NSRange(location: prevLineRange.location + offset, length: sel.length))
        }
    }

    func moveLineDown() {
        let str = string as NSString
        guard str.length > 0 else { return }
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)
        let lineEnd = NSMaxRange(lineRange)
        guard lineEnd < str.length else { return } // Already at bottom

        let nextLineRange = str.lineRange(for: NSRange(location: lineEnd, length: 0))
        let currentText = str.substring(with: lineRange)
        let nextText = str.substring(with: nextLineRange)

        let combinedRange = NSRange(location: lineRange.location, length: lineRange.length + nextLineRange.length)
        var newText: String
        if nextText.hasSuffix("\n") {
            newText = nextText + currentText
        } else {
            // Next line is last line (no trailing newline)
            newText = nextText + "\n" + (currentText.hasSuffix("\n") ? String(currentText.dropLast()) : currentText)
        }

        if shouldChangeText(in: combinedRange, replacementString: newText) {
            let attrStr = NSAttributedString(string: newText, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: combinedRange, with: attrStr)
            didChangeText()
            let offset = sel.location - lineRange.location
            let newLoc = lineRange.location + nextLineRange.length + offset
            setSelectedRange(NSRange(location: newLoc, length: sel.length))
        }
    }

    func deleteLine() {
        let str = string as NSString
        guard str.length > 0 else { return }
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)
        if shouldChangeText(in: lineRange, replacementString: "") {
            textStorage?.replaceCharacters(in: lineRange, with: "")
            didChangeText()
            let newLoc = min(lineRange.location, max(0, (string as NSString).length - 1))
            setSelectedRange(NSRange(location: max(0, newLoc), length: 0))
        }
    }

    func joinLines() {
        let str = string as NSString
        guard str.length > 0 else { return }
        let sel = selectedRange()
        let lineRange = str.lineRange(for: sel)
        let lineEnd = NSMaxRange(lineRange)
        // Find the newline at the end of the current line and replace with space
        let lineText = str.substring(with: lineRange)
        if lineText.hasSuffix("\n") && lineEnd <= str.length {
            let newlineRange = NSRange(location: lineEnd - 1, length: 1)
            if shouldChangeText(in: newlineRange, replacementString: " ") {
                textStorage?.replaceCharacters(in: newlineRange, with: NSAttributedString(string: " ", attributes: typingAttributes))
                didChangeText()
            }
        }
    }

    // MARK: - Convert Case

    func convertToUppercase() {
        replaceSelectedText { $0.uppercased() }
    }

    func convertToLowercase() {
        replaceSelectedText { $0.lowercased() }
    }

    func convertToTitleCase() {
        replaceSelectedText { $0.capitalized }
    }

    private func replaceSelectedText(_ transform: (String) -> String) {
        let sel = selectedRange()
        guard sel.length > 0 else { return }
        let str = string as NSString
        let original = str.substring(with: sel)
        let transformed = transform(original)
        if transformed != original, shouldChangeText(in: sel, replacementString: transformed) {
            let attrStr = NSAttributedString(string: transformed, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: sel, with: attrStr)
            didChangeText()
            setSelectedRange(NSRange(location: sel.location, length: (transformed as NSString).length))
        }
    }

    // MARK: - Sort Lines

    func sortLines(ascending: Bool) {
        let sel = selectedRange()
        let str = string as NSString
        let lineRange = sel.length > 0 ? str.lineRange(for: sel) : NSRange(location: 0, length: str.length)
        let text = str.substring(with: lineRange)
        var lines = text.components(separatedBy: "\n")
        let hadTrailingNewline = lines.last?.isEmpty == true
        if hadTrailingNewline { lines.removeLast() }

        lines.sort { ascending ? $0.localizedCaseInsensitiveCompare($1) == .orderedAscending : $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }

        if hadTrailingNewline { lines.append("") }
        let sorted = lines.joined(separator: "\n")
        if sorted != text, shouldChangeText(in: lineRange, replacementString: sorted) {
            let attrStr = NSAttributedString(string: sorted, attributes: typingAttributes)
            textStorage?.replaceCharacters(in: lineRange, with: attrStr)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: (sorted as NSString).length))
        }
    }

    // MARK: - Rich Text Formatting

    func toggleBold() {
        toggleFontTrait(.boldFontMask)
    }

    func toggleItalic() {
        toggleFontTrait(.italicFontMask)
    }

    func toggleUnderline() {
        let range = selectedRange()
        guard let textStorage = textStorage else { return }
        if range.length > 0 {
            // Toggle underline on selection
            let current = textStorage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
            let newVal = (current != 0) ? 0 : NSUnderlineStyle.single.rawValue
            textStorage.addAttribute(.underlineStyle, value: newVal, range: range)
            didChangeText()
        } else {
            // Toggle underline for typing attributes
            var attrs = typingAttributes
            let current = attrs[.underlineStyle] as? Int ?? 0
            attrs[.underlineStyle] = (current != 0) ? 0 : NSUnderlineStyle.single.rawValue
            typingAttributes = attrs
        }
    }

    func toggleStrikethrough() {
        let range = selectedRange()
        guard let textStorage = textStorage else { return }
        if range.length > 0 {
            let current = textStorage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
            let newVal = (current != 0) ? 0 : NSUnderlineStyle.single.rawValue
            textStorage.addAttribute(.strikethroughStyle, value: newVal, range: range)
            didChangeText()
        } else {
            var attrs = typingAttributes
            let current = attrs[.strikethroughStyle] as? Int ?? 0
            attrs[.strikethroughStyle] = (current != 0) ? 0 : NSUnderlineStyle.single.rawValue
            typingAttributes = attrs
        }
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        let fontManager = NSFontManager.shared
        if range.length > 0 {
            guard let textStorage = textStorage else { return }
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                guard let font = value as? NSFont else { return }
                let hasTrait = fontManager.traits(of: font).contains(trait)
                let newFont: NSFont
                if hasTrait {
                    newFont = fontManager.convert(font, toNotHaveTrait: trait)
                } else {
                    newFont = fontManager.convert(font, toHaveTrait: trait)
                }
                textStorage.addAttribute(.font, value: newFont, range: attrRange)
            }
            textStorage.endEditing()
            didChangeText()
        } else {
            // No selection — toggle for typing attributes (affects next typed text)
            var attrs = typingAttributes
            let currentFont = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 13)
            let hasTrait = fontManager.traits(of: currentFont).contains(trait)
            if hasTrait {
                attrs[.font] = fontManager.convert(currentFont, toNotHaveTrait: trait)
            } else {
                attrs[.font] = fontManager.convert(currentFont, toHaveTrait: trait)
            }
            typingAttributes = attrs
        }
    }

    // MARK: - Drag & Drop

    func setupDragAndDrop() {
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return super.performDragOperation(sender)
        }
        if !urls.isEmpty {
            for url in urls {
                NotificationCenter.default.post(name: .dragOpenFile, object: url)
            }
            return true
        }
        return super.performDragOperation(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let viewBounds = bounds

        // Fold region preview highlight — clamp to bounds and reject if suspiciously large
        // (> 80% of visible height means something went wrong with rect calculation)
        if let rect = foldRegionHighlightRect, dirtyRect.intersects(rect) {
            let clamped = rect.intersection(viewBounds)
            if !clamped.isEmpty && clamped.height < viewBounds.height * 0.8 {
                NSColor.systemBlue.withAlphaComponent(0.05).set()
                clamped.fill(using: .sourceOver)
            }
        }

        // Current line highlight overlay — must be a single line, reject if taller than 200pt
        if let rect = highlightedLineRect, dirtyRect.intersects(rect) {
            let clamped = rect.intersection(viewBounds)
            if !clamped.isEmpty && clamped.height < 200 {
                highlightColor.set()
                clamped.fill(using: .sourceOver)
            }
        }

        // Draw invisible characters (space → ·, tab → →, newline → ↵)
        if showInvisibles {
            drawInvisibles(in: dirtyRect)
        }
    }

    private func drawInvisibles(in dirtyRect: NSRect) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else { return }

        let str = string as NSString
        guard str.length > 0 else { return }

        // Only draw in visible range
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let invisibleColor = NSColor.tertiaryLabelColor
        let fontSize = font?.pointSize ?? 13
        let invisibleFont = NSFont.monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: invisibleFont,
            .foregroundColor: invisibleColor
        ]

        let containerOrigin = textContainerOrigin

        for i in visibleCharRange.location..<NSMaxRange(visibleCharRange) {
            guard i < str.length else { break }
            let ch = str.character(at: i)
            let symbol: String?

            switch ch {
            case 0x20:  // space
                symbol = "·"
            case 0x09:  // tab
                symbol = "→"
            case 0x0A:  // newline (LF)
                symbol = "↵"
            case 0x0D:  // carriage return (CR)
                symbol = "↵"
            default:
                symbol = nil
            }

            guard let sym = symbol else { continue }

            let glyphIndex = layoutManager.glyphIndexForCharacter(at: i)
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            let drawPoint = NSPoint(
                x: containerOrigin.x + lineFragmentRect.origin.x + location.x,
                y: containerOrigin.y + lineFragmentRect.origin.y
            )

            (sym as NSString).draw(at: drawPoint, withAttributes: attrs)
        }
    }

}
