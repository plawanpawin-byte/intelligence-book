import Foundation
import Observation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Runs Llama 3.2 fully on-device with MLX. Downloads weights from Hugging Face on first use.
@MainActor
@Observable
final class LLMService {
    static let shared = LLMService()

    enum LoadState: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready(LlamaVariant)
        case failed(String)
    }

    var state: LoadState = .idle

    private var container: ModelContainer?
    private(set) var loadedVariant: LlamaVariant?
    private var loadTask: Task<ModelContainer, Error>?

    private init() {}

    var statusText: String {
        switch state {
        case .idle: "ยังไม่ได้โหลด"
        case .downloading(let p): "กำลังดาวน์โหลด \(Int(p * 100))%"
        case .loading: "กำลังโหลดเข้าหน่วยความจำ"
        case .ready(let v): "\(v.displayName) พร้อมใช้งาน"
        case .failed(let m): "ผิดพลาด: \(m)"
        }
    }

    /// Loads (and downloads if needed) the model chosen for this device.
    func ensureLoaded() async throws -> ModelContainer {
        let variant = DeviceProfile.selected
        if let container, loadedVariant == variant { return container }
        if let loadTask { return try await loadTask.value }

        // Release a previously loaded size before loading another one.
        container = nil
        loadedVariant = nil
        Memory.cacheLimit = 32 * 1024 * 1024

        state = DeviceProfile.isDownloaded(variant) ? .loading : .downloading(0)

        let task = Task<ModelContainer, Error> {
            try await LLMModelFactory.shared.loadContainer(
                from: #hubDownloader(),
                using: #huggingFaceTokenizerLoader(),
                configuration: variant.configuration,
                progressHandler: { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        LLMService.shared.reportDownload(fraction)
                    }
                }
            )
        }
        loadTask = task
        defer { loadTask = nil }

        do {
            let loaded = try await task.value
            container = loaded
            loadedVariant = variant
            state = .ready(variant)
            return loaded
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    fileprivate func reportDownload(_ fraction: Double) {
        guard case .downloading = state else { return }
        state = fraction >= 0.999 ? .loading : .downloading(fraction)
    }

    func unload() {
        container = nil
        loadedVariant = nil
        state = .idle
        Memory.clearCache()
    }

    /// Loads the model in the background (e.g. while a recording is transcribed) so the
    /// note starts writing immediately. Only when the weights are already downloaded.
    func prewarm() {
        guard container == nil, loadTask == nil, DeviceProfile.isDownloaded(DeviceProfile.selected) else { return }
        Task { _ = try? await ensureLoaded() }
    }

    /// One-shot generation in a fresh context. `onUpdate` receives the full text so far.
    /// Stops early when the model starts looping (small models repeat the same line forever).
    func generate(
        system: String,
        prompt: String,
        maxTokens: Int,
        temperature: Float = 0.4,
        onUpdate: ((String) -> Void)? = nil
    ) async throws -> String {
        let model = try await ensureLoaded()

        var parameters = GenerateParameters()
        parameters.maxTokens = maxTokens
        parameters.temperature = temperature
        parameters.topP = 0.9
        parameters.repetitionPenalty = 1.15
        parameters.repetitionContextSize = 128

        let session = ChatSession(model, instructions: system, generateParameters: parameters)
        var text = ""
        var lastCheck = 0
        for try await chunk in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            text += chunk
            onUpdate?(text)
            if text.count - lastCheck > 40 {
                lastCheck = text.count
                if RepetitionGuard.isLooping(text) { break }
            }
        }
        Memory.clearCache()
        return RepetitionGuard.clean(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Detects and removes the "same line again and again" failure of small models.
enum RepetitionGuard {
    private static func key(_ line: String) -> String {
        line.lowercased().filter { !$0.isWhitespace && !"-*>#=•".contains($0) }
    }

    /// True when a non-trivial line has already appeared 3+ times, or the tail repeats itself.
    static func isLooping(_ text: String) -> Bool {
        var counts: [String: Int] = [:]
        for line in text.components(separatedBy: "\n") {
            let k = key(line)
            guard k.count >= 8 else { continue }
            counts[k, default: 0] += 1
            if counts[k]! >= 3 { return true }
        }
        // A phrase repeating inside one long line ("A เพราะ B A เพราะ B A เพราะ B").
        let tail = String(text.suffix(240))
        if tail.count == 240 {
            for size in stride(from: 12, through: 80, by: 4) {
                let unit = String(tail.suffix(size))
                if tail.hasSuffix(String(repeating: unit, count: 3)) { return true }
            }
        }
        return false
    }

    /// Drops lines/paragraphs that duplicate an earlier one and trims a repeated tail.
    static func clean(_ text: String) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            let k = key(line)
            if k.count >= 8 {
                if seen.contains(k) { continue }
                seen.insert(k)
            }
            out.append(line)
        }
        var result = out.joined(separator: "\n")
        // Collapse runs of blank lines left behind.
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        // Remove empty headings / callouts at the very end (cut-off output).
        var lines = result.components(separatedBy: "\n")
        while let last = lines.last?.trimmingCharacters(in: .whitespaces),
              last.isEmpty || last.hasPrefix("#") || last == ">" || last.hasPrefix("> [!") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }
}
