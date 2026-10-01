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

    private static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    private static let androidVersion = "20.10.38"

    /// Gets the transcript straight from YouTube, trying three independent routes:
    /// 1. InnerTube player API as the Android app → caption track (same as youtube-transcript-api)
    /// 2. The "Show transcript" panel API (get_transcript) the website uses
    /// 3. Caption tracks embedded in the watch page
    static func fetch(_ raw: String) async throws -> (title: String, text: String) {
        guard let id = videoID(from: raw) else { throw AppError.message("ไม่พบรหัสวิดีโอ YouTube ในลิงก์นี้") }
        let html = (try? await watchPage(id)) ?? ""
        let title = HTMLText.decodeEntities(
            HTMLText.firstMatch(html, "<meta[^>]+property=\"og:title\"[^>]+content=\"([^\"]*)\"")
                ?? HTMLText.firstMatch(html, "<title[^>]*>(.*?)</title>")?.replacingOccurrences(of: " - YouTube", with: "")
                ?? "YouTube \(id)"
        )

        if let text = try? await viaAndroidPlayer(id: id, html: html), !text.isEmpty { return (title, text) }
        if !html.isEmpty, let text = try? await viaTranscriptPanel(html: html), !text.isEmpty { return (title, text) }
        if !html.isEmpty, let tracks = tracks(fromJSONText: html), let text = try? await download(pick(tracks)), !text.isEmpty {
            return (title, text)
        }
        throw AppError.message("ดึง transcript จาก YouTube ไม่ได้ — วิดีโออาจไม่มีคำบรรยาย หรือเป็นวิดีโอส่วนตัว/จำกัดอายุ")
    }

    private static func watchPage(_ id: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(id)&hl=th")!, timeoutInterval: 30)
        request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        request.setValue("th,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.setValue("CONSENT=YES+cb; SOCS=CAI", forHTTPHeaderField: "Cookie")
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }

    private static func postJSON(_ url: URL, body: [String: Any], headers: [String: String]) async throws -> Any {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CONSENT=YES+cb; SOCS=CAI", forHTTPHeaderField: "Cookie")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.message("YouTube HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: Route 1 — InnerTube player (Android client)

    private static func viaAndroidPlayer(id: String, html: String) async throws -> String? {
        let apiKey = HTMLText.firstMatch(html, "\"INNERTUBE_API_KEY\":\\s*\"([a-zA-Z0-9_-]+)\"")
        var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/player")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")] + (apiKey.map { [URLQueryItem(name: "key", value: $0)] } ?? [])
        let json = try await postJSON(components.url!, body: [
            "context": ["client": [
                "clientName": "ANDROID",
                "clientVersion": androidVersion,
                "androidSdkVersion": 30,
                "hl": "th",
                "gl": "TH",
            ]],
            "videoId": id,
        ], headers: [
            "User-Agent": "com.google.android.youtube/\(androidVersion) (Linux; U; Android 11) gzip",
            "X-YouTube-Client-Name": "3",
            "X-YouTube-Client-Version": androidVersion,
        ])
        guard let tracks = JSONWalk.first(key: "captionTracks", in: json) as? [[String: Any]] else { return nil }
        let parsed = tracks.compactMap(Track.init(json:))
        guard !parsed.isEmpty else { return nil }
        return try await download(pick(parsed))
    }

    // MARK: Route 2 — "Show transcript" panel

    private static func viaTranscriptPanel(html: String) async throws -> String? {
        guard let params = HTMLText.firstMatch(html, "\"getTranscriptEndpoint\":\\{\"params\":\"([^\"]+)\"") else { return nil }
        let version = HTMLText.firstMatch(html, "\"INNERTUBE_CONTEXT_CLIENT_VERSION\":\"([^\"]+)\"") ?? "2.20250101.00.00"
        let apiKey = HTMLText.firstMatch(html, "\"INNERTUBE_API_KEY\":\\s*\"([a-zA-Z0-9_-]+)\"")
        var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/get_transcript")!
        components.queryItems = [URLQueryItem(name: "prettyPrint", value: "false")] + (apiKey.map { [URLQueryItem(name: "key", value: $0)] } ?? [])
        let json = try await postJSON(components.url!, body: [
            "context": ["client": ["clientName": "WEB", "clientVersion": version, "hl": "th", "gl": "TH"]],
            "params": params.replacingOccurrences(of: "\\u003d", with: "="),
        ], headers: [
            "User-Agent": desktopUA,
            "Origin": "https://www.youtube.com",
            "X-YouTube-Client-Name": "1",
            "X-YouTube-Client-Version": version,
        ])
        let segments = JSONWalk.all(key: "transcriptSegmentRenderer", in: json)
        var items: [(Int, String)] = []
        for case let segment as [String: Any] in segments {
            let start = Int(segment["startMs"] as? String ?? "") ?? 0
            let runs = (segment["snippet"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
            let text = runs.compactMap { $0["text"] as? String }.joined()
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { items.append((start, text)) }
        }
        return items.isEmpty ? nil : group(items)
    }

    // MARK: Caption tracks

    private struct Track {
        let baseUrl: String
        let languageCode: String
        let kind: String?

        init?(json: [String: Any]) {
            guard let url = json["baseUrl"] as? String else { return nil }
            baseUrl = url
            languageCode = json["languageCode"] as? String ?? ""
            kind = json["kind"] as? String
        }
    }

    private static func tracks(fromJSONText html: String) -> [Track]? {
        guard let array = extractArray(after: "\"captionTracks\":", in: html),
              let data = array.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let tracks = json.compactMap(Track.init(json:))
        return tracks.isEmpty ? nil : tracks
    }

    /// Thai first, then English; human captions before auto-generated ones.
    private static func pick(_ tracks: [Track]) -> Track {
        tracks.first { $0.languageCode.hasPrefix("th") && $0.kind != "asr" }
            ?? tracks.first { $0.languageCode.hasPrefix("th") }
            ?? tracks.first { $0.languageCode.hasPrefix("en") && $0.kind != "asr" }
            ?? tracks.first { $0.languageCode.hasPrefix("en") }
            ?? tracks[0]
    }

    /// Downloads a caption track and turns it into timestamped paragraphs (XML formats srv1/srv3, or json3).
    private static func download(_ track: Track) async throws -> String? {
        let base = track.baseUrl
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "&fmt=srv3", with: "")
        guard let url = URL(string: base) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(desktopUA, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let body = String(decoding: data, as: UTF8.self)
        var items: [(Int, String)] = []

        // srv1: <text start="1.23" dur="..">…</text>
        let srv1 = HTMLText.regex("<text start=\"([0-9.]+)\"[^>]*>([\\s\\S]*?)</text>")
        let ns = body as NSString
        for m in srv1.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let seconds = Double(ns.substring(with: m.range(at: 1))) ?? 0
            items.append((Int(seconds * 1000), cleanCaption(ns.substring(with: m.range(at: 2)))))
        }
        // srv3: <p t="1230" d="..">…</p>
        if items.isEmpty {
            let srv3 = HTMLText.regex("<p t=\"([0-9]+)\"[^>]*>([\\s\\S]*?)</p>")
            for m in srv3.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                let ms = Int(ns.substring(with: m.range(at: 1))) ?? 0
                items.append((ms, cleanCaption(ns.substring(with: m.range(at: 2)))))
            }
        }
        // json3
        if items.isEmpty, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let events = json["events"] as? [[String: Any]] {
            for event in events {
                let segs = event["segs"] as? [[String: Any]] ?? []
                let text = segs.compactMap { $0["utf8"] as? String }.joined()
                items.append((event["tStartMs"] as? Int ?? 0, text))
            }
        }
        items = items.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return items.isEmpty ? nil : group(items)
    }

    private static func cleanCaption(_ raw: String) -> String {
        let noTags = HTMLText.replace(raw, "<[^>]+>", with: "")
        return HTMLText.decodeEntities(HTMLText.decodeEntities(noTags)).replacingOccurrences(of: "\n", with: " ")
    }

    /// Joins caption lines into ~30 s paragraphs with a timestamp each.
    private static func group(_ items: [(Int, String)]) -> String {
        var lines: [String] = []
        var buffer = ""
        var lastStamp = -30_000
        for (start, text) in items {
            if start - lastStamp >= 30_000 {
                if !buffer.isEmpty { lines.append(buffer.trimmingCharacters(in: .whitespaces)) }
                buffer = "[\(timestamp(ms: start))] "
                lastStamp = start
            }
            buffer += text.trimmingCharacters(in: .whitespaces) + " "
        }
        if !buffer.isEmpty { lines.append(buffer.trimmingCharacters(in: .whitespaces)) }
        return lines.joined(separator: "\n")
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

/// Small helpers to find values deep inside YouTube's JSON responses.
enum JSONWalk {
    static func first(key: String, in value: Any) -> Any? {
        if let dict = value as? [String: Any] {
            if let found = dict[key] { return found }
            for child in dict.values { if let found = first(key: key, in: child) { return found } }
        } else if let array = value as? [Any] {
            for child in array { if let found = first(key: key, in: child) { return found } }
        }
        return nil
    }

    static func all(key: String, in value: Any) -> [Any] {
        var out: [Any] = []
        func walk(_ v: Any) {
            if let dict = v as? [String: Any] {
                for (k, child) in dict {
                    if k == key { out.append(child) } else { walk(child) }
                }
            } else if let array = v as? [Any] {
                array.forEach(walk)
            }
        }
        walk(value)
        return out
    }
}
