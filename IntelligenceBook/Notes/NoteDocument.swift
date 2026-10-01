import Foundation
import SwiftUI

/// Semantic colour roles from the vault's Theme notes:
/// Brand accent is yellow (like Apple Notes). source=blue, summary=yellow, definition=teal, tip=orange, question=pink, success=green, error=red.
enum CalloutKind: String, CaseIterable {
    case summary, definition, tip, question, example, warning, quote, note

    init(raw: String) {
        switch raw.lowercased() {
        case "summary", "abstract", "tldr", "insight": self = .summary
        case "definition", "define", "term", "info": self = .definition
        case "tip", "hint", "important", "key", "highlight": self = .tip
        case "question", "faq", "help", "review": self = .question
        case "example", "success", "check", "done": self = .example
        case "warning", "caution", "attention", "danger", "error", "bug", "failure": self = .warning
        case "quote", "cite": self = .quote
        default: self = .note
        }
    }

    var color: Color {
        switch self {
        case .summary: .yellow
        case .definition: .teal
        case .tip: .orange
        case .question: .pink
        case .example: .green
        case .warning: .red
        case .quote: .gray
        case .note: .blue
        }
    }

    var hex: String {
        switch self {
        case .summary: "#FFCC00"
        case .definition: "#30B0C7"
        case .tip: "#FF9500"
        case .question: "#FF2D55"
        case .example: "#34C759"
        case .warning: "#FF3B30"
        case .quote: "#8E8E93"
        case .note: "#007AFF"
        }
    }

    var symbol: String {
        switch self {
        case .summary: "sparkles"
        case .definition: "character.book.closed"
        case .tip: "lightbulb"
        case .question: "questionmark.circle"
        case .example: "checkmark.seal"
        case .warning: "exclamationmark.triangle"
        case .quote: "quote.opening"
        case .note: "info.circle"
        }
    }

    var defaultTitle: String {
        switch self {
        case .summary: "สรุป"
        case .definition: "นิยาม"
        case .tip: "ประเด็นสำคัญ"
        case .question: "คำถาม"
        case .example: "ตัวอย่าง"
        case .warning: "ข้อควรระวัง"
        case .quote: "อ้างอิง"
        case .note: "โน้ต"
        }
    }

    /// Obsidian callout type to use when exporting.
    var obsidianType: String {
        switch self {
        case .definition: "info"
        default: rawValue
        }
    }
}

indirect enum BlockKind: Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet(text: String, indent: Int)
    case numbered(number: String, text: String, indent: Int)
    case task(text: String, done: Bool, indent: Int)
    case quote(String)
    case callout(kind: CalloutKind, title: String, blocks: [NoteBlock])
    case code(language: String, code: String)
    case table(rows: [[String]])
    case divider
}

struct NoteBlock: Identifiable, Hashable {
    let id: Int
    let kind: BlockKind
}

enum NoteParser {
    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
    private static let headingRE = re("^(#{1,6})\\s+(.*)$")
    private static let taskRE = re("^(\\s*)[-*+]\\s+\\[([ xX])\\]\\s+(.*)$")
    private static let bulletRE = re("^(\\s*)[-*+•]\\s+(.*)$")
    private static let numberedRE = re("^(\\s*)(\\d+)[.)]\\s+(.*)$")
    private static let calloutRE = re("^\\[!(\\w+)\\][+-]?\\s*(.*)$")

    private static func groups(_ regex: NSRegularExpression, _ line: String) -> [String]? {
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    static func parse(_ markdown: String) -> [NoteBlock] {
        var counter = 0
        return parseLines(stripFrontmatter(markdown).components(separatedBy: "\n"), counter: &counter)
    }

    static func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---\n") else { return text }
        let rest = text.dropFirst(4)
        guard let end = rest.range(of: "\n---") else { return text }
        return String(rest[end.upperBound...]).trimmingCharacters(in: .newlines)
    }

    private static func indentLevel(_ spaces: String) -> Int {
        let width = spaces.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return min(width / 2, 4)
    }

