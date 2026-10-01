import Foundation
import Speech
import AVFoundation

enum SpeechLocale: String, CaseIterable, Identifiable {
    case thai = "th-TH"
    case english = "en-US"
    case englishUK = "en-GB"
    case japanese = "ja-JP"
    case chinese = "zh-CN"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thai: "ไทย"
        case .english: "English (US)"
        case .englishUK: "English (UK)"
        case .japanese: "日本語"
        case .chinese: "中文"
        }
    }

    static let storageKey = "speechLocale"
    static var current: SpeechLocale {
        if let saved = UserDefaults.standard.string(forKey: storageKey), let locale = SpeechLocale(rawValue: saved) {
            return locale
        }
        let language = Locale.preferredLanguages.first ?? "th"
        if language.hasPrefix("en") { return .english }
        if language.hasPrefix("ja") { return .japanese }
        if language.hasPrefix("zh") { return .chinese }
        return .thai
    }
}

/// Transcribes audio files of any length by feeding the recognizer ~50 second slices.
enum SpeechTranscriber {
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func transcribe(
        url: URL,
        locale: SpeechLocale,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> String {
        guard await requestAuthorization() else {
            throw AppError.message("ยังไม่ได้อนุญาต Speech Recognition — เปิดได้ที่ การตั้งค่า > IntelligenceBook")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale.rawValue)) else {
            throw AppError.message("เครื่องนี้ไม่รองรับการถอดเสียงภาษา \(locale.label)")
        }
        guard recognizer.isAvailable else {
            throw AppError.message("ระบบถอดเสียงไม่พร้อมใช้งานตอนนี้ (ตรวจสอบอินเทอร์เน็ต)")
        }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0 else { throw AppError.message("ไฟล์เสียงว่างเปล่า") }
        let sliceFrames = AVAudioFramePosition(format.sampleRate * 50)

        var pieces: [String] = []
        var start: AVAudioFramePosition = 0
        while start < totalFrames {
            try Task.checkCancellation()
            let count = min(sliceFrames, totalFrames - start)
            file.framePosition = start

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = false
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }

            var remaining = count
            while remaining > 0 {
                let frames = AVAudioFrameCount(min(remaining, 16_384))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
                try file.read(into: buffer, frameCount: frames)
                if buffer.frameLength == 0 { break }
                request.append(buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }
            request.endAudio()

            let text = try await recognize(request, with: recognizer)
            if !text.isEmpty {
                let seconds = Int(Double(start) / format.sampleRate)
                pieces.append("[\(YouTubeTranscript.timestamp(ms: seconds * 1000))] \(text)")
            }
            start += count
            await progress(Double(start) / Double(totalFrames))
        }
        return pieces.joined(separator: "\n")
    }

    private static func recognize(_ request: SFSpeechAudioBufferRecognitionRequest, with recognizer: SFSpeechRecognizer) async throws -> String {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func claim() -> Bool {
                lock.lock(); defer { lock.unlock() }
                if done { return false }
                done = true
                return true
            }
        }
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    if once.claim() { continuation.resume(returning: result.bestTranscription.formattedString) }
                } else if let error {
                    guard once.claim() else { return }
                    let code = (error as NSError).code
                    // 1110 = no speech detected, 1101/301 = cancelled/empty slice: not fatal.
                    if [1110, 1101, 301, 203].contains(code) {
                        continuation.resume(returning: "")
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
