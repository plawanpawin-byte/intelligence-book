import Foundation
import SwiftData

// MARK: - Notebook

@Model
final class Notebook {
    var uuid: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Source.notebook)
    var sources: [Source] = []

    @Relationship(deleteRule: .cascade, inverse: \Note.notebook)
    var notes: [Note] = []

    init(title: String) {
        self.uuid = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sortedSources: [Source] { sources.sorted { $0.createdAt > $1.createdAt } }
    var sortedNotes: [Note] { notes.sorted { $0.updatedAt > $1.updatedAt } }
    var readySources: [Source] { sortedSources.filter { $0.status == .ready } }

    func touch() { updatedAt = Date() }
}

// MARK: - Source

enum SourceKind: String, CaseIterable, Identifiable, Codable {
    case pdf, web, text, audio, recording

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .web: "Web link"
        case .text: "Text"
        case .audio: "Audio file"
        case .recording: "Recording"
        }
    }

    var addLabel: String {
        switch self {
        case .pdf: "PDF file"
        case .web: "Website link"
        case .text: "Paste text"
        case .audio: "Audio file"
        case .recording: "Record audio"
        }
    }

    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .web: "link"
        case .text: "text.alignleft"
        case .audio: "waveform"
        case .recording: "mic"
        }
    }
}

enum SourceStatus: String, Codable {
    case processing, ready, failed

    var label: String {
        switch self {
        case .processing: "Processing"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }
}

@Model
final class Source {
    var uuid: UUID = UUID()
    var kindRaw: String = SourceKind.text.rawValue
    var title: String = ""
    var createdAt: Date = Date()
    var statusRaw: String = SourceStatus.processing.rawValue
    var text: String = ""
    var detail: String?
    var urlString: String?
    var fileName: String?
    /// Cover image for the library card (web page og:image).
    var imageURL: String?
    var notebook: Notebook?

    init(kind: SourceKind, title: String, text: String = "", urlString: String? = nil, fileName: String? = nil) {
        self.uuid = UUID()
        self.kindRaw = kind.rawValue
        self.title = title
        self.text = text
        self.urlString = urlString
        self.fileName = fileName
        self.createdAt = Date()
        self.statusRaw = SourceStatus.processing.rawValue
    }

    var kind: SourceKind { SourceKind(rawValue: kindRaw) ?? .text }

    var status: SourceStatus {
        get { SourceStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var fileURL: URL? { fileName.map { FileStore.url(for: $0) } }
}

// MARK: - Note

enum NoteStyle: String, CaseIterable, Identifiable, Codable {
    case summary, studyGuide, outline, questions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary: "Summary"
        case .studyGuide: "Study guide"
        case .outline: "Outline"
        case .questions: "Review questions"
        }
    }

    var subtitle: String {
        switch self {
        case .summary: "Key points, highlights and definitions"
        case .studyGuide: "In-depth explanations with terms and examples"
        case .outline: "Nested headings, quick to scan"
        case .questions: "Questions and answers for review"
        }
    }

    var symbol: String {
        switch self {
        case .summary: "text.badge.star"
        case .studyGuide: "graduationcap"
        case .outline: "list.bullet.indent"
        case .questions: "questionmark.bubble"
        }
    }
}

@Model
final class Note {
    var uuid: UUID = UUID()
    var title: String = ""
    var markdown: String = ""
    var styleRaw: String = NoteStyle.summary.rawValue
    var modelName: String = ""
    var sourceTitles: [String] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var notebook: Notebook?

    init(title: String, markdown: String, style: NoteStyle, modelName: String, sourceTitles: [String]) {
        self.uuid = UUID()
        self.title = title
        self.markdown = markdown
        self.styleRaw = style.rawValue
        self.modelName = modelName
        self.sourceTitles = sourceTitles
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var style: NoteStyle { NoteStyle(rawValue: styleRaw) ?? .summary }
}

// MARK: - Errors & files

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): m
        }
    }

    /// Readable text for any error, with the step it happened in and the system error code,
    /// so a screenshot is enough to know what went wrong.
    static func describe(_ error: Error, during step: String) -> String {
        if let app = error as? AppError { return app.errorDescription ?? step }
        let ns = error as NSError
        var text = "\(step) failed: \(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        if let underlying {
            text += " ← [\(underlying.domain) \(underlying.code)] \(underlying.localizedDescription)"
        }
        // -5009 and friends come from iCloud Drive / a cloud drive that couldn't deliver the file.
        if ns.domain == "NSFileProviderErrorDomain" || underlying?.domain == "NSFileProviderErrorDomain" {
            text += "\n\niCloud Drive couldn’t hand over this file. In the Files app, touch and hold it → Download Now "
                + "(or move it to On My iPhone), then add it again. You can also share a recording straight from "
                + "Voice Memos → Share → IntelligenceBook."
        }
        return text
    }
}

enum FileStore {
    static var directory: URL {
        let dir = URL.documentsDirectory.appendingPathComponent("Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL { directory.appendingPathComponent(fileName) }

    static func newRecordingName() -> String { "recording-\(UUID().uuidString.prefix(8)).m4a" }

    /// Copies an imported (security-scoped) file into the app's sandbox and returns the stored file name.
    static func importFile(_ source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let name = "\(UUID().uuidString.prefix(8))-\(source.lastPathComponent)"
        let dest = FileStore.url(for: name)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        let fm = FileManager.default
        do {
            // The document picker already hands over a local copy, so a plain copy normally works.
            try fm.copyItem(at: source, to: dest)
        } catch let plainError {
            // Coordinated read makes file providers (iCloud Drive, Google Drive…) deliver the real file first.
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                do {
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: readable, to: dest)
                } catch { copyError = error }
            }
            if let error = coordinationError ?? copyError {
                _ = plainError
                throw AppError.message(AppError.describe(error, during: "Importing \(source.lastPathComponent)")
                    + " — if the file is in iCloud or another cloud drive, download it to the iPhone first.")
            }
        }
        return name
    }

    /// Imports a file picked "in place" (iCloud Drive, other cloud drives, On My iPhone).
    /// Cloud files are asked to download first and we wait for them, with retries, before copying —
    /// iCloud often answers with NSFileProviderErrorDomain -5009 while the file isn't on the device yet.
    static func importPicked(_ source: URL, onStatus: @escaping @MainActor (String) -> Void = { _ in }) async throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        if let values = try? source.resourceValues(forKeys: keys), values.isUbiquitousItem == true,
           values.ubiquitousItemDownloadingStatus != .current {
            await onStatus("Downloading from iCloud…")
            try? fm.startDownloadingUbiquitousItem(at: source)
            for _ in 0..<180 { // up to 90 s
                try Task.checkCancellation()
                var url = source
                url.removeAllCachedResourceValues()
                if let status = try? url.resourceValues(forKeys: keys).ubiquitousItemDownloadingStatus, status == .current { break }
                try await Task.sleep(for: .milliseconds(500))
            }
        }

        var lastError: Error = AppError.message("Couldn’t read the file")
        for attempt in 0..<4 {
            try Task.checkCancellation()
            if attempt > 0 {
                await onStatus("Retrying (\(attempt))…")
                try? fm.startDownloadingUbiquitousItem(at: source)
                try await Task.sleep(for: .seconds(2 * attempt))
            }
            do {
                return try await Task.detached(priority: .userInitiated) { try importFile(source) }.value
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
