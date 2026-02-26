import Foundation
import AppKit

/// Represents a single document with its content, file URL, encoding, and dirty state.
final class EditorDocument: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var content: String
    @Published var fileURL: URL?
    @Published var encoding: String.Encoding
    @Published var isDirty: Bool = false
    @Published var lineEnding: LineEnding = .lf
    @Published var languageID: String? = nil  // Detected or manually set language

    /// Undo manager per document
    let undoManager = UndoManager()

    enum LineEnding: String, CaseIterable {
        case lf = "LF (Unix)"
        case crlf = "CRLF (Windows)"
        case cr = "CR (Classic Mac)"

        var characters: String {
            switch self {
            case .lf: return "\n"
            case .crlf: return "\r\n"
            case .cr: return "\r"
            }
        }
    }

    init(title: String = "Untitled", content: String = "", fileURL: URL? = nil, encoding: String.Encoding = .utf8) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.fileURL = fileURL
        self.encoding = encoding
    }

    /// Load from file
    static func load(from url: URL, encoding: String.Encoding = .utf8) throws -> EditorDocument {
        let data = try Data(contentsOf: url)

        // Try specified encoding first, fall back to utf8, then isoLatin1
        let text: String
        var actualEncoding = encoding
        if let decoded = String(data: data, encoding: encoding) {
            text = decoded
        } else if let decoded = String(data: data, encoding: .utf8) {
            text = decoded
            actualEncoding = .utf8
        } else if let decoded = String(data: data, encoding: .isoLatin1) {
            text = decoded
            actualEncoding = .isoLatin1
        } else {
            throw NSError(domain: "BoBoNotes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode file with any supported encoding."])
        }

        let doc = EditorDocument(
            title: url.lastPathComponent,
            content: text,
            fileURL: url,
            encoding: actualEncoding
        )

        // Detect line ending
        if text.contains("\r\n") {
            doc.lineEnding = .crlf
        } else if text.contains("\r") {
            doc.lineEnding = .cr
        } else {
            doc.lineEnding = .lf
        }

        return doc
    }

    /// Save to file
    func save(to url: URL? = nil) throws {
        let targetURL = url ?? fileURL
        guard let targetURL = targetURL else {
            throw NSError(domain: "BoBoNotes", code: 2, userInfo: [NSLocalizedDescriptionKey: "No file URL specified."])
        }

        // Apply the document's line ending before encoding
        var output = content
        if lineEnding != .lf {
            // Normalize to LF first, then convert to target line ending
            output = output.replacingOccurrences(of: "\r\n", with: "\n")
                           .replacingOccurrences(of: "\r", with: "\n")
            if lineEnding == .crlf {
                output = output.replacingOccurrences(of: "\n", with: "\r\n")
            } else if lineEnding == .cr {
                output = output.replacingOccurrences(of: "\n", with: "\r")
            }
        }

        guard let data = output.data(using: encoding) else {
            throw NSError(domain: "BoBoNotes", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to encode content with selected encoding."])
        }

        try data.write(to: targetURL, options: .atomic)
        self.fileURL = targetURL
        self.title = targetURL.lastPathComponent
        self.isDirty = false
    }

    /// Supported encodings for the UI
    static let supportedEncodings: [(String, String.Encoding)] = [
        ("UTF-8", .utf8),
        ("UTF-16", .utf16),
        ("UTF-16 LE", .utf16LittleEndian),
        ("UTF-16 BE", .utf16BigEndian),
        ("ISO 8859-9 (Turkish)", .windowsCP1254),
        ("ISO 8859-1 (Latin 1)", .isoLatin1),
        ("ASCII", .ascii),
        ("Mac OS Roman", .macOSRoman),
        ("Windows 1252", .windowsCP1252),
    ]
}
