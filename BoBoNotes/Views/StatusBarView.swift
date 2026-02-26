import SwiftUI

/// Bottom status bar showing cursor position, encoding, line ending, etc.
struct StatusBarView: View {
    @ObservedObject var store: TabsStore
    @ObservedObject var settings: AppSettings
    @Environment(\.layoutMetrics) private var metrics

    var body: some View {
        HStack(spacing: 16) {
            if let tab = store.activeTab {
                // Cursor position
                Text("Ln \(tab.cursorLine), Col \(tab.cursorColumn)")
                    .font(.system(size: metrics.uiFontSize))

                Divider().frame(height: 12)

                // Word & character count
                Text("Words: \(tab.wordCount)  Chars: \(tab.charCount)")
                    .font(.system(size: metrics.uiFontSize))
                    .foregroundColor(.secondary)

                Divider().frame(height: 12)

                // Encoding
                Menu {
                    ForEach(EditorDocument.supportedEncodings, id: \.1.rawValue) { name, encoding in
                        Button(name) {
                            tab.document.encoding = encoding
                        }
                    }
                } label: {
                    Text(encodingName(tab.document.encoding))
                        .font(.system(size: metrics.uiFontSize))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Divider().frame(height: 12)

                // Line ending
                Menu {
                    ForEach(EditorDocument.LineEnding.allCases, id: \.self) { ending in
                        Button(ending.rawValue) {
                            tab.document.lineEnding = ending
                        }
                    }
                } label: {
                    Text(tab.document.lineEnding.rawValue)
                        .font(.system(size: metrics.uiFontSize))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Divider().frame(height: 12)

                // Wrap toggle
                Button(action: { settings.useSoftWrap.toggle() }) {
                    Text(settings.useSoftWrap ? "Wrap: On" : "Wrap: Off")
                        .font(.system(size: metrics.uiFontSize))
                }
                .buttonStyle(.plain)

                Divider().frame(height: 12)

                // Tab/Spaces
                Button(action: { settings.useSpacesForTabs.toggle() }) {
                    Text(settings.useSpacesForTabs ? "Spaces: \(settings.tabWidth)" : "Tab: \(settings.tabWidth)")
                        .font(.system(size: metrics.uiFontSize))
                }
                .buttonStyle(.plain)

                Divider().frame(height: 12)

                // Bookmarks
                if !tab.bookmarkedLines.isEmpty {
                    Divider().frame(height: 12)

                    Button(action: {
                        NotificationCenter.default.post(name: .nextBookmark, object: nil)
                    }) {
                        Text("Bookmarks: \(tab.bookmarkedLines.count)")
                            .font(.system(size: metrics.uiFontSize))
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 12)

                // Language
                Menu {
                    ForEach(LanguageRegistry.shared.languages, id: \.id) { lang in
                        Button(lang.displayName) {
                            tab.document.languageID = lang.id
                            NotificationCenter.default.post(name: .languageDidChange, object: lang.id)
                        }
                    }
                } label: {
                    Text(languageName(tab.document.languageID))
                        .font(.system(size: metrics.uiFontSize))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: metrics.statusBarHeight)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(nsColor: .separatorColor)),
            alignment: .top
        )
    }

    private func encodingName(_ encoding: String.Encoding) -> String {
        EditorDocument.supportedEncodings.first { $0.1 == encoding }?.0 ?? "UTF-8"
    }

    private func languageName(_ id: String?) -> String {
        guard let id = id else { return "Plain Text" }
        return LanguageRegistry.shared.language(forID: id)?.displayName ?? "Plain Text"
    }
}
