<p align="center">
  <img src="logo.png" alt="BoBoNotes" width="400">
</p>

<h3 align="center">A fast, lightweight, and native text editor for macOS</h3>

<p align="center">
  Built with Swift, SwiftUI & AppKit · No Electron · No web views · Just fast editing
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#keyboard-shortcuts">Shortcuts</a> •
  <a href="#building-from-source">Build</a> •
  <a href="#privacy">Privacy</a> •
  <a href="#license">License</a>
</p>

---

## About

BoBoNotes is a native macOS text editor designed for everyday writing, notes, configuration files, and script editing. It's named after **Bobo** — a tiny toy poodle who sniffs every corner and peeks behind every drawer. BoBoNotes' search and discovery features are inspired by his endless curiosity. 🐩

## Features

### ✏️ Core Editor
- Multi-tab document editing with drag-reorderable tab bar
- High-performance NSTextView with TextKit
- Line numbers (absolute, relative, interval modes)
- Current line highlight
- Soft wrap toggle
- Configurable indentation (tabs/spaces, width 1–8)
- Multiple encoding support (UTF-8, UTF-16, ISO 8859-1/9, ASCII, Mac OS Roman, Windows-1252)
- Line ending detection and switching (LF, CRLF, CR)
- Undo/Redo per document
- Large file support

### 🔍 Search & Replace
- Find bar with Find / Replace
- Match Case, Whole Word, Regex, Wrap Around
- **Find All** across current document, open documents, or entire folder
- Bottom search results panel with file grouping, line numbers, and click-to-jump
- Incremental background search via Swift Concurrency

### 🎨 Syntax Highlighting
26+ languages with automatic detection:

| | | | |
|---|---|---|---|
| Swift | Python | JavaScript | TypeScript |
| SQL | PL/SQL | Bash | PowerShell |
| Java | C | C++ | C# |
| Go | Rust | PHP | Ruby |
| HTML | CSS | XML | JSON |
| YAML | Markdown | INI | TOML |
| Properties | Log | | |

- VS Code-inspired Dark+ and Light+ color themes
- Automatic system appearance matching
- Visible-range incremental highlighting for performance

### 🗂️ Workspace & Navigation
- **Workspace Browser** — Open any folder and browse files from the sidebar
- **Function List** — Jump to functions, methods, and class definitions
- **Minimap** — Bird's-eye document overview with click-to-navigate
- **Split View** — View two files side by side
- **Compare Notes** — Diff two documents with color-coded changes (green/red)
- **Bookmarks** — Mark important lines and navigate between them
- **File extension icons** — Color-coded icons for easy identification

### ⚙️ Settings
- Font family and size
- Indentation (tabs/spaces, width)
- Display (line numbers, current line highlight, word wrap, minimap)
- Theme (Dark / Light)
- Default encoding

## Installation

### Homebrew (coming soon)

```bash
brew install --cask bobonotes
```

### App Store (coming soon)

Available on the Mac App Store.

### Building from Source

**Requirements:** macOS 13.0+, Xcode 15+

```bash
git clone https://github.com/burakhatipogluu/BoBoNotes.git
cd BoBoNotes
open BoBoNotes.xcodeproj
```

Select the **BoBoNotes** scheme and press `Cmd+R` to build and run.

## Screenshots

*Coming soon*

<!-- 
![Dark Theme](screenshots/dark-theme.png)
![Light Theme](screenshots/light-theme.png)
![Search Results](screenshots/search-results.png)
-->

## Keyboard Shortcuts

### File
| Action | Shortcut |
|--------|----------|
| New | `⌘N` |
| Open | `⌘O` |
| Save | `⌘S` |
| Save As | `⇧⌘S` |
| Close Tab | `⌘W` |

### Edit
| Action | Shortcut |
|--------|----------|
| Go to Line | `⌘L` |
| Select Next Occurrence | `⌘D` |
| Duplicate Line | `⇧⌘D` |
| Delete Line | `⇧⌘K` |
| Move Line Up / Down | `⌥↑` / `⌥↓` |
| Join Lines | `⌘J` |
| Toggle Comment | `⌘/` |
| Go to Matching Bracket | `⌘]` |

### Find
| Action | Shortcut |
|--------|----------|
| Find | `⌘F` |
| Find & Replace | `⌘H` |
| Find Next / Previous | `⌘G` / `⇧⌘G` |
| Find in Folder | `⇧⌘F` |

### View
| Action | Shortcut |
|--------|----------|
| Toggle Toolbar | `⌥⌘T` |
| Toggle Word Wrap | `⌥⌘Z` |
| Function List | `⇧⌘L` |
| Workspace | `⇧⌘E` |
| Split View | `⌘\` |
| Zoom In / Out | `⌘+` / `⌘-` |
| Reset Zoom | `⌘0` |

### Navigation
| Action | Shortcut |
|--------|----------|
| Next Tab | `⇧⌘]` |
| Previous Tab | `⇧⌘[` |
| Toggle Bookmark | `⌥⌘B` |
| Next / Previous Bookmark | `⌥⌘N` / `⌥⌘P` |

## Architecture

```
BoBoNotes/
├── BoBoNotesApp.swift              # App entry, menus, commands
├── Models/
│   ├── EditorDocument.swift        # Document model
│   ├── EditorTab.swift             # Tab state
│   ├── TabsStore.swift             # Tab management
│   ├── AppSettings.swift           # User preferences
│   ├── SearchModels.swift          # Search data types
│   ├── SearchResultsStore.swift    # Search state
│   └── LanguageDefinition.swift    # Token types & rules
├── Views/
│   ├── ContentView.swift           # Main layout
│   ├── EditorTextView.swift        # NSTextView wrapper
│   ├── LineNumberRulerView.swift   # Line number gutter
│   ├── TabBarView.swift            # Tab bar
│   ├── StatusBarView.swift         # Status bar
│   ├── SettingsView.swift          # Preferences
│   ├── FindReplaceBar.swift        # Find/Replace UI
│   ├── SearchResultsPanel.swift    # Search results
│   ├── FolderWorkspaceView.swift   # File browser
│   ├── FunctionListView.swift      # Symbol list
│   └── DiffView.swift              # Diff viewer
├── Services/
│   ├── HighlightrSyntaxService.swift  # Syntax engine
│   ├── LanguageRegistry.swift         # 26+ language definitions
│   ├── SearchService.swift            # Async search engine
│   ├── SessionManager.swift           # Session persistence
│   ├── CodeFoldingService.swift       # Code folding
│   ├── FunctionListService.swift      # Symbol extraction
│   └── DiffService.swift              # Diff engine
└── Assets.xcassets/                   # App icons & assets
```

## Privacy

BoBoNotes works **entirely offline**. No data is collected, no network requests are made, no accounts are required. Your files stay on your Mac.

See our full [Privacy Policy](docs/appstore/privacy-policy.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Made with ❤️ and inspired by Bobo 🐩
</p>
