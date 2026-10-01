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
    case pdf, web, youtube, text, audio, recording

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .web: "ลิงก์เว็บ"
        case .youtube: "YouTube"
        case .text: "ข้อความ"
        case .audio: "ไฟล์เสียง"
        case .recording: "อัดเสียง"
        }
    }

    var addLabel: String {
        switch self {
        case .pdf: "ไฟล์ PDF"
        case .web: "ลิงก์เว็บไซต์"
        case .youtube: "ลิงก์ YouTube"
        case .text: "วางข้อความ"
        case .audio: "ไฟล์เสียง"
        case .recording: "อัดเสียงตอนนี้"
        }
    }

    var symbol: String {
        switch self {
        case .pdf: "doc.richtext"
        case .web: "link"
        case .youtube: "play.rectangle"
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
        case .processing: "กำลังประมวลผล"
        case .ready: "พร้อมใช้"
        case .failed: "ผิดพลาด"
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
    /// Cover image for the library card (YouTube thumbnail, web og:image).
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
        case .summary: "สรุปใจความ"
        case .studyGuide: "คู่มืออ่านทบทวน"
        case .outline: "โครงร่าง"
        case .questions: "คำถามทบทวน"
        }
    }

    var subtitle: String {
        switch self {
        case .summary: "ประเด็นสำคัญ ไฮไลท์ และนิยาม"
        case .studyGuide: "อธิบายละเอียด พร้อมคำศัพท์และตัวอย่าง"
        case .outline: "หัวข้อเป็นลำดับชั้น อ่านเร็ว"
        case .questions: "คำถาม-คำตอบสำหรับทบทวน"
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
        try FileManager.default.copyItem(at: source, to: dest)
        return name
    }

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
