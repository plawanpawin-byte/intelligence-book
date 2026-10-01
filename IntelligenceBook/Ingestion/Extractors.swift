import Foundation
import PDFKit
import Vision
import UIKit

// MARK: - PDF

enum PDFExtractor {
    static func extract(url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else {
                throw AppError.message("Couldn’t open the PDF")
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
                if !trimmed.isEmpty { output.append("[Page \(index + 1)]\n\(trimmed)") }
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
            throw AppError.message("The site returned \(http.statusCode) — it may need a login or have a paywall")
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    static func fetch(_ raw: String) async throws -> (title: String, text: String, image: String?) {
        guard let url = normalize(raw) else { throw AppError.message("Invalid link") }
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
        guard text.count > 40 else { throw AppError.message("Couldn’t read this page (it may need JavaScript)") }
        let image = (HTMLText.firstMatch(html, "<meta[^>]+property=\"og:image(?::url)?\"[^>]+content=\"([^\"]+)\"")
            ?? HTMLText.firstMatch(html, "<meta[^>]+content=\"([^\"]+)\"[^>]+property=\"og:image\"")
            ?? HTMLText.firstMatch(html, "<meta[^>]+name=\"twitter:image\"[^>]+content=\"([^\"]+)\""))
            .map(HTMLText.decodeEntities)
            .flatMap { URL(string: $0, relativeTo: url)?.absoluteString }
        return (HTMLText.decodeEntities(title).trimmingCharacters(in: .whitespacesAndNewlines), text, image)
    }
}

// MARK: - Timestamps

enum Timestamp {
    static func string(ms: Int) -> String {
        let total = ms / 1000
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
