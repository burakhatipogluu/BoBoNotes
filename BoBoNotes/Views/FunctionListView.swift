import SwiftUI

/// Right-side panel showing extracted symbols (functions, classes, etc.) from the active document.
/// Function List panel showing symbols extracted from the current document.
struct FunctionListView: View {
    let symbols: [SymbolItem]
    let onSymbolTap: (Int) -> Void  // lineNumber callback
    @State private var filterText: String = ""
    @Environment(\.layoutMetrics) private var metrics

    private var filteredSymbols: [SymbolItem] {
        if filterText.isEmpty {
            return symbols
        }
        return symbols.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.accentColor)
                    .font(.system(size: metrics.uiFontSize))

                Text("Function List")
                    .font(.system(size: metrics.uiFontSize, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text("\(filteredSymbols.count)")
                    .font(.system(size: metrics.uiFontSizeSmall))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Filter field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: metrics.uiFontSizeSmall))
                    .foregroundColor(.secondary)

                TextField("Filter...", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: metrics.uiFontSize))

                if !filterText.isEmpty {
                    Button(action: { filterText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: metrics.uiFontSizeSmall))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            // Symbol list
            if filteredSymbols.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "function")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(symbols.isEmpty ? "No symbols found" : "No matches")
                        .font(.system(size: metrics.uiFontSize))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredSymbols) { symbol in
                            symbolRow(symbol)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 160)
    }

    @ViewBuilder
    private func symbolRow(_ symbol: SymbolItem) -> some View {
        Button(action: { onSymbolTap(symbol.lineNumber) }) {
            HStack(spacing: 6) {
                Image(systemName: symbol.kind.icon)
                    .font(.system(size: metrics.uiFontSizeSmall))
                    .foregroundColor(iconColor(for: symbol.kind))
                    .frame(width: 14)

                Text(symbol.name)
                    .font(.system(size: metrics.uiFontSize, design: .monospaced))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Spacer()

                Text(":\(symbol.lineNumber)")
                    .font(.system(size: metrics.uiFontSizeSmall, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func iconColor(for kind: SymbolItem.SymbolKind) -> Color {
        switch kind {
        case .function, .method: return .blue
        case .classDecl: return .purple
        case .structDecl: return .orange
        case .enumDecl: return .green
        case .protocolDecl, .interfaceDecl: return .teal
        case .property: return .secondary
        case .moduleDecl: return .brown
        }
    }
}
