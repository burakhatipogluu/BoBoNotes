import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared

    private let monoFonts = ["Menlo", "Monaco", "SF Mono", "Courier New", "Consolas", "Source Code Pro", "Fira Code", "JetBrains Mono", "IBM Plex Mono"]

    private var settingsWidth: CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1440
        if screenWidth < 1200 { return 420 }
        if screenWidth < 1800 { return 480 }
        return 540
    }

    private var settingsHeight: CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1440
        if screenWidth < 1200 { return 360 }
        if screenWidth < 1800 { return 400 }
        return 440
    }

    var body: some View {
        TabView {
            // MARK: - Appearance Tab
            Form {
                Section("Theme") {
                    Picker("App Theme", selection: $settings.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Font") {
                    Picker("Family", selection: $settings.fontName) {
                        ForEach(monoFonts, id: \.self) { font in
                            Text(font).font(.custom(font, size: 12)).tag(font)
                        }
                    }
                    HStack {
                        Text("Size")
                        Spacer()
                        Text("\(Int(settings.fontSize)) pt")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                        Stepper("", value: $settings.fontSize, in: 8...72, step: 1)
                            .labelsHidden()
                    }
                }
            }
            .tabItem { Label("Appearance", systemImage: "paintbrush") }
            .padding()

            // MARK: - Editor Tab
            Form {
                Section("Indentation") {
                    Toggle("Use Spaces for Tabs", isOn: $settings.useSpacesForTabs)
                    Stepper("Tab Width: \(settings.tabWidth)", value: $settings.tabWidth, in: 1...8)
                    Toggle("Auto-Indent", isOn: $settings.autoIndent)
                }

                Section("Typing") {
                    Toggle("Auto-Close Brackets & Quotes", isOn: $settings.autoCloseBrackets)
                    Toggle("Mark Occurrences of Selection", isOn: $settings.markOccurrences)
                    Toggle("Highlight Matching Brackets", isOn: $settings.highlightMatchingBrackets)
                    Toggle("Spell Checking", isOn: $settings.enableSpellChecker)
                }

                Section("Save") {
                    Toggle("Trim Trailing Whitespace on Save", isOn: $settings.trimTrailingWhitespaceOnSave)
                    Picker("Default Encoding", selection: $settings.defaultEncodingRawValue) {
                        ForEach(EditorDocument.supportedEncodings, id: \.1.rawValue) { name, encoding in
                            Text(name).tag(Int(encoding.rawValue))
                        }
                    }
                }

                Section("Session") {
                    Toggle("Restore Session on Launch", isOn: $settings.restoreSessionOnLaunch)
                }
            }
            .tabItem { Label("Editor", systemImage: "text.alignleft") }
            .padding()

            // MARK: - View Tab
            Form {
                Section("Editor") {
                    Toggle("Line Numbers", isOn: $settings.showLineNumbers)
                    Picker("Line Number Mode", selection: $settings.lineNumberMode) {
                        Text("Absolute").tag("absolute")
                        Text("Relative").tag("relative")
                        Text("Interval").tag("interval")
                    }
                    Toggle("Highlight Current Line", isOn: $settings.highlightCurrentLine)
                    Toggle("Word Wrap", isOn: $settings.useSoftWrap)
                    Toggle("Show Invisible Characters", isOn: $settings.showInvisibles)
                }

                Section("Panels") {
                    Toggle("Show Toolbar", isOn: $settings.showToolbar)
                    Toggle("Document Map (Minimap)", isOn: $settings.showMinimap)
                    Toggle("Overview Ruler", isOn: $settings.showOverviewRuler)
                    Toggle("Function List", isOn: $settings.showFunctionList)
                }
            }
            .tabItem { Label("View", systemImage: "sidebar.squares.left") }
            .padding()
        }
        .frame(width: settingsWidth, height: settingsHeight)
    }
}
