import Foundation
import MLXLMCommon
import MLXLLM

/// Llama 3.2 sizes that run on-device (4-bit MLX weights from mlx-community).
enum LlamaVariant: String, CaseIterable, Identifiable {
    case b1 = "1b"
    case b3 = "3b"
    /// Qwen3 1.7B — for 4 GB iPhones (iPhone 13 and older), where the 3B model runs out of memory.
    case qwen17 = "qwen3-1.7b"

    var id: String { rawValue }

    var isQwen: Bool { self == .qwen17 }

    var displayName: String {
        switch self {
        case .b1: "Apple Foundation Models 1B"
        case .b3: "Apple Foundation Models 3B"
        case .qwen17: "Apple Foundation Models 1.7B"
        }
    }

    var repoID: String {
        switch self {
        case .b1: "mlx-community/Llama-3.2-1B-Instruct-4bit"
        case .b3: "mlx-community/Llama-3.2-3B-Instruct-4bit"
        case .qwen17: "mlx-community/Qwen3-1.7B-4bit"
        }
    }

    var configuration: ModelConfiguration {
        switch self {
        case .b1: LLMRegistry.llama3_2_1B_4bit
        case .b3: LLMRegistry.llama3_2_3B_4bit
        case .qwen17: LLMRegistry.qwen3_1_7b_4bit
        }
    }

    /// Approximate download size.
    var downloadSize: String {
        switch self {
        case .b1: "≈ 0.7 GB"
        case .b3: "≈ 1.8 GB"
        case .qwen17: "≈ 1.0 GB"
        }
    }

    /// RAM the device should have for this variant to run comfortably.
    var minimumRAMGB: Double {
        switch self {
        case .b1: 3
        case .b3: 6
        case .qwen17: 4
        }
    }

    /// How many characters of source text we feed per pass.
    /// Thai tokenizes much denser than English, so this is conservative.
    var chunkCharacters: Int {
        switch self {
        case .b1: 6_000
        case .b3, .qwen17: 10_000
        }
    }

    var maxOutputTokens: Int {
        switch self {
        case .b1: 1_500
        case .b3, .qwen17: 2_200
        }
    }
}

enum DeviceProfile {
    static var ramGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    static var processorCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// Llama 3.2 3B ("Apple Foundation Models 3B") on every iPhone. (Qwen3 1.7B was tried for 4 GB phones and
    /// invented far more than 3B in the note evaluation, so it is not used.)
    static let selected: LlamaVariant = .b3

    /// 4 GB iPhones (iPhone 13 and older): the 3B model only just fits, so the pipeline uses less memory there.
    static var isLowMemory: Bool { ramGB < 5 }

    /// Frees the space of a 1B model downloaded by older builds.
    static func removeUnusedDownloads() {
        for variant in LlamaVariant.allCases where variant != selected {
            deleteDownload(variant)
        }
    }

    static var deviceSummary: String {
        String(format: "%.1f GB RAM · %d cores", ramGB, processorCount)
    }

    // MARK: Model cache on disk (swift-huggingface cache: Library/Caches/huggingface/hub)

    static var hubCacheDirectory: URL {
        URL.cachesDirectory.appendingPathComponent("huggingface/hub", isDirectory: true)
    }

    static func cacheFolders(for variant: LlamaVariant) -> [URL] {
        let fm = FileManager.default
        let needle = variant.repoID.components(separatedBy: "/").last ?? variant.repoID
        var found: [URL] = []
        guard let enumerator = fm.enumerator(
            at: URL.cachesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        for case let url as URL in enumerator {
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            if url.lastPathComponent.contains(needle) {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        return found
    }

    static func isDownloaded(_ variant: LlamaVariant) -> Bool {
        cacheFolders(for: variant).contains { folder in
            let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
            while let next = enumerator?.nextObject() as? URL {
                if next.pathExtension == "safetensors" { return true }
            }
            return false
        }
    }

    static func deleteDownload(_ variant: LlamaVariant) {
        for folder in cacheFolders(for: variant) {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
