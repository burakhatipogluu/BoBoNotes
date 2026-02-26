import Foundation
import SwiftUI
import AppKit

/// Editor appearance mode.
enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
}

/// Global application settings
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("useSoftWrap") var useSoftWrap: Bool = true
    @AppStorage("useSpacesForTabs") var useSpacesForTabs: Bool = true
    @AppStorage("tabWidth") var tabWidth: Int = 4
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true
    @AppStorage("highlightCurrentLine") var highlightCurrentLine: Bool = true
    @AppStorage("autoIndent") var autoIndent: Bool = true
    @AppStorage("trimTrailingWhitespaceOnSave") var trimTrailingWhitespaceOnSave: Bool = false
    @AppStorage("autoCloseBrackets") var autoCloseBrackets: Bool = true
    @AppStorage("highlightMatchingBrackets") var highlightMatchingBrackets: Bool = true
    @AppStorage("markOccurrences") var markOccurrences: Bool = true
    @AppStorage("restoreSessionOnLaunch") var restoreSessionOnLaunch: Bool = true
    @AppStorage("fontSize") var fontSize: Double = 13.0
    @AppStorage("fontName") var fontName: String = "Consolas"
    @AppStorage("defaultEncoding") var defaultEncodingRawValue: Int = 4 // .utf8
    @AppStorage("appTheme") var appThemeRaw: String = AppTheme.dark.rawValue
    @AppStorage("showWorkspacePanel") var showWorkspacePanel: Bool = false
    @AppStorage("searchPanelPinned") var searchPanelPinned: Bool = false
    @AppStorage("workspacePanelPinned") var workspacePanelPinned: Bool = true
    @AppStorage("showToolbar") var showToolbar: Bool = true
    @AppStorage("showInvisibles") var showInvisibles: Bool = false
    @AppStorage("showMinimap") var showMinimap: Bool = false
    @AppStorage("showOverviewRuler") var showOverviewRuler: Bool = true
    @AppStorage("enableSpellChecker") var enableSpellChecker: Bool = false
    @AppStorage("showFunctionList") var showFunctionList: Bool = false
    @AppStorage("lineNumberMode") var lineNumberMode: String = "absolute"  // absolute, relative, interval
    @AppStorage("hasShownWelcomeNote") var hasShownWelcomeNote: Bool = false

    /// Fixed syntax theme: dark = vs2015, light = atom-one-light
    var currentSyntaxTheme: String {
        isDarkMode ? "vs2015" : "atom-one-light"
    }

    // MARK: - Workspace Persistence (security-scoped bookmark)

    private let workspaceBookmarkKey = "workspaceBookmark"

    var workspaceURL: URL? {
        get {
            guard let data = UserDefaults.standard.data(forKey: workspaceBookmarkKey) else { return nil }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            if isStale {
                // Try to re-save the bookmark
                saveWorkspaceBookmark(url: url)
            }
            return url
        }
        set {
            objectWillChange.send()
            if let url = newValue {
                saveWorkspaceBookmark(url: url)
            } else {
                UserDefaults.standard.removeObject(forKey: workspaceBookmarkKey)
            }
        }
    }

    func saveWorkspaceBookmark(url: URL) {
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: workspaceBookmarkKey)
        }
    }

    func clearWorkspace() {
        objectWillChange.send()
        UserDefaults.standard.removeObject(forKey: workspaceBookmarkKey)
        showWorkspacePanel = false
    }

    var appTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .dark }
        set {
            objectWillChange.send()
            appThemeRaw = newValue.rawValue
        }
    }

    var defaultEncoding: String.Encoding {
        get { String.Encoding(rawValue: UInt(defaultEncodingRawValue)) }
        set { defaultEncodingRawValue = Int(newValue.rawValue) }
    }

    var editorFont: NSFont {
        NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
    }

    /// Resolved: is the editor currently in dark mode?
    var isDarkMode: Bool {
        appTheme == .dark
    }

    /// Explicit editor text color — never relies on system semantic colors
    var editorTextColor: NSColor {
        isDarkMode ? NSColor(calibratedWhite: 0.93, alpha: 1.0) : NSColor(calibratedWhite: 0.1, alpha: 1.0)
    }

    /// Explicit editor background color
    var editorBackgroundColor: NSColor {
        isDarkMode ? NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.18, alpha: 1.0) : NSColor(calibratedWhite: 1.0, alpha: 1.0)
    }

    /// Cursor color
    var editorCursorColor: NSColor {
        isDarkMode ? NSColor(calibratedWhite: 0.95, alpha: 1.0) : NSColor(calibratedWhite: 0.05, alpha: 1.0)
    }

    /// Current line highlight color
    var currentLineHighlightColor: NSColor {
        isDarkMode ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04)
    }

    /// NSAppearance for forcing theme
    var nsAppearance: NSAppearance? {
        switch appTheme {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    private init() {}
}
