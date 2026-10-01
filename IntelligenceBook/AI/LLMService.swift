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

    /// One-shot generation in a fresh context. `onUpdate` receives the full text so far.
    func generate(
        system: String,
        prompt: String,
        maxTokens: Int,
        temperature: Float = 0.3,
        onUpdate: ((String) -> Void)? = nil
    ) async throws -> String {
        let model = try await ensureLoaded()

        var parameters = GenerateParameters()
        parameters.maxTokens = maxTokens
        parameters.temperature = temperature
        parameters.topP = 0.9
        parameters.repetitionPenalty = 1.1

        let session = ChatSession(model, instructions: system, generateParameters: parameters)
        var text = ""
        for try await chunk in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            text += chunk
            onUpdate?(text)
        }
        Memory.clearCache()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
