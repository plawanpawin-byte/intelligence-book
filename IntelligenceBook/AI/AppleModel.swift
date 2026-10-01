import Foundation
import Observation
import FoundationModels

/// Apple's on-device foundation model (Apple Intelligence, iOS 26+).
/// No download: the model ships with the OS. Context window is ~4K tokens (prompt + answer),
/// so long sources are condensed in chunks by `GenerationJob`.
@MainActor
@Observable
final class LLMService {
    static let shared = LLMService()

    static let displayName = "Apple Intelligence"

    /// Characters of source text per pass. Small because the 4K-token window holds
    /// the instructions, the source and the answer together (Thai tokenizes densely).
    static let chunkCharacters = 3_000
    static let noteMaxTokens = 1_200
    static let digestMaxTokens = 300

    /// `permissiveContentTransformations` lets the model summarise material it is given
    /// (news, lectures on sensitive topics) instead of refusing as often.
    private let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    private init() {}

    enum Status: Equatable {
        case ready
        case notEligible
        case notEnabled
        case notReady
        case other(String)
    }

    var status: Status {
        switch model.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .notEligible
            case .appleIntelligenceNotEnabled: return .notEnabled
            case .modelNotReady: return .notReady
            @unknown default: return .other(String(describing: reason))
            }
        }
    }

    var isAvailable: Bool { status == .ready }

    var statusText: String {
        switch status {
        case .ready: "พร้อมใช้งาน · ประมวลผลบนเครื่อง"
        case .notEligible: "เครื่องนี้ไม่รองรับ Apple Intelligence (ต้องเป็น iPhone 15 Pro ขึ้นไป)"
        case .notEnabled: "ยังไม่ได้เปิด Apple Intelligence — เปิดได้ที่ การตั้งค่า > Apple Intelligence และ Siri"
        case .notReady: "Apple Intelligence กำลังดาวน์โหลดโมเดล ลองใหม่อีกครั้งในไม่กี่นาที"
        case .other(let reason): "Apple Intelligence ใช้งานไม่ได้ (\(reason))"
        }
    }

    /// Whether the model officially supports the iPhone's current language.
    var supportsCurrentLanguage: Bool { model.supportsLocale() }

    /// One-shot generation in a fresh session. `onUpdate` receives the full text so far.
    func generate(
        system: String,
        prompt: String,
        maxTokens: Int,
        temperature: Double = 0.3,
        onUpdate: ((String) -> Void)? = nil
    ) async throws -> String {
        guard isAvailable else { throw AppError.message(statusText) }

        let session = LanguageModelSession(model: model, instructions: system)
        let options = GenerationOptions(temperature: temperature, maximumResponseTokens: maxTokens)
        var text = ""
        do {
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                try Task.checkCancellation()
                text = snapshot.content
                onUpdate?(text)
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw LLMError(error)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Readable (Thai) messages for Foundation Models errors.
enum LLMError: LocalizedError {
    case contextTooLong
    case unsupportedLanguage
    case guardrail
    case busy
    case other(String)

    init(_ error: LanguageModelSession.GenerationError) {
        switch error {
        case .exceededContextWindowSize: self = .contextTooLong
        case .unsupportedLanguageOrLocale: self = .unsupportedLanguage
        case .guardrailViolation: self = .guardrail
        case .rateLimited, .concurrentRequests: self = .busy
        default: self = .other(error.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextTooLong: "เนื้อหายาวเกินกว่าที่โมเดลรับได้ในครั้งเดียว"
        case .unsupportedLanguage: "Apple Intelligence ยังไม่รองรับภาษานี้ (ตอนนี้ยังไม่รองรับภาษาไทย) — ลองเลือกภาษาโน้ตเป็น English หรือใช้แหล่งข้อมูลภาษาอังกฤษ"
        case .guardrail: "Apple Intelligence ปฏิเสธเนื้อหานี้ตามนโยบายความปลอดภัย"
        case .busy: "โมเดลกำลังทำงานอื่นอยู่ ลองใหม่อีกครั้ง"
        case .other(let message): message
        }
    }
}
