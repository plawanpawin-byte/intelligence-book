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
        case .idle: "Not loaded"
        case .downloading(let p): "Downloading model \(Int(p * 100))%"
        case .loading: "Loading model into memory"
        case .ready(let v): "\(v.displayName) ready"
        case .failed(let m): "Error: \(m)"
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
    /// With `continueIfCut`, a note that hits the token limit mid-sentence is continued (up to twice)
    /// instead of ending abruptly.
    func generate(
        system: String,
        prompt: String,
        maxTokens: Int,
        temperature: Float = 0.4,
        continueIfCut: Bool = false,
        onUpdate: ((String) -> Void)? = nil
    ) async throws -> String {
        var (text, cut) = try await stream(system: system, prompt: prompt, maxTokens: maxTokens, temperature: temperature, prefix: "", onUpdate: onUpdate)
        var passes = 0
        while cut && continueIfCut && passes < 2 {
            passes += 1
            let continuation = """
            \(prompt)

            ---
            THE NOTE WRITTEN SO FAR (it was cut off because of length):
            \(text)
            ---
            Continue the note from exactly where it stops. Do not repeat anything already written. \
            Output only the continuation text.
            """
            let joiner = text.hasSuffix("\n") ? "" : (text.last?.isWhitespace == true ? "" : " ")
            let (more, stillCut) = try await stream(
                system: system, prompt: continuation, maxTokens: maxTokens, temperature: temperature,
                prefix: text + joiner, onUpdate: onUpdate
            )
            text += joiner + more
            cut = stillCut
        }
        Memory.clearCache()
        return RepetitionGuard.clean(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Streams one reply. Returns the text and whether it stopped because of the token limit.
    private func stream(
        system: String,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        prefix: String,
        onUpdate: ((String) -> Void)?
    ) async throws -> (String, Bool) {
        let model = try await ensureLoaded()

        var parameters = GenerateParameters()
        parameters.maxTokens = maxTokens
        parameters.temperature = temperature
        parameters.topP = 0.9
        parameters.repetitionPenalty = 1.1
        parameters.repetitionContextSize = 96

        let session = ChatSession(model, instructions: system, generateParameters: parameters)
        var text = ""
        var lastCheck = 0
        var hitLimit = false
        for try await event in session.streamDetails(to: prompt) {
            try Task.checkCancellation()
            switch event {
            case .chunk(let chunk):
                text += chunk
                onUpdate?(prefix + text)
                if text.count - lastCheck > 40 {
                    lastCheck = text.count
                    if RepetitionGuard.isLooping(text) { return (text, false) }
                }
            case .info(let info):
                hitLimit = info.stopReason == .length
            default:
                break
            }
        }
        return (text, hitLimit)
    }
}

/// Detects and removes the "same line again and again" failure of small models.
enum RepetitionGuard {
    private static func key(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Headings, callout headers and table rows legitimately repeat ("> [!tip] Key point").
        if trimmed.hasPrefix("#") || trimmed.hasPrefix("> [!") || trimmed.hasPrefix("|") || trimmed.hasPrefix("```") {
            return ""
        }
        return line.lowercased().filter { !$0.isWhitespace && !"-*>#=•".contains($0) }
    }

    /// True when a non-trivial line has already appeared 3+ times, or the tail repeats itself.
    static func isLooping(_ text: String) -> Bool {
        var counts: [String: Int] = [:]
        for line in text.components(separatedBy: "\n") {
            let k = key(line)
            guard k.count >= 16 else { continue }
            counts[k, default: 0] += 1
            if counts[k]! >= 3 { return true }
        }
        // A phrase repeating inside one long line ("A because B A because B A because B").
        let tail = String(text.suffix(300))
        if tail.count == 300 {
            for size in stride(from: 20, through: 100, by: 1) {
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
            if k.count >= 16 {
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
