import Foundation
import UIKit

/// Builds the files handed to the iOS share sheet (Obsidian, Canva, Notes, Files, AirDrop …).
@MainActor
enum NoteExporter {
    // MARK: Markdown (Obsidian)

    static func markdown(for note: Note) -> String {
        let iso = ISO8601DateFormatter().string(from: note.createdAt)
        let sources = note.sourceTitles.map { "  - \"\(yamlEscape($0))\"" }.joined(separator: "\n")
        return """
        ---
        title: "\(yamlEscape(note.title))"
        created: \(iso)
        type: \(note.style.rawValue)
        generator: IntelligenceBook (\(note.modelName))
        tags:
          - intelligencebook
        sources:
        \(sources.isEmpty ? "  []" : sources)
        ---

        \(note.markdown)
        """
    }

    private static func yamlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func fileName(for note: Note, ext: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:#^[]")
        let base = note.title.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(base.isEmpty ? "IntelligenceBook Note" : String(base.prefix(80))).\(ext)"
    }

    private static func exportDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func markdownFile(for note: Note) throws -> URL {
        let url = exportDirectory().appendingPathComponent(fileName(for: note, ext: "md"))
        try markdown(for: note).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Plain text (Notes, Messages)

    static func plainText(for note: Note) -> String {
        var out: [String] = []
        func render(_ blocks: [NoteBlock], prefix: String = "") {
            for block in blocks {
                switch block.kind {
                case .heading(_, let text): out.append(""); out.append(prefix + InlineMarkdown.plain(text).uppercased())
                case .paragraph(let text): out.append(prefix + InlineMarkdown.plain(text))
                case .bullet(let text, let indent):
                    out.append(prefix + String(repeating: "  ", count: indent) + "• " + InlineMarkdown.plain(text))
                case .numbered(let n, let text, let indent):
                    out.append(prefix + String(repeating: "  ", count: indent) + "\(n). " + InlineMarkdown.plain(text))
                case .task(let text, let done, let indent):
                    out.append(prefix + String(repeating: "  ", count: indent) + (done ? "☑︎ " : "☐ ") + InlineMarkdown.plain(text))
                case .quote(let text): out.append(prefix + "“" + InlineMarkdown.plain(text) + "”")
                case .callout(let kind, let title, let children):
                    out.append("")
                    out.append(prefix + "▍" + (title.isEmpty ? kind.defaultTitle : InlineMarkdown.plain(title)))
                    render(children, prefix: prefix + "▍ ")
                case .code(_, let code): out.append(code)
                case .table(let rows): rows.forEach { out.append(prefix + $0.map(InlineMarkdown.plain).joined(separator: " | ")) }
                case .divider: out.append("———")
                }
            }
        }
        render(NoteParser.parse(note.markdown))
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: HTML → PDF (Canva, Notes, Files)

    static func html(for note: Note) -> String {
        let body = NoteHTML.render(NoteParser.parse(note.markdown))
        return """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, "Helvetica Neue", "Thonburi", sans-serif; font-size: 12.5pt; line-height: 1.55; color: #1c1c1e; }
        h1 { font-size: 24pt; margin: 0 0 6pt; } h2 { font-size: 17pt; margin: 16pt 0 4pt; } h3 { font-size: 14pt; margin: 12pt 0 4pt; }
        h4,h5,h6 { font-size: 12.5pt; margin: 10pt 0 2pt; }
        p { margin: 4pt 0; } ul, ol { margin: 4pt 0; padding-left: 18pt; } li { margin: 2pt 0; }
        mark { background: #FFE58A; padding: 0 2px; border-radius: 3px; }
        code { font-family: Menlo, monospace; font-size: 11pt; background: #F2F2F7; padding: 1px 4px; border-radius: 4px; }
        pre { background: #F2F2F7; padding: 10pt; border-radius: 8pt; white-space: pre-wrap; font-family: Menlo, monospace; font-size: 10.5pt; }
        blockquote { margin: 6pt 0; padding-left: 10pt; border-left: 3px solid #D1D1D6; color: #636366; font-style: italic; }
        .callout { margin: 10pt 0; padding: 8pt 12pt; border-radius: 8pt; border-left: 4px solid; page-break-inside: avoid; }
        .callout-title { font-weight: 600; margin-bottom: 4pt; }
        table { border-collapse: collapse; margin: 6pt 0; } th, td { border-bottom: 1px solid #E5E5EA; padding: 4pt 8pt; text-align: left; }
        .task { list-style: none; margin-left: -16pt; }
        .meta { color: #8E8E93; font-size: 10pt; margin-bottom: 14pt; }
        a { color: #007AFF; }
        </style></head><body>
        <div class="meta">IntelligenceBook · \(note.createdAt.formatted(date: .long, time: .shortened)) · \(NoteHTML.escape(note.modelName))</div>
        \(body)
        </body></html>
        """
    }

    static func pdfFile(for note: Note) throws -> URL {
        let formatter = UIMarkupTextPrintFormatter(markupText: html(for: note))
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let paper = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let printable = paper.insetBy(dx: 42, dy: 48)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, [kCGPDFContextTitle as String: note.title])
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()

        let url = exportDirectory().appendingPathComponent(fileName(for: note, ext: "pdf"))
        try (data as Data).write(to: url)
        return url
    }

    // MARK: Obsidian deep link

    static func obsidianURL(for note: Note, vault: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#/")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        let name = fileName(for: note, ext: "md").replacingOccurrences(of: ".md", with: "")
        var url = "obsidian://new?name=\(enc(name))&content=\(enc(markdown(for: note)))"
        let trimmedVault = vault.trimmingCharacters(in: .whitespaces)
        if !trimmedVault.isEmpty { url += "&vault=\(enc(trimmedVault))" }
        return URL(string: url)
    }
}

enum NoteHTML {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func sub(_ s: String, _ pattern: String, _ template: String) -> String {
        let re = try! NSRegularExpression(pattern: pattern)
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    static func inline(_ text: String) -> String {
        var s = escape(InlineMarkdown.normalize(text))
        s = sub(s, "`([^`]+)`", "<code>$1</code>")
        s = sub(s, "==(.+?)==", "<mark>$1</mark>")
        s = sub(s, "\\*\\*(.+?)\\*\\*", "<strong>$1</strong>")
        s = sub(s, "(?<![\\w*])\\*(?!\\s)(.+?)\\*", "<em>$1</em>")
        s = sub(s, "\\[([^\\]]+)\\]\\((https?://[^)\\s]+)\\)", "<a href=\"$2\">$1</a>")
        return s
    }

