import SwiftUI
import AppKit

/// Icon toolbar with Apple SF Symbol icons.
/// Positioned below the tab bar, above the editor area.
struct EditorToolbarView: View {
    @EnvironmentObject var store: TabsStore
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - File Group
            toolbarButton(icon: "doc.badge.plus", tooltip: "New (⌘N)") {
                store.newTab()
            }
            toolbarButton(icon: "folder", tooltip: "Open (⌘O)") {
                store.openFileDialog()
            }
            toolbarButton(icon: "square.and.arrow.down", tooltip: "Save (⌘S)") {
                store.saveActiveDocument()
            }
            toolbarButton(icon: "square.and.arrow.down.on.square", tooltip: "Save All") {
                store.saveAllDocuments()
            }
            toolbarButton(icon: "xmark.square", tooltip: "Close Tab (⌘W)") {
                if let tab = store.activeTab {
                    store.closeTab(tab)
                }
            }

            groupDivider()

            // MARK: - Edit Group
            toolbarButton(icon: "arrow.uturn.backward", tooltip: "Undo (⌘Z)") {
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            }
            toolbarButton(icon: "arrow.uturn.forward", tooltip: "Redo (⇧⌘Z)") {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            }

            groupDivider()

            // MARK: - Clipboard Group
            toolbarButton(icon: "scissors", tooltip: "Cut (⌘X)") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            toolbarButton(icon: "doc.on.doc", tooltip: "Copy (⌘C)") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            toolbarButton(icon: "doc.on.clipboard", tooltip: "Paste (⌘V)") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }

            groupDivider()

            // MARK: - Format Group
            toolbarButton(icon: "bold", tooltip: "Bold (⌘B)") {
                NotificationCenter.default.post(name: .toggleBold, object: nil)
            }
            toolbarButton(icon: "italic", tooltip: "Italic (⌘I)") {
                NotificationCenter.default.post(name: .toggleItalic, object: nil)
            }
            toolbarButton(icon: "underline", tooltip: "Underline (⌘U)") {
                NotificationCenter.default.post(name: .toggleUnderline, object: nil)
            }
            toolbarButton(icon: "strikethrough", tooltip: "Strikethrough") {
                NotificationCenter.default.post(name: .toggleStrikethrough, object: nil)
            }

            groupDivider()

            // MARK: - Search Group
            toolbarButton(icon: "magnifyingglass", tooltip: "Find (⌘F)") {
                NotificationCenter.default.post(name: .showFindBar, object: nil)
            }
            toolbarButton(icon: "arrow.left.arrow.right", tooltip: "Find & Replace (⌘H)") {
                NotificationCenter.default.post(name: .showFindReplaceBar, object: nil)
            }

            groupDivider()

            // MARK: - Zoom Group
            toolbarButton(icon: "plus.magnifyingglass", tooltip: "Zoom In (⌘+)") {
                settings.fontSize = min(settings.fontSize + 1, 72)
            }
            toolbarButton(icon: "minus.magnifyingglass", tooltip: "Zoom Out (⌘-)") {
                settings.fontSize = max(settings.fontSize - 1, 8)
            }

            groupDivider()

            // MARK: - Toggle Group
            toolbarToggle(
                icon: "arrow.turn.down.left",
                tooltip: settings.useSoftWrap ? "Word Wrap: On" : "Word Wrap: Off",
                isActive: settings.useSoftWrap
            ) {
                settings.useSoftWrap.toggle()
            }
            toolbarToggle(
                icon: "sidebar.left",
                tooltip: settings.showWorkspacePanel ? "Workspace: On" : "Workspace: Off",
                isActive: settings.showWorkspacePanel
            ) {
                NotificationCenter.default.post(name: .toggleWorkspacePanel, object: nil)
            }
            toolbarButton(icon: "rectangle.split.2x1", tooltip: "Split Editor (⌘\\)") {
                NotificationCenter.default.post(name: .toggleSplitView, object: nil)
            }
            toolbarToggle(
                icon: "chart.bar.doc.horizontal",
                tooltip: settings.showMinimap ? "Document Map: On" : "Document Map: Off",
                isActive: settings.showMinimap
            ) {
                NotificationCenter.default.post(name: .toggleMinimap, object: nil)
            }
            toolbarToggle(
                icon: "list.bullet.rectangle",
                tooltip: settings.showFunctionList ? "Function List: On" : "Function List: Off",
                isActive: settings.showFunctionList
            ) {
                NotificationCenter.default.post(name: .toggleFunctionList, object: nil)
            }

            groupDivider()

            // MARK: - Bookmark Group
            toolbarButton(icon: "bookmark", tooltip: "Toggle Bookmark (F2)") {
                NotificationCenter.default.post(name: .toggleBookmark, object: nil)
            }
            toolbarButton(icon: "chevron.down", tooltip: "Next Bookmark (⌘F2)") {
                NotificationCenter.default.post(name: .nextBookmark, object: nil)
            }
            toolbarButton(icon: "chevron.up", tooltip: "Previous Bookmark (⇧⌘F2)") {
                NotificationCenter.default.post(name: .previousBookmark, object: nil)
            }

            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: metrics.toolbarHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Button Components

    @ViewBuilder
    private func toolbarButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: metrics.toolbarIconSize))
                .frame(width: metrics.toolbarButtonSize.width, height: metrics.toolbarButtonSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarIconButtonStyle())
        .help(tooltip)
    }

    @ViewBuilder
    private func toolbarToggle(icon: String, tooltip: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: metrics.toolbarIconSize))
                .foregroundColor(isActive ? .accentColor : .primary)
                .frame(width: metrics.toolbarButtonSize.width, height: metrics.toolbarButtonSize.height)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolbarIconButtonStyle(isToggle: true, isActive: isActive))
        .help(tooltip)
    }

    @ViewBuilder
    private func groupDivider() -> some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 4)
    }
}

// MARK: - Custom Button Style

struct ToolbarIconButtonStyle: ButtonStyle {
    var isToggle: Bool = false
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(
                isToggle && isActive
                    ? .accentColor
                    : configuration.isPressed ? .accentColor : .primary
            )
            .background(
                Group {
                    if isToggle && isActive {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.15))
                    } else if configuration.isPressed {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.1))
                    } else {
                        Color.clear
                    }
                }
            )
    }
}
