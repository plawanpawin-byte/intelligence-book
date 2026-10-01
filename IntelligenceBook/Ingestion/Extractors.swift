import Foundation
import PDFKit
import Vision
import UIKit

// MARK: - PDF

enum PDFExtractor {
    static func extract(url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else {
                throw AppError.message("เปิดไฟล์ PDF ไม่ได้")
            }
            var output: [String] = []
            for index in 0..<document.pageCount {
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { continue }
                var text = page.string ?? ""
                // Scanned page: fall back to on-device OCR.
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 25 {
                    text = (try? ocr(page)) ?? text
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { output.append("[หน้า \(index + 1)]\n\(trimmed)") }
            }
            return output.joined(separator: "\n\n")
        }.value
    }

    private static func ocr(_ page: PDFPage) throws -> String {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2000 / max(bounds.width, bounds.height, 1)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

// MARK: - HTML helpers

enum HTMLText {
    static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    static func replace(_ text: String, _ pattern: String, with template: String) -> String {
        let re = regex(pattern)
        return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    static func firstMatch(_ text: String, _ pattern: String, group: Int = 1) -> String? {
        let re = regex(pattern)
        guard let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > group,
              let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }

    static func decodeEntities(_ text: String) -> String {
        var s = text
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘",
            "&rdquo;": "”", "&ldquo;": "“",
        ]
        for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }
        let re = regex("&#(x?)([0-9a-f]+);")
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let isHex = ns.substring(with: m.range(at: 1)).lowercased() == "x"
            let num = ns.substring(with: m.range(at: 2))
            if let code = UInt32(num, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                result += String(Character(scalar))
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    static func plainText(fromHTML html: String) -> String {
        var s = html
        for tag in ["script", "style", "noscript", "svg", "nav", "footer", "form", "aside", "iframe", "template"] {
            s = replace(s, "<\(tag)[^>]*>.*?</\(tag)>", with: " ")
        }
        s = replace(s, "<!--.*?-->", with: " ")
        s = replace(s, "<(br|hr)[^>]*>", with: "\n")
        s = replace(s, "<li[^>]*>", with: "\n- ")
        s = replace(s, "<h([1-6])[^>]*>", with: "\n\n## ")
        s = replace(s, "</(p|div|h[1-6]|li|tr|section|article|blockquote|pre|table)>", with: "\n")
        s = replace(s, "<[^>]+>", with: "")
        s = decodeEntities(s)
        let lines = s.components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        var blank = 0
        for line in lines {
            if line.isEmpty || line == "-" || line == "##" {
                blank += 1
                if blank == 1 { out.append("") }
            } else {
                blank = 0
                out.append(line)
            }
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Web pages

enum WebExtractor {
    static let mobileSafariUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    static func fetchHTML(_ url: URL, userAgent: String = mobileSafariUA) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("th,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw AppError.message("เว็บตอบกลับ \(http.statusCode) — อาจต้องล็อกอินหรือมี paywall")
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    static func fetch(_ raw: String) async throws -> (title: String, text: String, image: String?) {
        guard let url = normalize(raw) else { throw AppError.message("ลิงก์ไม่ถูกต้อง") }
        let html = try await fetchHTML(url)

        let title = HTMLText.firstMatch(html, "<meta[^>]+property=\"og:title\"[^>]+content=\"([^\"]*)\"")
            ?? HTMLText.firstMatch(html, "<title[^>]*>(.*?)</title>")
            ?? url.host ?? raw

        // Prefer the main article body when the page marks one.
        let body = HTMLText.firstMatch(html, "<article[^>]*>(.*)</article>")
            ?? HTMLText.firstMatch(html, "<main[^>]*>(.*)</main>")
            ?? HTMLText.firstMatch(html, "<body[^>]*>(.*)</body>")
            ?? html
        var text = HTMLText.plainText(fromHTML: body)
        if text.count < 200 { text = HTMLText.plainText(fromHTML: html) }
        guard text.count > 40 else { throw AppError.message("ดึงเนื้อหาจากหน้านี้ไม่ได้ (อาจเป็นหน้าที่ต้องใช้ JavaScript)") }
        let image = (HTMLText.firstMatch(html, "<meta[^>]+property=\"og:image(?::url)?\"[^>]+content=\"([^\"]+)\"")
            ?? HTMLText.firstMatch(html, "<meta[^>]+content=\"([^\"]+)\"[^>]+property=\"og:image\"")
            ?? HTMLText.firstMatch(html, "<meta[^>]+name=\"twitter:image\"[^>]+content=\"([^\"]+)\""))
            .map(HTMLText.decodeEntities)
            .flatMap { URL(string: $0, relativeTo: url)?.absoluteString }
        return (HTMLText.decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines), text, image)
    }
}

// MARK: - YouTube

enum YouTubeTranscript {
    static func thumbnailURL(for raw: String) -> String? {
        videoID(from: raw).map { "https://i.ytimg.com/vi/\($0)/hqdefault.jpg" }
    }

    static func videoID(from raw: String) -> String? {
        guard let url = WebExtractor.normalize(raw), let host = url.host?.lowercased() else { return nil }
        if host.contains("youtu.be") {
            return url.pathComponents.dropFirst().first
        }
        guard host.contains("youtube.com") else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
            return v
        }
        let parts = url.pathComponents
        if let i = parts.firstIndex(where: { ["shorts", "embed", "live", "v"].contains($0) }), i + 1 < parts.count {
            return parts[i + 1]
        }
        return nil
    }

    private struct Track: Decodable {
        let baseUrl: String
        let languageCode: String
        let kind: String?
    }

    private struct Json3: Decodable {
        struct Event: Decodable {
            struct Seg: Decodable { let utf8: String? }
            let tStartMs: Int?
            let segs: [Seg]?
        }
        let events: [Event]?
    }

    static func fetch(_ raw: String) async throws -> (title: String, text: String) {
        guard let id = videoID(from: raw) else { throw AppError.message("ไม่พบรหัสวิดีโอ YouTube ในลิงก์นี้") }
        let page = URL(string: "https://www.youtube.com/watch?v=\(id)&hl=th")!
        let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        let html = try await WebExtractor.fetchHTML(page, userAgent: desktopUA)

        let title = HTMLText.decodeEntities(
            HTMLText.firstMatch(html, "<meta[^>]+property=\"og:title\"[^>]+content=\"([^\"]*)\"")
                ?? HTMLText.firstMatch(html, "<title[^>]*>(.*?)</title>")?.replacingOccurrences(of: " - YouTube", with: "")
                ?? "YouTube \(id)"
        )

        guard let tracksJSON = extractArray(after: "\"captionTracks\":", in: html),
              let data = tracksJSON.data(using: .utf8),
              let tracks = try? JSONDecoder().decode([Track].self, from: data),
              !tracks.isEmpty else {
            throw AppError.message("วิดีโอนี้ไม่มีคำบรรยาย (subtitle) ที่เข้าถึงได้ — คัดลอก transcript มาวางเป็น “ข้อความ” แทนได้")
        }

        let preferred = tracks.first { $0.languageCode.hasPrefix("th") && $0.kind != "asr" }
            ?? tracks.first { $0.languageCode.hasPrefix("th") }
            ?? tracks.first { $0.languageCode.hasPrefix("en") && $0.kind != "asr" }
            ?? tracks.first { $0.languageCode.hasPrefix("en") }
            ?? tracks[0]

        guard let captionURL = URL(string: preferred.baseUrl + "&fmt=json3") else {
            throw AppError.message("ลิงก์คำบรรยายไม่ถูกต้อง")
        }
        let (captionData, _) = try await URLSession.shared.data(from: captionURL)
        var lines: [String] = []
        if let json = try? JSONDecoder().decode(Json3.self, from: captionData) {
            var lastStamp = -30_000
            var buffer = ""
            for event in json.events ?? [] {
                let text = (event.segs ?? []).compactMap(\.utf8).joined()
                    .replacingOccurrences(of: "\n", with: " ")
                guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let start = event.tStartMs ?? 0
                if start - lastStamp >= 30_000 {
                    if !buffer.isEmpty { lines.append(buffer) }
                    buffer = "[\(timestamp(ms: start))] "
                    lastStamp = start
                }
                buffer += text + " "
            }
            if !buffer.isEmpty { lines.append(buffer) }
        }
        if lines.isEmpty {
            // Older XML caption format.
            let xml = String(decoding: captionData, as: UTF8.self)
            let re = HTMLText.regex("<text start=\"([0-9.]+)\"[^>]*>(.*?)</text>")
            let ns = xml as NSString
            for m in re.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
                let seconds = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let text = HTMLText.decodeEntities(HTMLText.decodeEntities(ns.substring(with: m.range(at: 2))))
                lines.append("[\(timestamp(ms: Int(seconds * 1000)))] \(text)")
            }
        }
        guard !lines.isEmpty else {
            throw AppError.message("YouTube ไม่ส่งคำบรรยายกลับมา — ลองคัดลอก transcript จากแอป YouTube มาวางเป็นข้อความ")
        }
        return (title, lines.joined(separator: "\n"))
    }

    static func timestamp(ms: Int) -> String {
        let total = ms / 1000
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// Finds `marker` and returns the balanced JSON array that follows it.
    private static func extractArray(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        var index = markerRange.upperBound
        guard index < text.endIndex, text[index] == "[" else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        let start = index
        while index < text.endIndex {
            let c = text[index]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                if c == "\"" { inString = true }
                else if c == "[" { depth += 1 }
                else if c == "]" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
