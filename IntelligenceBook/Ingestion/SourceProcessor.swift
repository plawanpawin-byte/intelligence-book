import Foundation
import SwiftData

/// Extracts readable text from each source on-device.
@MainActor
final class SourceProcessor {
    static let shared = SourceProcessor()
    private var tasks: [UUID: Task<Void, Never>] = [:]

    private init() {}

    func process(_ source: Source) {
        tasks[source.uuid]?.cancel()
        tasks[source.uuid] = Task { [weak self] in
            await self?.run(source)
            self?.tasks[source.uuid] = nil
        }
    }

    func cancel(_ source: Source) {
        tasks[source.uuid]?.cancel()
        tasks[source.uuid] = nil
    }

    /// Re-run anything that was interrupted (e.g. the app was closed mid-transcription).
    func resumePending(in context: ModelContext) {
        let pending = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        for source in pending where source.status == .processing && tasks[source.uuid] == nil {
            process(source)
        }
    }

    private func run(_ source: Source) async {
        source.status = .processing
        source.detail = nil
        do {
            switch source.kind {
            case .pdf:
                guard let url = source.fileURL else { throw AppError.message("ไม่พบไฟล์") }
                source.detail = "กำลังอ่าน PDF"
                source.text = try await PDFExtractor.extract(url: url)

            case .web:
                source.detail = "กำลังดึงหน้าเว็บ"
                let result = try await WebExtractor.fetch(source.urlString ?? "")
                source.text = result.text
                if !result.title.isEmpty { source.title = result.title }
                source.imageURL = result.image

            case .youtube:
                source.detail = "กำลังดึงคำบรรยาย"
                source.imageURL = YouTubeTranscript.thumbnailURL(for: source.urlString ?? "")
                let result = try await YouTubeTranscript.fetch(source.urlString ?? "")
                source.text = result.text
                source.title = result.title

            case .text:
                break

            case .audio, .recording:
                guard let url = source.fileURL else { throw AppError.message("ไม่พบไฟล์เสียง") }
                source.detail = "กำลังถอดเสียง 0%"
                source.text = try await SpeechTranscriber.transcribe(url: url, locale: .current) { fraction in
                    source.detail = "กำลังถอดเสียง \(Int(fraction * 100))%"
                }
            }

            let trimmed = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AppError.message("ไม่พบข้อความในแหล่งข้อมูลนี้") }
            source.text = trimmed
            source.status = .ready
            source.detail = "\(trimmed.count.formatted()) ตัวอักษร"
            source.notebook?.touch()
        } catch is CancellationError {
            source.status = .failed
            source.detail = "ยกเลิกแล้ว"
        } catch {
            source.status = .failed
            source.detail = error.localizedDescription
        }
    }
}
