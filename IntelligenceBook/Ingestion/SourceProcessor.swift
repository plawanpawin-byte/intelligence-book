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
        var step = "Reading the source"
        do {
            switch source.kind {
            case .pdf:
                guard let url = source.fileURL else { throw AppError.message("File not found") }
                step = "Reading the PDF"
                source.detail = "Reading PDF"
                source.text = try await PDFExtractor.extract(url: url)

            case .web:
                step = "Loading the web page"
                source.detail = "Fetching web page"
                let result = try await WebExtractor.fetch(source.urlString ?? "")
                source.text = result.text
                if !result.title.isEmpty { source.title = result.title }
                source.imageURL = result.image

            case .text:
                break

            case .recording where !source.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                break // already transcribed live while recording

            case .audio, .recording:
                guard let url = source.fileURL else { throw AppError.message("Audio file not found") }
                step = "Transcribing the audio"
                source.detail = "Transcribing 0%"
                source.text = try await SpeechTranscriber.transcribe(url: url, locale: .current) { fraction in
                    source.detail = "Transcribing \(Int(fraction * 100))%"
                }
            }

            let trimmed = source.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AppError.message("No text found in this source") }
            source.text = trimmed
            source.status = .ready
            source.detail = "\(trimmed.count.formatted()) characters"
            source.notebook?.touch()
        } catch is CancellationError {
            source.status = .failed
            source.detail = "Cancelled"
        } catch {
            source.status = .failed
            source.detail = AppError.describe(error, during: step)
        }
    }
}
