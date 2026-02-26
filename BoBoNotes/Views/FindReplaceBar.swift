import SwiftUI
import AppKit

// MARK: - Find/Replace Window Controller (floating panel)

final class FindReplaceWindowController: NSWindowController {
    static let shared = FindReplaceWindowController()

    private var hostingView: NSHostingView<FindReplacePanel>?
    weak var searchStore: SearchResultsStore?
    weak var tabsStore: TabsStore?
    var onFindNext: (() -> Void)?
    var onFindPrevious: (() -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var isPinned: Bool = true

    func togglePin() {
        isPinned.toggle()
        (window as? NSPanel)?.hidesOnDeactivate = !isPinned
    }

    private init() {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1440
        let isCompact = screenWidth < 1200
        let panelWidth: CGFloat = isCompact ? 380 : 480

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 200),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Find & Replace"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: isCompact ? 340 : 400, height: 140)
        panel.maxSize = NSSize(width: isCompact ? 600 : 800, height: 400)

        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showFind(searchStore: SearchResultsStore, tabsStore: TabsStore,
                  onFindNext: @escaping () -> Void,
                  onFindPrevious: @escaping () -> Void,
                  onReplace: @escaping () -> Void,
                  onReplaceAll: @escaping () -> Void) {
        self.searchStore = searchStore
        self.tabsStore = tabsStore
        self.onFindNext = onFindNext
        self.onFindPrevious = onFindPrevious
        self.onReplace = onReplace
        self.onReplaceAll = onReplaceAll

        let panel = FindReplacePanel(
            searchStore: searchStore,
            tabsStore: tabsStore,
            isPinned: isPinned,
            onFindNext: onFindNext,
            onFindPrevious: onFindPrevious,
            onReplace: onReplace,
            onReplaceAll: onReplaceAll,
            onClose: { [weak self] in self?.window?.orderOut(nil) },
            onTogglePin: { [weak self] in self?.togglePin() }
        )

        let hostingView = NSHostingView(rootView: panel)
        window?.contentView = hostingView
        self.hostingView = hostingView

        if window?.isVisible != true {
            // Position near center-top of main window
            if let mainWindow = NSApp.mainWindow {
                let mainFrame = mainWindow.frame
                let x = mainFrame.midX - 240
                let y = mainFrame.maxY - 300
                window?.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        showWindow(nil)
        // Temporarily allow panel to become key so the search field can receive focus
        (window as? NSPanel)?.becomesKeyOnlyIfNeeded = false
        window?.makeKeyAndOrderFront(nil)
        // Restore non-activating behavior after focus is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            (self?.window as? NSPanel)?.becomesKeyOnlyIfNeeded = true
        }
    }
}

// MARK: - Find/Replace Panel View (SwiftUI content inside the NSPanel)

struct FindReplacePanel: View {
    @ObservedObject var searchStore: SearchResultsStore
    @ObservedObject var tabsStore: TabsStore

    var isPinned: Bool
    var onFindNext: () -> Void
    var onFindPrevious: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    var onClose: () -> Void
    var onTogglePin: () -> Void

    @State private var showReplace = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top bar with pin button
            HStack {
                Text("Find:")
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button(action: onTogglePin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin.slash")
                        .font(.system(size: 11))
                        .foregroundColor(isPinned ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin panel (closes when app deactivates)" : "Pin panel (always visible)")
            }

            // Find Section
            VStack(alignment: .leading, spacing: 6) {

                HStack(spacing: 6) {
                    TextField("Search text...", text: $searchStore.query.searchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .focused($isSearchFieldFocused)
                        .onSubmit { onFindNext() }

                    Button("Find Next") { onFindNext() }
                        .keyboardShortcut(.return, modifiers: [])

                    Button("Find Prev") { onFindPrevious() }
                }

                // Options
                HStack(spacing: 12) {
                    Toggle("Match Case", isOn: $searchStore.query.matchCase)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))

                    Toggle("Whole Word", isOn: $searchStore.query.wholeWord)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))

                    Toggle("Regex", isOn: $searchStore.query.useRegex)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))

                    Toggle("Wrap", isOn: $searchStore.query.wrapAround)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }
            }

            Divider()

            // Replace Section
            DisclosureGroup(isExpanded: $showReplace) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        TextField("Replace with...", text: $searchStore.query.replaceText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))

                        Button("Replace") { onReplace() }

                        Button("Replace All") { onReplaceAll() }
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Replace")
                    .font(.system(size: 12, weight: .medium))
            }

            Divider()

            // Find All Section
            HStack(spacing: 8) {
                Button("Find All in Document") {
                    if let doc = tabsStore.activeTab?.document {
                        searchStore.findAllInDocument(doc)
                    }
                }
                .font(.system(size: 11))

                Button("Find All in Open Docs") {
                    let docs = tabsStore.tabs.map(\.document)
                    searchStore.findAllInOpenDocuments(docs)
                }
                .font(.system(size: 11))

                Button("Find in Folder...") {
                    selectFolderAndSearch()
                }
                .font(.system(size: 11))

                Spacer()
            }

            // Status
            if !searchStore.statusMessage.isEmpty || !searchStore.results.isEmpty {
                HStack(spacing: 6) {
                    if searchStore.isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(searchStore.statusMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if !searchStore.results.isEmpty {
                        let totalMatches = searchStore.results.reduce(0) { $0 + $1.matchCount }
                        Text("\(totalMatches) matches")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 400)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
    }

    private func selectFolderAndSearch() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to search in"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        searchStore.findInFolder(at: url)
    }
}

// MARK: - Toggle Chip (kept for backward compat)

struct ToggleChip: View {
    let label: String
    @Binding var isOn: Bool
    let tooltip: String

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(label)
                .font(.system(size: 10, weight: isOn ? .bold : .regular, design: .monospaced))
                .foregroundColor(isOn ? .accentColor : .secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isOn ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isOn ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
