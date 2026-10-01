import Foundation
import AVFoundation
import Observation

/// Records the microphone to an .m4a file with AVAudioEngine and, at the same time, transcribes it
/// in ~50 s pieces. Works with the screen locked (UIBackgroundModes: audio), so a 2–3 hour lecture
/// already has its transcript when recording stops.
@MainActor
@Observable
final class AudioRecorder {
    enum State { case idle, recording, paused }

    var state: State = .idle
    var elapsed: TimeInterval = 0
    var levels: [Float] = Array(repeating: 0, count: 48)
    /// Number of transcribed pieces so far (shown under the timer).
    var transcribedPieces = 0
    private(set) var fileName: String?

    private var engine: AVAudioEngine?
    private var writer: RecordingWriter?

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let speechAllowed = await SpeechTranscriber.requestAuthorization()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AppError.message("No microphone found") }

        let name = FileStore.newRecordingName()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(
            forWriting: FileStore.url(for: name),
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        let live = speechAllowed ? LiveTranscriber(locale: .current, sampleRate: format.sampleRate) : nil
        let writer = RecordingWriter(file: file, live: live) { [weak self] level, seconds, pieces in
            Task { @MainActor in self?.update(level: level, seconds: seconds, pieces: pieces) }
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            writer.append(buffer)
        }
        engine.prepare()
        try engine.start()

        self.engine = engine
        self.writer = writer
        fileName = name
        elapsed = 0
        transcribedPieces = 0
        state = .recording
    }

    func pause() {
        engine?.pause()
        state = .paused
        levels.removeFirst()
        levels.append(0.04)
    }

    func resume() {
        try? engine?.start()
        state = .recording
    }

    /// Stops recording and returns the file name plus the live transcript (if speech recognition was allowed).
    func stop() async -> (fileName: String, transcript: String?)? {
        guard let engine, let name = fileName else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        let transcript = await writer?.finish()
        writer = nil
        fileName = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (name, transcript)
    }

    func discard() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        writer?.cancel()
        writer = nil
        FileStore.delete(fileName)
        fileName = nil
        state = .idle
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func update(level: Float, seconds: TimeInterval, pieces: Int) {
        guard state != .idle else { return }
        elapsed = seconds
        transcribedPieces = pieces
        levels.removeFirst()
        levels.append(state == .recording ? level : 0.04)
    }
}

/// Runs on the audio thread: writes buffers to the file and forwards them to the transcriber.
final class RecordingWriter: @unchecked Sendable {
    private let file: AVAudioFile
    private let live: LiveTranscriber?
    private let report: (Float, TimeInterval, Int) -> Void
    private let lock = NSLock()
    private var frames: AVAudioFramePosition = 0
    private var lastReport: AVAudioFramePosition = 0
    private var closed = false

    init(file: AVAudioFile, live: LiveTranscriber?, report: @escaping (Float, TimeInterval, Int) -> Void) {
        self.file = file
        self.live = live
        self.report = report
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        try? file.write(from: buffer)
        frames += AVAudioFramePosition(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        let shouldReport = frames - lastReport > AVAudioFramePosition(sampleRate * 0.08)
        if shouldReport { lastReport = frames }
        let seconds = Double(frames) / sampleRate
        lock.unlock()

        live?.append(buffer)
        if shouldReport {
            report(Self.level(of: buffer), seconds, live?.finishedPieces ?? 0)
        }
    }

    func finish() async -> String? {
        lock.lock(); closed = true; lock.unlock()
        return await live?.finish()
    }

    func cancel() {
        lock.lock(); closed = true; lock.unlock()
        live?.cancel()
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0.04 }
        var sum: Float = 0
        let n = Int(buffer.frameLength)
        for i in stride(from: 0, to: n, by: 4) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(max(1, n / 4)))
        let db = 20 * log10(max(rms, 0.000_01))
        return max(0.04, min(1, (db + 55) / 55))
    }
}

@MainActor
@Observable
final class AudioPlayer {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var rate: Float = 1 {
        didSet { player?.rate = rate }
    }

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(_ url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.rate = rate
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let player = self.player else { return }
                    self.currentTime = player.currentTime
                    if !player.isPlaying { self.isPlaying = false; self.timer?.invalidate() }
                }
            }
        }
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func skip(_ delta: TimeInterval) {
        seek(to: min(max(0, currentTime + delta), duration))
    }

    func stop() {
        player?.stop()
        timer?.invalidate()
        isPlaying = false
    }
}

extension TimeInterval {
    var clockString: String {
        let total = Int(self)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
