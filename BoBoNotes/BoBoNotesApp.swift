import SwiftUI

@main
struct BoBoNotesApp: App {
    @StateObject private var store = TabsStore()
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var recentFiles = RecentFilesManager.shared

    init() {
        // Show tooltips immediately (default macOS delay ~1.5s is too slow)
        UserDefaults.standard.set(200, forKey: "NSInitialToolTipDelay")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 500, minHeight: 350)
                .onDisappear {
                    store.saveSession()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.saveSession()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            // MARK: - File Menu
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    store.newTab()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open...") {
                    store.openFileDialog()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Save") {
                    store.saveActiveDocument()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As...") {
                    store.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Menu("Recent Files") {
                    ForEach(recentFiles.recentFiles, id: \.absoluteString) { url in
                        Button(url.lastPathComponent) {
                            // Security scope stays open while the document is in use;
                            // it will be released when the tab is closed or the app terminates.
                            _ = url.startAccessingSecurityScopedResource()
                            store.openFile(url: url)
                        }
                    }
                    if !recentFiles.recentFiles.isEmpty {
                        Divider()
                        Button("Clear Recent Files") {
                            recentFiles.clearAll()
                        }
                    }
                }

                Divider()

                Button("Close Tab") {
                    if let tab = store.activeTab {
                        store.closeTab(tab)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            // MARK: - Edit Menu
            CommandGroup(after: .undoRedo) {
                Divider()

                Button("Go to Line...") {
                    showGoToLineDialog()
                }
                .keyboardShortcut("l", modifiers: .command)

                Divider()

                Button("Select Next Occurrence") {
                    NotificationCenter.default.post(name: .selectNextOccurrence, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Duplicate Line") {
                    NotificationCenter.default.post(name: .duplicateLine, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Delete Line") {
                    NotificationCenter.default.post(name: .deleteLine, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Move Line Up") {
                    NotificationCenter.default.post(name: .moveLineUp, object: nil)
                }
                .keyboardShortcut(.upArrow, modifiers: .option)

                Button("Move Line Down") {
                    NotificationCenter.default.post(name: .moveLineDown, object: nil)
                }
                .keyboardShortcut(.downArrow, modifiers: .option)

                Button("Join Lines") {
                    NotificationCenter.default.post(name: .joinLines, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)

                Divider()

                Button("Toggle Comment") {
                    NotificationCenter.default.post(name: .toggleComment, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)

                Button("Toggle Block Comment") {
                    NotificationCenter.default.post(name: .toggleBlockComment, object: nil)
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])

                Divider()

                Button("Trim Trailing Whitespace") {
                    NotificationCenter.default.post(name: .trimTrailingWhitespace, object: nil)
                }

                Divider()

                Button("Go to Matching Bracket") {
                    NotificationCenter.default.post(name: .goToMatchingBracket, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Menu("Convert Case") {
                    Button("UPPERCASE") {
                        NotificationCenter.default.post(name: .convertToUppercase, object: nil)
                    }
                    .keyboardShortcut("u", modifiers: [.command, .control])

                    Button("lowercase") {
                        NotificationCenter.default.post(name: .convertToLowercase, object: nil)
                    }
                    .keyboardShortcut("u", modifiers: [.command, .shift])

                    Button("Title Case") {
                        NotificationCenter.default.post(name: .convertToTitleCase, object: nil)
                    }
                }

                Menu("Sort Lines") {
                    Button("Sort Ascending") {
                        NotificationCenter.default.post(name: .sortLinesAscending, object: nil)
                    }
                    Button("Sort Descending") {
                        NotificationCenter.default.post(name: .sortLinesDescending, object: nil)
                    }
                }

                Divider()

                Menu("Bookmarks") {
                    Button("Toggle Bookmark") {
                        NotificationCenter.default.post(name: .toggleBookmark, object: nil)
                    }
                    .keyboardShortcut("b", modifiers: [.command, .option])

                    Button("Next Bookmark") {
                        NotificationCenter.default.post(name: .nextBookmark, object: nil)
                    }
                    .keyboardShortcut("n", modifiers: [.command, .option])

                    Button("Previous Bookmark") {
                        NotificationCenter.default.post(name: .previousBookmark, object: nil)
                    }
                    .keyboardShortcut("p", modifiers: [.command, .option])

                    Divider()

                    Button("Clear All Bookmarks") {
                        NotificationCenter.default.post(name: .clearBookmarks, object: nil)
                    }
                }
            }

            // MARK: - Format Menu
            CommandMenu("Format") {
                Button("Bold") {
                    NotificationCenter.default.post(name: .toggleBold, object: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    NotificationCenter.default.post(name: .toggleItalic, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Underline") {
                    NotificationCenter.default.post(name: .toggleUnderline, object: nil)
                }
                .keyboardShortcut("u", modifiers: .command)

                Button("Strikethrough") {
                    NotificationCenter.default.post(name: .toggleStrikethrough, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift, .option])
            }

            // MARK: - Find Menu
            CommandGroup(replacing: .textEditing) {
                Button("Find...") {
                    NotificationCenter.default.post(name: .showFindBar, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find and Replace...") {
                    NotificationCenter.default.post(name: .showFindReplaceBar, object: nil)
                }
                .keyboardShortcut("h", modifiers: .command)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .findNextCommand, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command])

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .findPreviousCommand, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Button("Find in Folder...") {
                    NotificationCenter.default.post(name: .showFindBar, object: nil)
                    // Will be handled by Find All menu in the bar
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Toggle Search Results") {
                    NotificationCenter.default.post(name: .toggleSearchResults, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Divider()

                Button("Close Find Bar") {
                    NotificationCenter.default.post(name: .hideFindBar, object: nil)
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            // MARK: - View Menu
            CommandGroup(replacing: .toolbar) {
                Toggle("Icon Toolbar", isOn: $settings.showToolbar)
                    .keyboardShortcut("t", modifiers: [.command, .option])

                Toggle("Word Wrap", isOn: $settings.useSoftWrap)
                    .keyboardShortcut("z", modifiers: [.command, .option])

                Toggle("Line Numbers", isOn: $settings.showLineNumbers)

                Toggle("Highlight Current Line", isOn: $settings.highlightCurrentLine)

                Toggle("Show Invisible Characters", isOn: $settings.showInvisibles)

                Toggle("Document Map", isOn: $settings.showMinimap)

                Toggle("Overview Ruler", isOn: $settings.showOverviewRuler)

                Toggle("Spell Checking", isOn: $settings.enableSpellChecker)

                Button("Function List") {
                    NotificationCenter.default.post(name: .toggleFunctionList, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Workspace Panel") {
                    NotificationCenter.default.post(name: .toggleWorkspacePanel, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Open Folder as Workspace...") {
                    NotificationCenter.default.post(name: .openFolderAsWorkspace, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Split View") {
                    NotificationCenter.default.post(name: .toggleSplitView, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Compare Notes...") {
                    NotificationCenter.default.post(name: .compareNotes, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Divider()

                Button("Increase Font Size") {
                    settings.fontSize = min(settings.fontSize + 1, 72)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    settings.fontSize = max(settings.fontSize - 1, 8)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Font Size") {
                    settings.fontSize = 13
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            // MARK: - Language Menu
            CommandMenu("Language") {
                ForEach(LanguageRegistry.shared.languages, id: \.id) { lang in
                    Button(lang.displayName) {
                        if let doc = store.activeTab?.document {
                            doc.languageID = lang.id
                            NotificationCenter.default.post(name: .languageDidChange, object: lang.id)
                        }
                    }
                }
            }

            // MARK: - Help Menu
            CommandGroup(replacing: .help) {
                Button("BoBoNotes Help Center") {
                    openHelpInApp()
                }

                Button("Keyboard Shortcuts") {
                    showKeyboardShortcuts()
                }
            }

            // MARK: - Navigation between tabs
            CommandGroup(after: .windowArrangement) {
                Button("Next Tab") {
                    navigateTab(forward: true)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Previous Tab") {
                    navigateTab(forward: false)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func navigateTab(forward: Bool) {
        guard let activeID = store.activeTabID,
              let currentIndex = store.tabs.firstIndex(where: { $0.id == activeID }) else { return }

        let newIndex: Int
        if forward {
            newIndex = (currentIndex + 1) % store.tabs.count
        } else {
            newIndex = (currentIndex - 1 + store.tabs.count) % store.tabs.count
        }
        store.selectTab(store.tabs[newIndex])
    }

    private func openHelpInApp() {
        let helpContent = TabsStore.helpNoteContent
        let doc = EditorDocument(title: "BoBoNotes Help", content: helpContent)
        doc.languageID = "markdown"
        let tab = EditorTab(document: doc)
        store.tabs.append(tab)
        store.selectTab(tab)
    }

    private func showKeyboardShortcuts() {
        let shortcuts = """
        BoBoNotes Keyboard Shortcuts
        ════════════════════════════

        File
          ⌘N  New          ⌘O  Open          ⌘S  Save
          ⇧⌘S  Save As     ⌘W  Close Tab

        Edit
          ⌘L  Go to Line   ⌘D  Select Next Occurrence
          ⇧⌘D  Duplicate   ⇧⌘K  Delete Line
          ⌥↑  Move Up      ⌥↓  Move Down
          ⌘J  Join Lines   ⌘/  Toggle Comment
          ⌘]  Matching Bracket

        Find
          ⌘F  Find         ⌘H  Find & Replace
          ⌘G  Find Next    ⇧⌘G  Find Previous
          ⇧⌘F  Find in Folder

        View
          ⌥⌘T  Toolbar     ⌥⌘Z  Word Wrap
          ⇧⌘L  Function List
          ⇧⌘E  Workspace   ⌘\\  Split View
          ⌘+  Zoom In      ⌘-  Zoom Out      ⌘0  Reset

        Navigation
          ⇧⌘]  Next Tab    ⇧⌘[  Previous Tab

        Bookmarks
          ⌥⌘B  Toggle      ⌥⌘N  Next         ⌥⌘P  Previous
        """
        let alert = NSAlert()
        alert.messageText = "Keyboard Shortcuts"
        alert.informativeText = shortcuts
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showGoToLineDialog() {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter line number:"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.placeholderString = "Line number"
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn,
              let lineNum = Int(textField.stringValue), lineNum > 0 else { return }

        NotificationCenter.default.post(name: .goToLine, object: lineNum)
    }
}

// goToLine notification is defined in ContentView.swift
