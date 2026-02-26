import SwiftUI

/// Horizontal tab bar showing open documents.
struct TabBarView: View {
    @ObservedObject var store: TabsStore
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(store.tabs) { tab in
                    TabItemView(tab: tab, isActive: tab.id == store.activeTabID) {
                        store.selectTab(tab)
                    } onClose: {
                        store.closeTab(tab)
                    }
                    .contextMenu {
                        Button("Close") { store.closeTab(tab) }
                        Button("Close Others") { store.closeOtherTabs(except: tab) }
                        Button("Close All") { store.closeAllTabs() }
                        Button("Close to the Right") { store.closeTabsToRight(of: tab) }
                        Divider()
                        if let url = tab.document.fileURL {
                            Button("Copy File Path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.path, forType: .string)
                            }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                    }
                }
            }
        }
        .frame(height: metrics.tabBarHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct TabItemView: View {
    @ObservedObject var tab: EditorTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @Environment(\.layoutMetrics) private var metrics
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 5) {
            // BoBoNotes logo (tab icon)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: metrics.tabIconSize, height: metrics.tabIconSize)

            if tab.document.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }

            Text(tab.document.title)
                .font(.system(size: metrics.uiFontSize))
                .lineLimit(1)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isActive ? 1 : 0)
        }
        .padding(.horizontal, metrics.tabHorizontalPadding)
        .padding(.vertical, 6)
        .background(
            isActive
                ? Color(nsColor: .textBackgroundColor)
                : Color(nsColor: .controlBackgroundColor)
        )
        .overlay(
            Rectangle()
                .frame(height: isActive ? 2 : 0)
                .foregroundColor(.accentColor),
            alignment: .bottom
        )
        .overlay(
            Rectangle()
                .frame(width: 0.5)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .trailing
        )
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
