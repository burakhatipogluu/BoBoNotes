import SwiftUI

/// Main content view: tab bar + editor + search results + status bar + workspace panel
struct ContentView: View {
    @EnvironmentObject var store: TabsStore
    @ObservedObject var settings = AppSettings.shared
    @StateObject private var searchStore = SearchResultsStore()

    @State private var searchPanelHeight: CGFloat = 120
    // Split view
    @State private var isSplit: Bool = false
    @State private var secondaryTabID: UUID? = nil
    // Compare notes (diff) — inline side-by-side diff view
    @State private var isComparing: Bool = false
    @State private var diffResult: DiffResult? = nil
    @State private var diffLeftTitle: String = ""
    @State private var diffRightTitle: String = ""
    @State private var diffLeftContent: String = ""
    @State private var diffRightContent: String = ""
    // Function list
    @State private var functionListSymbols: [SymbolItem] = []

    var body: some View {
        GeometryReader { geo in
            let metrics = LayoutMetrics(windowWidth: geo.size.width)
            mainContent(metrics: metrics)
                .environment(\.layoutMetrics, metrics)
        }
    }

    private func mainContent(metrics: LayoutMetrics) -> some View {
        VStack(spacing: 0) {
            // Icon Toolbar
            if settings.showToolbar {
                EditorToolbarView()
                    .environmentObject(store)

                Divider()
            }

            // Tab bar
            TabBarView(store: store)

            Divider()

            // Main content area: workspace panel | editor (+ search/diff results)
            HSplitView {
                // Left: workspace panel
                if settings.showWorkspacePanel {
                    FolderWorkspaceView()
                        .environmentObject(store)
                        .frame(minWidth: metrics.workspaceMinWidth, idealWidth: metrics.workspaceIdealWidth, maxWidth: metrics.workspaceMaxWidth)
                }

                // Right: editor + bottom panels (search results / diff panel)
                HSplitView {
                    VStack(spacing: 0) {
                        if isComparing, let result = diffResult {
                            // Compare mode: inline side-by-side diff replaces editors
                            DiffView(
                                diffResult: result,
                                leftTitle: diffLeftTitle,
                                rightTitle: diffRightTitle,
                                leftContent: diffLeftContent,
                                rightContent: diffRightContent
                            ) {
                                closeCompareMode()
                            }
                        } else if searchStore.isPanelVisible {
                            GeometryReader { geo in
                                VSplitView {
                                    splitOrSingleEditor(metrics: metrics)
                                        .frame(minHeight: 100)

                                    SearchResultsPanel(searchStore: searchStore) { fileResult, match in
                                        jumpToMatch(fileResult: fileResult, match: match)
                                    }
                                    .frame(minHeight: 60, idealHeight: searchPanelHeight, maxHeight: geo.size.height * 0.3)
                                }
                            }
                        } else {
                            splitOrSingleEditor(metrics: metrics)
                        }
                    }
                    .frame(minWidth: metrics.editorMinWidth)
                    .layoutPriority(1)

                    if settings.showFunctionList {
                        FunctionListView(
                            symbols: functionListSymbols,
                            onSymbolTap: { lineNumber in
                                NotificationCenter.default.post(name: .goToLine, object: lineNumber)
                            }
                        )
                        .frame(minWidth: metrics.functionListMinWidth, idealWidth: metrics.functionListIdealWidth, maxWidth: metrics.functionListMaxWidth)
                    }
                }
            }

            // Status bar
            StatusBarView(store: store, settings: settings)
        }
        .background(Color(nsColor: settings.editorBackgroundColor))
        .preferredColorScheme(settings.appTheme == .dark ? .dark : .light)
        .onReceive(NotificationCenter.default.publisher(for: .showFindBar)) { _ in
            openFindWindow(withReplace: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFindReplaceBar)) { _ in
            openFindWindow(withReplace: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hideFindBar)) { _ in
            FindReplaceWindowController.shared.window?.orderOut(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSearchResults)) { _ in
            searchStore.togglePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findNextCommand)) { _ in
            findNext()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findPreviousCommand)) { _ in
            findPrevious()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dragOpenFile)) { notification in
            if let url = notification.object as? URL {
                store.openFile(url: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleWorkspacePanel)) { _ in
            settings.showWorkspacePanel.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSplitView)) { _ in
            isSplit.toggle()
            if isSplit && secondaryTabID == nil {
                let otherTab = store.tabs.first(where: { $0.id != store.activeTabID })
                secondaryTabID = otherTab?.id ?? store.activeTabID
            }
            if !isSplit {
                secondaryTabID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .compareNotes)) { _ in
            showCompareSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolderAsWorkspace)) { notification in
            if let url = notification.object as? URL {
                settings.workspaceURL = url
                settings.showWorkspacePanel = true
            } else {
                selectWorkspaceFolder()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFunctionList)) { _ in
            settings.showFunctionList.toggle()
            if settings.showFunctionList {
                updateFunctionList()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .textContentDidChange)) { _ in
            if settings.showFunctionList {
                updateFunctionList()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .languageDidChange)) { _ in
            if settings.showFunctionList {
                updateFunctionList()
            }
        }
        .onChange(of: store.activeTabID) { _ in
            if settings.showFunctionList {
                updateFunctionList()
            }
        }
        .onAppear {
            // Workspace restore handled by AppSettings bookmark persistence
            if settings.showFunctionList {
                updateFunctionList()
            }
        }
        .onDisappear {
            // Workspace cleanup handled by AppSettings bookmark
        }
    }

    @ViewBuilder
    private var editorView: some View {
        if let tab = store.activeTab {
            ZStack {
                EditorTextView(tab: tab, settings: settings)
                    .id(tab.id)

                // Watermark — centered BoBo poodle
                if tab.document.content.isEmpty && tab.document.fileURL == nil {
                    Image("BoBoPoodle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 256, height: 256)
                        .allowsHitTesting(false)
                }
            }
        } else {
            Image("BoBoPoodle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 256, height: 256)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: settings.editorBackgroundColor))
        }
    }

    /// Single editor or split (two editors side by side with title headers)
    @ViewBuilder
    private func splitOrSingleEditor(metrics: LayoutMetrics) -> some View {
        if isSplit {
            HSplitView {
                // Left pane (primary / active tab)
                VStack(spacing: 0) {
                    splitPaneHeader(
                        title: store.activeTab?.document.title ?? "Untitled",
                        isPrimary: true
                    )
                    Divider()
                    editorView
                }
                .frame(minWidth: metrics.splitPaneMinWidth, maxWidth: .infinity)
                .layoutPriority(1)

                // Right pane (secondary tab)
                VStack(spacing: 0) {
                    splitPaneHeader(
                        title: store.tabs.first(where: { $0.id == secondaryTabID })?.document.title ?? "Select Document",
                        isPrimary: false
                    )
                    Divider()
                    secondaryEditorView
                }
                .frame(minWidth: metrics.splitPaneMinWidth, maxWidth: .infinity)
            }
        } else {
            editorView
        }
    }

    /// Header bar for each split pane showing document title
    @ViewBuilder
    private func splitPaneHeader(title: String, isPrimary: Bool) -> some View {
        @Environment(\.layoutMetrics) var metrics
        return HStack(spacing: 6) {
            Image(systemName: isPrimary ? "doc.text" : "doc.text.fill")
                .font(.system(size: metrics.uiFontSizeSmall))
                .foregroundColor(.secondary)

            Text(title)
                .font(.system(size: metrics.uiFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)

            Spacer()

            if !isPrimary {
                Menu {
                    ForEach(store.tabs) { tab in
                        Button(tab.document.title) {
                            secondaryTabID = tab.id
                            // If comparing, recalculate diff
                            if isComparing, let activeTab = store.activeTab {
                                diffResult = DiffService.diff(
                                    left: activeTab.document.content,
                                    right: tab.document.content
                                )
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .font(.system(size: metrics.uiFontSizeSmall))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
                .help("Choose document")

                // Close split pane button
                Button(action: {
                    isSplit = false
                    secondaryTabID = nil
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close Split View")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: metrics.paneHeaderHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Secondary editor pane for split view
    @ViewBuilder
    private var secondaryEditorView: some View {
        if let secondaryID = secondaryTabID,
           let tab = store.tabs.first(where: { $0.id == secondaryID }) {
            ZStack {
                EditorTextView(tab: tab, settings: settings)
                    .id(tab.id)

                if tab.document.content.isEmpty && tab.document.fileURL == nil {
                    Image("BoBoPoodle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 128)
                        .allowsHitTesting(false)
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 32))
                    .foregroundColor(.secondary)
                Text("Select a document")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: settings.editorBackgroundColor))
        }
    }

    // MARK: - Find Window

    private func openFindWindow(withReplace: Bool) {
        FindReplaceWindowController.shared.showFind(
            searchStore: searchStore,
            tabsStore: store,
            onFindNext: { findNext() },
            onFindPrevious: { findPrevious() },
            onReplace: { replaceCurrent() },
            onReplaceAll: { replaceAll() }
        )
    }

    // MARK: - Search Actions

    private func findNext() {
        guard let tab = store.activeTab else { return }
        Task {
            let fromLocation = tab.selectedRange.location + tab.selectedRange.length
            if let match = await searchStore.findNext(in: tab.document, fromLocation: fromLocation) {
                NotificationCenter.default.post(name: .selectRange, object: match.range)
                searchStore.statusMessage = "Line \(match.lineNumber)"
            } else {
                searchStore.statusMessage = "No matches found"
            }
        }
    }

    private func findPrevious() {
        guard let tab = store.activeTab else { return }
        Task {
            let fromLocation = tab.selectedRange.location
            if let match = await searchStore.findPrevious(in: tab.document, fromLocation: fromLocation) {
                NotificationCenter.default.post(name: .selectRange, object: match.range)
                searchStore.statusMessage = "Line \(match.lineNumber)"
            } else {
                searchStore.statusMessage = "No matches found"
            }
        }
    }

    private func replaceCurrent() {
        guard let tab = store.activeTab else { return }
        let selectedRange = tab.selectedRange
        guard selectedRange.length > 0 else {
            findNext()
            return
        }

        let nsContent = tab.document.content as NSString
        let selectedText = nsContent.substring(with: selectedRange)

        if let regex = try? searchStore.query.buildRegex(),
           let match = regex.firstMatch(in: selectedText, range: NSRange(location: 0, length: (selectedText as NSString).length)) {
            if match.range.length == (selectedText as NSString).length {
                let replacement = searchStore.query.useRegex
                    ? regex.replacementString(for: match, in: selectedText, offset: 0, template: searchStore.query.replaceText)
                    : searchStore.query.replaceText

                let newContent = nsContent.replacingCharacters(in: selectedRange, with: replacement)
                tab.document.content = newContent
                tab.document.isDirty = true

                NotificationCenter.default.post(name: .textContentDidChange, object: newContent)
                findNext()
            }
        }
    }

    private func replaceAll() {
        guard let tab = store.activeTab else { return }
        let document = tab.document
        Task {
            let count = await searchStore.replaceAllInDocument(document)
            if count > 0 {
                NotificationCenter.default.post(name: .textContentDidChange, object: document.content)
            }
        }
    }

    // MARK: - Workspace

    private func selectWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the folder you want to open as a workspace. BoBoNotes will request permission to read files in this folder."
        panel.prompt = "Open as Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.workspaceURL = url
        settings.showWorkspacePanel = true
    }

    // MARK: - Compare Notes

    private func showCompareSheet() {
        guard store.tabs.count >= 2 else {
            let alert = NSAlert()
            alert.messageText = "Compare Notes"
            alert.informativeText = "At least 2 open documents are required for comparison."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        guard let activeTab = store.activeTab else { return }
        let otherTabs = store.tabs.filter { $0.id != activeTab.id }

        let alert = NSAlert()
        alert.messageText = "Compare Notes"
        alert.informativeText = "Compare \"\(activeTab.document.title)\" with:"
        alert.addButton(withTitle: "Compare")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        for tab in otherTabs {
            popup.addItem(withTitle: tab.document.title)
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let selectedIndex = popup.indexOfSelectedItem
        guard selectedIndex >= 0 && selectedIndex < otherTabs.count else { return }

        let selectedTab = otherTabs[selectedIndex]

        // Store titles and content for the DiffView
        diffLeftTitle = activeTab.document.title
        diffRightTitle = selectedTab.document.title
        diffLeftContent = activeTab.document.content
        diffRightContent = selectedTab.document.content
        diffResult = DiffService.diff(left: diffLeftContent, right: diffRightContent)
        isComparing = true
    }

    private func closeCompareMode() {
        isComparing = false
        diffResult = nil
        diffLeftTitle = ""
        diffRightTitle = ""
        diffLeftContent = ""
        diffRightContent = ""
    }

    // MARK: - Function List

    private func updateFunctionList() {
        guard let tab = store.activeTab else {
            functionListSymbols = []
            return
        }
        functionListSymbols = FunctionListService.shared.extractSymbols(
            from: tab.document.content,
            languageID: tab.document.languageID
        )
    }

    // MARK: - Jump to Match

    private func jumpToMatch(fileResult: FileSearchResult, match: SearchMatch) {
        if let url = fileResult.fileURL {
            if store.tabs.first(where: { $0.document.fileURL == url }) == nil {
                store.openFile(url: url)
            } else {
                if let tab = store.tabs.first(where: { $0.document.fileURL == url }) {
                    store.selectTab(tab)
                }
            }
        } else {
            if let tab = store.tabs.first(where: { $0.document.id == fileResult.documentID }) {
                store.selectTab(tab)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let targetTabID = self.store.activeTabID
            NotificationCenter.default.post(name: .selectRange, object: match.range, userInfo: targetTabID.map { ["tabID": $0] })
            NotificationCenter.default.post(name: .flashLine, object: match.lineNumber, userInfo: targetTabID.map { ["tabID": $0] })
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showFindBar = Notification.Name("BoBoNotes.showFindBar")
    static let showFindReplaceBar = Notification.Name("BoBoNotes.showFindReplaceBar")
    static let hideFindBar = Notification.Name("BoBoNotes.hideFindBar")
    static let toggleSearchResults = Notification.Name("BoBoNotes.toggleSearchResults")
    static let findNextCommand = Notification.Name("BoBoNotes.findNextCommand")
    static let findPreviousCommand = Notification.Name("BoBoNotes.findPreviousCommand")
    static let selectRange = Notification.Name("BoBoNotes.selectRange")
    static let textContentDidChange = Notification.Name("BoBoNotes.textContentDidChange")
    static let flashLine = Notification.Name("BoBoNotes.flashLine")
    static let languageDidChange = Notification.Name("BoBoNotes.languageDidChange")
    static let goToLine = Notification.Name("BoBoNotes.goToLine")
    static let toggleWorkspacePanel = Notification.Name("BoBoNotes.toggleWorkspacePanel")
    static let openFolderAsWorkspace = Notification.Name("BoBoNotes.openFolderAsWorkspace")
    // Line operations
    static let duplicateLine = Notification.Name("BoBoNotes.duplicateLine")
    static let moveLineUp = Notification.Name("BoBoNotes.moveLineUp")
    static let moveLineDown = Notification.Name("BoBoNotes.moveLineDown")
    static let deleteLine = Notification.Name("BoBoNotes.deleteLine")
    static let joinLines = Notification.Name("BoBoNotes.joinLines")
    // Comment toggle
    static let toggleComment = Notification.Name("BoBoNotes.toggleComment")
    static let toggleBlockComment = Notification.Name("BoBoNotes.toggleBlockComment")
    // Trim whitespace
    static let trimTrailingWhitespace = Notification.Name("BoBoNotes.trimTrailingWhitespace")
    // Multi-cursor
    static let selectNextOccurrence = Notification.Name("BoBoNotes.selectNextOccurrence")
    // Go to matching bracket
    static let goToMatchingBracket = Notification.Name("BoBoNotes.goToMatchingBracket")
    // Convert case
    static let convertToUppercase = Notification.Name("BoBoNotes.convertToUppercase")
    static let convertToLowercase = Notification.Name("BoBoNotes.convertToLowercase")
    static let convertToTitleCase = Notification.Name("BoBoNotes.convertToTitleCase")
    // Sort lines
    static let sortLinesAscending = Notification.Name("BoBoNotes.sortLinesAscending")
    static let sortLinesDescending = Notification.Name("BoBoNotes.sortLinesDescending")
    // Drag & drop
    static let dragOpenFile = Notification.Name("BoBoNotes.dragOpenFile")
    // Split view & Compare
    static let toggleSplitView = Notification.Name("BoBoNotes.toggleSplitView")
    static let compareNotes = Notification.Name("BoBoNotes.compareNotes")
    // Rich text formatting
    static let toggleBold = Notification.Name("BoBoNotes.toggleBold")
    static let toggleItalic = Notification.Name("BoBoNotes.toggleItalic")
    static let toggleUnderline = Notification.Name("BoBoNotes.toggleUnderline")
    static let toggleStrikethrough = Notification.Name("BoBoNotes.toggleStrikethrough")
    // Show invisibles
    static let toggleInvisibles = Notification.Name("BoBoNotes.toggleInvisibles")
    // Minimap
    static let toggleMinimap = Notification.Name("BoBoNotes.toggleMinimap")
    // Function List
    static let toggleFunctionList = Notification.Name("BoBoNotes.toggleFunctionList")
    // Bookmarks
    static let toggleBookmark = Notification.Name("BoBoNotes.toggleBookmark")
    static let nextBookmark = Notification.Name("BoBoNotes.nextBookmark")
    static let previousBookmark = Notification.Name("BoBoNotes.previousBookmark")
    static let clearBookmarks = Notification.Name("BoBoNotes.clearBookmarks")
}
