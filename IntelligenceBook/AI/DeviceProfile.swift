import Foundation
import MLXLMCommon
import MLXLLM

/// Llama 3.2 sizes that run on-device (4-bit MLX weights from mlx-community).
enum LlamaVariant: String, CaseIterable, Identifiable {
    case b1 = "1b"
    case b3 = "3b"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .b1: "Llama 3.2 1B"
        case .b3: "Llama 3.2 3B"
        }
    }

    var repoID: String {
        switch self {
        case .b1: "mlx-community/Llama-3.2-1B-Instruct-4bit"
        case .b3: "mlx-community/Llama-3.2-3B-Instruct-4bit"
        }
    }

    var configuration: ModelConfiguration {
        switch self {
        case .b1: LLMRegistry.llama3_2_1B_4bit
        case .b3: LLMRegistry.llama3_2_3B_4bit
        }
    }

    /// Approximate download size.
    var downloadSize: String {
        switch self {
        case .b1: "≈ 0.7 GB"
        case .b3: "≈ 1.8 GB"
        }
    }

    /// RAM the device should have for this variant to run comfortably.
    var minimumRAMGB: Double {
        switch self {
        case .b1: 3
        case .b3: 6
        }
    }

    /// How many characters of source text we feed per pass.
    /// Thai tokenizes much denser than English, so this is conservative.
    var chunkCharacters: Int {
        switch self {
        case .b1: 5_000
        case .b3: 8_000
        }
    }

    var maxOutputTokens: Int {
        switch self {
        case .b1: 1_200
        case .b3: 1_800
        }
    }
}

/// User-facing model preference stored in Settings.
enum ModelPreference: String, CaseIterable, Identifiable {
    case auto, b1, b3
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "อัตโนมัติ (ตามเครื่อง)"
        case .b1: "1B — เร็ว ประหยัดแรม"
        case .b3: "3B — ฉลาดกว่า ช้ากว่า"
        }
    }
}

enum DeviceProfile {
    static let preferenceKey = "modelPreference"

    static var ramGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    static var processorCount: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// Picks the biggest Llama 3.2 the device can run.
    /// 8 GB devices (iPhone 15 Pro and newer, M-series iPad) → 3B, anything smaller → 1B.
    static var recommended: LlamaVariant {
        ramGB >= 7.0 ? .b3 : .b1
    }

    static var preference: ModelPreference {
        ModelPreference(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .auto
    }

    static var selected: LlamaVariant {
        switch preference {
        case .auto: recommended
        case .b1: .b1
        case .b3: .b3
        }
    }

    static var deviceSummary: String {
        String(format: "แรม %.1f GB · %d คอร์", ramGB, processorCount)
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
