import Foundation
import Security

/// Stores the user's Gemini API key in the Keychain.
enum GeminiKey {
    private static let service = "com.plawan.intelligencebook.gemini"

    static var value: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static var isSet: Bool { value != nil }

    static func save(_ key: String) {
        remove()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func remove() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
    }
}

/// Uses Google Gemini, which can watch a YouTube video directly from its URL, to get the transcript.
enum GeminiYouTube {
    /// Tried in order; the "latest" alias follows Google's current Flash model.
    private static let models = ["gemini-flash-latest", "gemini-2.5-flash"]

    private struct Response: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct APIError: Decodable { let message: String? }
        let candidates: [Candidate]?
        let error: APIError?
    }

    static func transcript(videoID: String, key: String) async throws -> String {
        let prompt = """
        Transcribe everything that is spoken in this video, word for word, in the original spoken language \
        (do not translate). Start each paragraph with a timestamp like [12:34]. \
        If there is no speech, describe the important on-screen text instead. \
        Output only the transcript, no introduction.
        """
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["file_data": ["file_uri": "https://www.youtube.com/watch?v=\(videoID)"]],
                    ["text": prompt],
                ],
            ]],
            "generationConfig": ["temperature": 0, "maxOutputTokens": 65_536],
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)

        var lastError = "Gemini ไม่ตอบกลับ"
        for model in models {
            var request = URLRequest(
                url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                timeoutInterval: 900
            )
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = payload

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let decoded = try? JSONDecoder().decode(Response.self, from: data)
            if status == 404 { lastError = decoded?.error?.message ?? "ไม่พบโมเดล \(model)"; continue }
            guard (200..<300).contains(status) else {
                let message = decoded?.error?.message ?? "HTTP \(status)"
                if status == 400 || status == 401 || status == 403, message.lowercased().contains("api key") {
                    throw AppError.message("Gemini API key ไม่ถูกต้อง — แก้ได้ในหน้าเพิ่มลิงก์ YouTube")
                }
                throw AppError.message("Gemini: \(message)")
            }
            let text = decoded?.candidates?.first?.content?.parts?.compactMap(\.text).joined() ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw AppError.message("Gemini ถอดคำพูดจากวิดีโอนี้ไม่ได้ (\(decoded?.candidates?.first?.finishReason ?? "ไม่มีข้อความ")) — วิดีโออาจเป็นส่วนตัวหรือจำกัดอายุ")
            }
            return trimmed
        }
        throw AppError.message("Gemini: \(lastError)")
    }

    /// Video title via YouTube oEmbed (no key needed).
    static func title(videoID: String) async -> String? {
        guard let url = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(videoID)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["title"] as? String
    }
}
