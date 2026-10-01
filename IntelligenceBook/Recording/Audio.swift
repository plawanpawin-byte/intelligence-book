import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class AudioRecorder {
    enum State { case idle, recording, paused }

    var state: State = .idle
    var elapsed: TimeInterval = 0
    var levels: [Float] = Array(repeating: 0, count: 48)
    private(set) var fileName: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let name = FileStore.newRecordingName()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: FileStore.url(for: name), settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw AppError.message("เริ่มอัดเสียงไม่ได้") }
        self.recorder = recorder
        fileName = name
        state = .recording
        startTimer()
    }

    func pause() {
        recorder?.pause()
        state = .paused
    }

    func resume() {
        recorder?.record()
        state = .recording
    }

    /// Stops and returns the stored file name.
    func stop() -> String? {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { fileName = nil }
        return fileName
    }

    func discard() {
        let name = stop()
        FileStore.delete(name)
        elapsed = 0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let recorder else { return }
        elapsed = recorder.currentTime > 0 ? recorder.currentTime : elapsed
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let level = state == .recording ? max(0.04, min(1, (power + 55) / 55)) : 0.04
        levels.removeFirst()
        levels.append(level)
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
