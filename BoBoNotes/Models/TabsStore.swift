import Foundation
import Combine
import AppKit

/// Manages the collection of open tabs and the active tab.
@MainActor
final class TabsStore: ObservableObject {
    @Published var tabs: [EditorTab] = []
    @Published var activeTabID: UUID?

    /// Combine is used here (rather than async/await) because @Published property
    /// observation requires Combine's sink. This is the idiomatic pattern for
    /// forwarding child ObservableObject changes to a parent ObservableObject.
    private var cancellables = Set<AnyCancellable>()
    private var untitledCounter = 0

    var activeTab: EditorTab? {
        guard let id = activeTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    init() {
        // Try to restore previous session
        if AppSettings.shared.restoreSessionOnLaunch {
            let session = SessionManager.shared.restoreSession()
            if !session.tabs.isEmpty {
                for restored in session.tabs {
                    let tab = EditorTab(document: restored.document)
                    tabs.append(tab)
                    observeDocument(tab)
                }
                let safeIndex = min(session.activeIndex, tabs.count - 1)
                activeTabID = tabs[max(0, safeIndex)].id
                // Set untitledCounter based on existing unsaved tabs
                untitledCounter = tabs.filter { $0.document.fileURL == nil }.count
                return
            }
        }
        // Fallback: start with one untitled tab
        if !AppSettings.shared.hasShownWelcomeNote {
            let tab = newWelcomeTab()
            AppSettings.shared.hasShownWelcomeNote = true
            tabs.append(tab)
            activeTabID = tab.id
            observeDocument(tab)
            saveSession()
        } else {
            newTab()
        }
    }

    func saveSession() {
        let activeIndex = tabs.firstIndex(where: { $0.id == activeTabID }) ?? 0
        SessionManager.shared.saveSession(tabs: tabs, activeIndex: activeIndex)
    }

    // MARK: - Welcome / Help Content

    /// Shared help content used by both first-run welcome and Help menu
    static let helpNoteContent = """
    # Welcome to BoBoNotes! 🎉

    BoBoNotes is a fast and lightweight text editor for macOS.

    ## Who is Bobo?

    Bobo is a tiny toy poodle — always sniffing every corner and peeking
    behind every drawer. BoBoNotes' search and discovery features are
    inspired by his endless curiosity. 🐩

    ---

    ## Key Features

    • Tabs — Open multiple files at once (⌘T: New Tab)
    • Syntax Highlighting — 26+ language support (Swift, Python, JS, etc.)
    • Find & Replace — Quick search with ⌘F, including regex support
    • Themes — Dark and Light theme (Settings → Theme)
    • Line Numbers — Absolute, relative, and interval modes
    • Auto-Save — Your session is preserved on exit and restored on launch

    ## Minimap

    See a miniaturized preview of your document on the right edge of the editor.
    Minimap lets you navigate large files quickly — click to jump to any section.
    Toggle it via View → Document Map.

    ## Workspace

    Open a folder from the side panel to browse all your files.
    Use ⌘⇧K to open quickly, or go to File → Open Folder as Workspace.
    Click files in the folder tree to open them directly in the editor.

    ## Function List

    View → Function List (⌘⇧L) to list all functions, methods, and class
    definitions in the current file. Click a symbol to jump to that line.

    ## Search Results

    Use ⌘⇧S to search across your workspace. Results are grouped by file
    in the bottom panel; click a result to open the file and highlight the
    matching line — explore every corner with Bobo's curiosity!

    ## Compare Notes

    Use ⌘⌥D to compare two open notes side by side.
    Differences are color-coded (green: added, red: removed).

    ## Split View

    Use ⌘\\ to split the editor in two. View two files simultaneously,
    and choose which note to display from the dropdown in the right panel.
    Click the ✕ button in the right panel to close it.

    ## File Extension Icons

    Files in the Workspace panel are shown with colorful icons based on their extension:
    • .swift → Swift icon (orange)
    • .py → Python (blue)
    • .js/.jsx → JavaScript (yellow) | .ts/.tsx → TypeScript (cyan)
    • .html → Web (red) | .css → Style (blue)
    • .json → JSON (green) | .md/.txt → Plain text
    • .sh/.bash/.zsh → Terminal | .sql → Database (purple)
    • Other extensions use a generic file icon.

    ## Useful Shortcuts

    ⌘N    New file                ⌘T    New tab
    ⌘O    Open file               ⌘W    Close tab
    ⌘S    Save                    ⌘⇧S   Save As
    ⌘F    Find                    ⌘⇧K   Open workspace
    ⌘\\    Split view              ⌘⌥D   Compare notes
    ⌘+/-  Change font size

    ## Next Steps

    Feel free to edit this note or create a new file with ⌘N.
    Happy writing! 🐾
    """

    private func newWelcomeTab() -> EditorTab {
        let doc = EditorDocument(title: "Welcome", content: Self.helpNoteContent)
        doc.languageID = "markdown"
        return EditorTab(document: doc)
    }

    // MARK: - Tab Management

    @discardableResult
    func newTab() -> EditorTab {
        untitledCounter += 1
        let title = untitledCounter == 1 ? "BoBo" : "BoBo \(untitledCounter)"
        let doc = EditorDocument(title: title)
        let tab = EditorTab(document: doc)
        tabs.append(tab)
        activeTabID = tab.id
        observeDocument(tab)
        saveSession()
        return tab
    }

    @discardableResult
    func openFile(url: URL, encoding: String.Encoding = .utf8) -> EditorTab? {
        // Check if already open
        if let existing = tabs.first(where: { $0.document.fileURL == url }) {
            activeTabID = existing.id
            return existing
        }

        do {
            let doc = try EditorDocument.load(from: url, encoding: encoding)
            let tab = EditorTab(document: doc)

            // If the only tab is an empty untitled, replace it
            if tabs.count == 1, let first = tabs.first,
               first.document.fileURL == nil, !first.document.isDirty, first.document.content.isEmpty {
                tabs[0] = tab
            } else {
                tabs.append(tab)
            }

            activeTabID = tab.id
            observeDocument(tab)
            RecentFilesManager.shared.addFile(url: url)
            saveSession()
            return tab
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to open file"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return nil
        }
    }

    func closeTab(_ tab: EditorTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        if tab.document.isDirty {
            let alert = NSAlert()
            alert.messageText = "Do you want to save changes to \"\(tab.document.title)\"?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                do {
                    if tab.document.fileURL != nil {
                        try tab.document.save()
                    } else {
                        guard saveAs(tab: tab) else { return }
                    }
                } catch {
                    return
                }
            case .alertSecondButtonReturn:
                break // Don't save, just close
            default:
                return // Cancel
            }
        }