    private static func isBlockStart(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("#") || t.hasPrefix(">") || t.hasPrefix("```") || t.hasPrefix("|")
            || groups(bulletRE, line) != nil || groups(numberedRE, line) != nil
            || ["---", "***", "___"].contains(t)
    }

    private static func parseLines(_ lines: [String], counter: inout Int) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        func add(_ kind: BlockKind) {
            blocks.append(NoteBlock(id: counter, kind: kind))
            counter += 1
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Fenced code
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1
                add(.code(language: language, code: code.joined(separator: "\n")))
                continue
            }

            if ["---", "***", "___"].contains(trimmed) { add(.divider); i += 1; continue }

            if let g = groups(headingRE, trimmed) {
                add(.heading(level: g[0].count, text: g[1].trimmingCharacters(in: CharacterSet(charactersIn: "# "))))
                i += 1; continue
            }

            // Quote / callout
            if trimmed.hasPrefix(">") {
                var inner: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var content = String(t.dropFirst())
                    if content.hasPrefix(" ") { content.removeFirst() }
                    inner.append(content)
                    i += 1
                }
                if let first = inner.first, let g = groups(calloutRE, first.trimmingCharacters(in: .whitespaces)) {
                    let kind = CalloutKind(raw: g[0])
                    let children = parseLines(Array(inner.dropFirst()), counter: &counter)
                    add(.callout(kind: kind, title: g[1], blocks: children))
                } else {
                    add(.quote(inner.joined(separator: "\n")))
                }
                continue
            }

            // Table
            if trimmed.hasPrefix("|") {
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    let isSeparator = row.allSatisfy { "|-: ".contains($0) }
                    if !isSeparator {
                        var cells = row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                        if cells.first == "" { cells.removeFirst() }
                        if cells.last == "" { cells.removeLast() }
                        rows.append(cells)
                    }
                    i += 1
                }
                if !rows.isEmpty { add(.table(rows: rows)) }
                continue
            }

            if let g = groups(taskRE, line) {
                add(.task(text: g[2], done: g[1].lowercased() == "x", indent: indentLevel(g[0])))
                i += 1; continue
            }
            if let g = groups(bulletRE, line) {
                add(.bullet(text: g[1], indent: indentLevel(g[0])))
                i += 1; continue
            }
            if let g = groups(numberedRE, line) {
                add(.numbered(number: g[1], text: g[2], indent: indentLevel(g[0])))
                i += 1; continue
            }

            // Paragraph: gather until blank line or another block.
            var paragraph = [trimmed]
            i += 1
            while i < lines.count {
                let next = lines[i]
                if next.trimmingCharacters(in: .whitespaces).isEmpty || isBlockStart(next) { break }
                paragraph.append(next.trimmingCharacters(in: .whitespaces))
                i += 1
            }
            add(.paragraph(paragraph.joined(separator: " ")))
        }
        return blocks
    }
}

// MARK: - Inline markdown (bold, italic, code, links, ==highlight==)

enum InlineMarkdown {
    static let highlightColor = Color.yellow.opacity(0.38)

    private static let boldHighlight = try! NSRegularExpression(pattern: "\\*\\*==(.+?)==\\*\\*")

    static func normalize(_ text: String) -> String {
        let ns = text as NSString
        return boldHighlight.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "==**$1**=="
        )
    }

    static func attributed(_ text: String) -> AttributedString {
        let parts = normalize(text).components(separatedBy: "==")
        // An odd number of "==" means an unmatched marker: treat literally.
        let balanced = parts.count % 2 == 1
        var result = AttributedString()
        for (index, part) in parts.enumerated() {
            if part.isEmpty { continue }
            var piece = (try? AttributedString(
                markdown: part,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(part)
            if balanced, index % 2 == 1 {
                piece.backgroundColor = highlightColor
            } else if !balanced, index > 0 {
                piece = AttributedString("==") + piece
            }
            result += piece
        }
        return result
    }

    /// Plain text with markdown markers removed (for plain-text export).
    static func plain(_ text: String) -> String {
        String(attributed(text).characters)
    }
}
