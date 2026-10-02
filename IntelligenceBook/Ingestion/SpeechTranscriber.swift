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
        case .thai: "Thai"
        case .english: "English (US)"
        case .englishUK: "English (UK)"
        case .japanese: "日本語"
        case .chinese: "中文"
        }
    }

    var shortLabel: String {
        switch self {
        case .thai: "TH"
        case .english: "EN"
        case .englishUK: "UK"
        case .japanese: "日本"
        case .chinese: "中文"
        }
    }

    /// v2 key: the old default followed the iPhone language (English UI → Thai speech became gibberish).
    static let storageKey = "speechLocale.v2"
    /// Thai unless the user picked another language on the recording screen.
    static var current: SpeechLocale {
        if let saved = UserDefaults.standard.string(forKey: storageKey), let locale = SpeechLocale(rawValue: saved) {
            return locale
        }
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
            throw AppError.message("Speech Recognition isn’t allowed — turn it on in Settings > IntelligenceBook")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale.rawValue)) else {
            throw AppError.message("This device can’t transcribe \(locale.label)")
        }
        guard recognizer.isAvailable else {
            throw AppError.message("Speech recognition isn’t available right now (check your internet connection)")
        }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0 else { throw AppError.message("The audio file is empty") }
        let sliceFrames = AVAudioFramePosition(format.sampleRate * 50)

        var pieces: [String] = []
        var start: AVAudioFramePosition = 0
        // Apple's server recognizer is clearly more accurate (especially for Thai) than the on-device one;
        // fall back to on-device when the server fails (offline, daily limit).
        var onDevice = false
        while start < totalFrames {
            try Task.checkCancellation()
            let count = min(sliceFrames, totalFrames - start)
            file.framePosition = start

            var buffers: [AVAudioPCMBuffer] = []
            var remaining = count
            while remaining > 0 {
                let frames = AVAudioFrameCount(min(remaining, 16_384))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { break }
                try file.read(into: buffer, frameCount: frames)
                if buffer.frameLength == 0 { break }
                buffers.append(buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }

            func makeRequest(onDevice: Bool) -> SFSpeechAudioBufferRecognitionRequest {
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = false
                request.addsPunctuation = true
                request.taskHint = .dictation
                request.requiresOnDeviceRecognition = onDevice
                buffers.forEach { request.append($0) }
                request.endAudio()
                return request
            }

            var text: String
            do {
                text = try await recognize(makeRequest(onDevice: onDevice), with: recognizer)
            } catch where !onDevice && recognizer.supportsOnDeviceRecognition {
                onDevice = true
                text = try await recognize(makeRequest(onDevice: true), with: recognizer)
            }
            if !text.isEmpty {
                let seconds = Int(Double(start) / format.sampleRate)
                pieces.append("[\(Timestamp.string(ms: seconds * 1000))] \(text)")
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

/// Transcribes microphone audio while it is being recorded, restarting the recognizer every ~50 s
/// (Apple's per-request limit). Thread-safe: `append` is called from the audio thread.
final class LiveTranscriber: @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer?
    private let sampleRate: Double
    private let segmentFrames: AVAudioFramePosition
    private let lock = NSLock()

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tasks: [SFSpeechRecognitionTask] = []
    private var frames: AVAudioFramePosition = 0
    private var segmentStart: AVAudioFramePosition = 0
    private var nextIndex = 0
    private var texts: [Int: (start: Double, text: String)] = [:]
    private var done: Set<Int> = []
    private var cancelled = false
    /// Server recognition first (more accurate); switches to on-device after a server failure.
    private var onDevice = false

    init(locale: SpeechLocale, sampleRate: Double) {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale.rawValue))
        recognizer?.queue = OperationQueue()
        self.recognizer = (recognizer?.isAvailable ?? false) ? recognizer : nil
        self.sampleRate = sampleRate
        self.segmentFrames = AVAudioFramePosition(sampleRate * 50)
    }

    var finishedPieces: Int {
        lock.lock(); defer { lock.unlock() }
        return done.count
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let recognizer else { return }
        lock.lock()
        if cancelled { lock.unlock(); return }
        if request == nil { startSegment(recognizer) }
        let current = request
        frames += AVAudioFramePosition(buffer.frameLength)
        let rollOver = frames - segmentStart >= segmentFrames
        if rollOver { request = nil }
        lock.unlock()

        current?.append(buffer)
        if rollOver { current?.endAudio() }
    }

    /// Must be called with the lock held.
    private func startSegment(_ recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = onDevice && recognizer.supportsOnDeviceRecognition
        let index = nextIndex
        nextIndex += 1
        segmentStart = frames
        texts[index] = (Double(frames) / sampleRate, "")
        self.request = request
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            if let result {
                texts[index]?.text = result.bestTranscription.formattedString
                if result.isFinal { done.insert(index) }
            }
            if let error {
                done.insert(index)
                let code = (error as NSError).code
                if ![1110, 1101, 301, 203, 216].contains(code), recognizer.supportsOnDeviceRecognition { onDevice = true }
            }
        }
        tasks.append(task)
    }

    /// Ends the last piece and waits (up to ~20 s) for pending pieces, then returns the timestamped transcript.
    func finish() async -> String? {
        lock.lock()
        let last = request
        request = nil
        lock.unlock()
        last?.endAudio()

        guard recognizer != nil else { return nil }
        for _ in 0..<100 {
            lock.lock()
            let pending = nextIndex - done.count
            lock.unlock()
            if pending <= 0 { break }
            try? await Task.sleep(for: .milliseconds(200))
        }

        lock.lock()
        let pieces = texts.sorted { $0.key < $1.key }.map { $0.value }
        lock.unlock()
        let lines = pieces.compactMap { piece -> String? in
            let text = piece.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "[\(Timestamp.string(ms: Int(piece.start * 1000)))] \(text)"
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let all = tasks
        request = nil
        lock.unlock()
        all.forEach { $0.cancel() }
    }
}
