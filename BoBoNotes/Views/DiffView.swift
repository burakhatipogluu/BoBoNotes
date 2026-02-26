import SwiftUI
import AppKit

/// Side-by-side inline diff view — shows two documents with colored line highlights.
/// Left side: original with removals in red. Right side: modified with additions in green.
struct DiffView: View {
    let diffResult: DiffResult
    let leftTitle: String
    let rightTitle: String
    let leftContent: String
    let rightContent: String
    let onClose: () -> Void
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // MARK: - Left Panel (Original / Removals)
                VStack(spacing: 0) {
                    diffPaneHeader(
                        icon: "minus.circle.fill",
                        iconColor: .red,
                        title: leftTitle,
                        stat: "− \(diffResult.removedCount) removals",
                        statColor: .red,
                        lineCount: diffResult.leftLineCount,
                        content: leftContent,
                        showClose: true
                    )

                    Divider()

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(diffResult.pairs) { pair in
                                DiffSideRowView(row: pair.left)
                            }
                        }
                    }
                }
                .frame(minWidth: metrics.diffPaneMinWidth)

                // MARK: - Right Panel (Modified / Additions)
                VStack(spacing: 0) {
                    diffPaneHeader(
                        icon: "plus.circle.fill",
                        iconColor: .green,
                        title: rightTitle,
                        stat: "+ \(diffResult.addedCount) additions",
                        statColor: .green,
                        lineCount: diffResult.rightLineCount,
                        content: rightContent,
                        showClose: false
                    )

                    Divider()

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(diffResult.pairs) { pair in
                                DiffSideRowView(row: pair.right)
                            }
                        }
                    }
                }
                .frame(minWidth: metrics.diffPaneMinWidth)
            }
        }
    }

    // MARK: - Pane Header

    @ViewBuilder
    private func diffPaneHeader(
        icon: String, iconColor: Color, title: String,
        stat: String, statColor: Color,
        lineCount: Int, content: String, showClose: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: metrics.uiFontSizeMedium))
                .foregroundColor(iconColor)

            Text(stat)
                .font(.system(size: metrics.uiFontSize, weight: .semibold))
                .foregroundColor(statColor)

            Text(title)
                .font(.system(size: metrics.uiFontSize, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Text("\(lineCount) lines")
                .font(.system(size: metrics.uiFontSizeSmall))
                .foregroundColor(.secondary)

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(content, forType: .string)
            }
            .font(.system(size: metrics.uiFontSizeSmall, weight: .medium))
            .buttonStyle(.bordered)
            .controlSize(.mini)

            if showClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: metrics.uiFontSizeMedium + 2))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close compare")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: metrics.diffHeaderHeight)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Single Side Row

struct DiffSideRowView: View {
    let row: DiffSideRow

    var body: some View {
        HStack(spacing: 0) {
            // Line number
            Text(row.lineNumber.map { String($0) } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
                .foregroundColor(.secondary)
                .padding(.trailing, 8)

            // Text content
            Text(row.isEmpty ? " " : row.text)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1.5)
        .padding(.horizontal, 4)
        .background(backgroundColor)
    }

    private var backgroundColor: Color {
        switch row.type {
        case .unchanged:
            return .clear
        case .removed:
            return row.isEmpty ? .clear : Color.red.opacity(0.15)
        case .added:
            return row.isEmpty ? .clear : Color.green.opacity(0.15)
        }
    }
}