        tabs.remove(at: index)

        if tabs.isEmpty {
            newTab()
        } else if activeTabID == tab.id {
            let newIndex = min(index, tabs.count - 1)
            activeTabID = tabs[newIndex].id
        }
        saveSession()
    }

    func selectTab(_ tab: EditorTab) {
        activeTabID = tab.id
        saveSession()
    }

    func closeOtherTabs(except tab: EditorTab) {
        let others = tabs.filter { $0.id != tab.id }
        for other in others {
            closeTab(other)
        }
        activeTabID = tab.id
        if tabs.isEmpty { newTab() }
        saveSession()
    }

    func closeAllTabs() {
        // Close each tab individually so dirty tabs get a save dialog
        let tabsCopy = tabs
        for tab in tabsCopy {
            closeTab(tab)
        }
        if tabs.isEmpty { newTab() }
    }

    func closeTabsToRight(of tab: EditorTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        // Close each tab individually so dirty tabs get a save dialog
        let rightTabs = Array(tabs.suffix(from: index + 1))
        for t in rightTabs {
            closeTab(t)
        }
        if !tabs.contains(where: { $0.id == activeTabID }) {
            activeTabID = tabs.last?.id
        }
        saveSession()
    }

    // MARK: - File Operations

    func saveAllDocuments() {
        var errors: [String] = []
        for tab in tabs {
            if tab.document.isDirty, tab.document.fileURL != nil {
                do {
                    try tab.document.save()
                } catch {
                    errors.append("\(tab.document.title): \(error.localizedDescription)")
                }
            }
        }
        if !errors.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some files could not be saved"
            alert.informativeText = errors.joined(separator: "\n")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func saveActiveDocument() {
        guard let tab = activeTab else { return }
        // Trim trailing whitespace on save if enabled
        if AppSettings.shared.trimTrailingWhitespaceOnSave {
            NotificationCenter.default.post(name: .trimTrailingWhitespace, object: nil)
        }
        if tab.document.fileURL != nil {
            do {
                try tab.document.save()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Failed to save file"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        } else {
            saveAs(tab: tab)
        }
    }

    @discardableResult
    func saveAs(tab: EditorTab? = nil) -> Bool {
        let targetTab = tab ?? activeTab
        guard let targetTab = targetTab else { return false }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = targetTab.document.title
        panel.allowedContentTypes = [.plainText, .sourceCode, .xml, .json, .yaml, .html, .script]

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try targetTab.document.save(to: url)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to save file"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    func openFileDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .sourceCode, .xml, .json, .yaml, .html, .data, .script]

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            openFile(url: url)
        }
    }

    // MARK: - Helpers

    private func observeDocument(_ tab: EditorTab) {
        tab.document.$isDirty
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
