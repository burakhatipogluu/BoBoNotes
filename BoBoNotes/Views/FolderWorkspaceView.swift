import SwiftUI
import AppKit

/// Right-side panel showing a folder tree (Folder as Workspace)
struct FolderWorkspaceView: View {
    @EnvironmentObject var store: TabsStore
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.layoutMetrics) private var metrics
    @State private var expandedFolders: Set<URL> = []
    @State private var fileTree: [FileNode] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: metrics.uiFontSize))
                    .frame(width: 16, alignment: .center)

                if let url = settings.workspaceURL {
                    Text(url.lastPathComponent)
                        .font(.system(size: metrics.uiFontSize, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Workspace")
                        .font(.system(size: metrics.uiFontSize, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    // Pin toggle
                    Button(action: { settings.workspacePanelPinned.toggle() }) {
                        Image(systemName: settings.workspacePanelPinned ? "pin.fill" : "pin.slash")
                            .font(.system(size: 10))
                            .foregroundColor(settings.workspacePanelPinned ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(settings.workspacePanelPinned
                        ? "Pinned (restored on app launch)"
                        : "Unpinned (not restored on app launch)")

                    // Open folder button
                    Button(action: selectWorkspaceFolder) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: metrics.uiFontSize))
                    }
                    .buttonStyle(.plain)
                    .help("Open Folder as Workspace")

                    // Close workspace
                    if settings.workspaceURL != nil {
                        Button(action: closeWorkspace) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .help("Close Workspace")
                    }
                }
                .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(height: metrics.paneHeaderHeight)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // File tree
            if settings.workspaceURL != nil {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(fileTree) { node in
                            fileNodeRow(node: node, depth: 0)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Open a folder to browse\nyour files")
                        .font(.system(size: metrics.uiFontSize))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Open Folder...") {
                        selectWorkspaceFolder()
                    }
                    .font(.system(size: metrics.uiFontSize))
                    Text("File access permission will be\nrequested once for the selected folder.")
                        .font(.system(size: max(metrics.uiFontSize - 1, 9)))
                        .foregroundColor(.secondary.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if let url = settings.workspaceURL {
                _ = url.startAccessingSecurityScopedResource()
                loadFileTree(at: url)
            }
        }
        .onDisappear {
            if let url = settings.workspaceURL {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    private func closeWorkspace() {
        if let url = settings.workspaceURL {
            url.stopAccessingSecurityScopedResource()
        }
        settings.clearWorkspace()
        fileTree = []
    }

    private func fileNodeRow(node: FileNode, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Spacer()
                        .frame(width: CGFloat(depth) * metrics.treeIndentPerLevel)

                    if node.isDirectory {
                        Image(systemName: expandedFolders.contains(node.url) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(width: 12)

                        Image(systemName: expandedFolders.contains(node.url) ? "folder.fill" : "folder")
                            .font(.system(size: metrics.uiFontSize))
                            .foregroundColor(.accentColor)

                        Text(node.name)
                            .font(.system(size: metrics.uiFontSize))
                            .lineLimit(1)
                    } else {
                        Spacer().frame(width: 12)

                        Image(systemName: fileIcon(for: node.name))
                            .font(.system(size: metrics.uiFontSize))
                            .foregroundColor(fileIconColor(for: node.name))

                        Text(node.name)
                            .font(.system(size: metrics.uiFontSize))
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    if node.isDirectory {
                        toggleFolder(node)
                    } else {
                        store.openFile(url: node.url)
                    }
                }

                // Children (if expanded)
                if node.isDirectory && expandedFolders.contains(node.url) {
                    ForEach(node.children) { child in
                        fileNodeRow(node: child, depth: depth + 1)
                    }
                }
            }
        )
    }

    private func toggleFolder(_ node: FileNode) {
        if expandedFolders.contains(node.url) {
            expandedFolders.remove(node.url)
        } else {
            expandedFolders.insert(node.url)
            // Load children lazily
            if node.children.isEmpty {
                loadChildren(for: node)
            }
        }
    }

    private func selectWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the folder you want to open as a workspace. BoBoNotes will request permission to read files in this folder."
        panel.prompt = "Open as Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // NSOpenPanel grants access — set as workspace directly
        settings.workspaceURL = url
        settings.showWorkspacePanel = true
        loadFileTree(at: url)
    }

    private func loadFileTree(at url: URL) {
        expandedFolders = [url]
        let nodes = buildNodes(at: url)
        fileTree = nodes
    }

    private func loadChildren(for node: FileNode) {
        guard node.isDirectory else { return }
        let children = buildNodes(at: node.url)
        // Find and update the node in the tree
        updateNode(in: &fileTree, url: node.url, children: children)
    }

    private func updateNode(in nodes: inout [FileNode], url: URL, children: [FileNode]) {
        for i in nodes.indices {
            if nodes[i].url == url {
                nodes[i].children = children
                return
            }
            if nodes[i].isDirectory {
                updateNode(in: &nodes[i].children, url: url, children: children)
            }
        }
    }

    private func buildNodes(at url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [FileNode] = []
        var files: [FileNode] = []

        for item in contents {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let node = FileNode(name: item.lastPathComponent, url: item, isDirectory: isDir)
            if isDir {
                folders.append(node)
            } else {
                files.append(node)
            }
        }

        // Sort: folders first (alphabetical), then files (alphabetical)
        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + files
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "sql": return "cylinder"
        case "html", "htm": return "globe"
        case "css": return "paintbrush"
        case "json": return "curlybraces"
        case "xml": return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.plaintext"
        case "yaml", "yml": return "list.bullet"
        case "sh", "bash", "zsh": return "terminal"
        case "c", "cpp", "h": return "c.square"
        case "java": return "cup.and.saucer"
        case "go": return "g.square"
        case "rs": return "r.square"
        case "rb": return "diamond"
        case "php": return "p.square"
        default: return "doc"
        }
    }

    private func fileIconColor(for name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "py": return .blue
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .cyan
        case "sql": return .purple
        case "html", "htm": return .red
        case "css": return .blue
        case "json": return .green
        case "md": return .gray
        default: return .secondary
        }
    }
}

// MARK: - File Node

struct FileNode: Identifiable {
    /// Use the file URL as identity so SwiftUI can correctly diff nodes
    /// across rebuilds of the tree (e.g. when expanding/collapsing folders).
    var id: URL { url }
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode] = []
}