    static func render(_ blocks: [NoteBlock]) -> String {
        var html = ""
        var openList: String?
        func closeList() {
            if let tag = openList { html += "</\(tag)>"; openList = nil }
        }
        func ensureList(_ tag: String) {
            if openList != tag { closeList(); html += "<\(tag)>"; openList = tag }
        }
        for block in blocks {
            switch block.kind {
            case .bullet(let text, let indent):
                ensureList("ul")
                html += "<li style=\"margin-left:\(indent * 16)pt\">\(inline(text))</li>"
            case .task(let text, let done, let indent):
                ensureList("ul")
                html += "<li class=\"task\" style=\"margin-left:\(indent * 16)pt\">\(done ? "☑︎" : "☐") \(inline(text))</li>"
            case .numbered(let n, let text, let indent):
                ensureList("ol")
                html += "<li value=\"\(escape(n))\" style=\"margin-left:\(indent * 16)pt\">\(inline(text))</li>"
            default:
                closeList()
                switch block.kind {
                case .heading(let level, let text): html += "<h\(level)>\(inline(text))</h\(level)>"
                case .paragraph(let text): html += "<p>\(inline(text))</p>"
                case .quote(let text): html += "<blockquote>\(inline(text))</blockquote>"
                case .callout(let kind, let title, let children):
                    html += """
                    <div class="callout" style="border-color:\(kind.hex); background:\(kind.hex)1F">\
                    <div class="callout-title" style="color:\(kind == .tip ? "#9A7B00" : kind.hex)">\(inline(title.isEmpty ? kind.defaultTitle : title))</div>\
                    \(render(children))</div>
                    """
                case .code(_, let code): html += "<pre>\(escape(code))</pre>"
                case .table(let rows):
                    html += "<table>"
                    for (i, row) in rows.enumerated() {
                        let tag = i == 0 ? "th" : "td"
                        html += "<tr>" + row.map { "<\(tag)>\(inline($0))</\(tag)>" }.joined() + "</tr>"
                    }
                    html += "</table>"
                case .divider: html += "<hr>"
                default: break
                }
            }
        }
        closeList()
        return html
    }
}
