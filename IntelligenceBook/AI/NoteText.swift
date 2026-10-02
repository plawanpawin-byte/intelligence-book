import Foundation

// Pure text helpers of the note pipeline (no app types), so tools/swiftcheck can compile and test them on CI.

// MARK: - Source clean-up

enum SourceCleaner {
    private static let timestamp = try! NSRegularExpression(pattern: "^\\[(?:\\d{1,2}:)?\\d{1,2}:\\d{2}\\]\\s*", options: .anchorsMatchLines)
    private static let fillerTokens: Set<String> = [
        "เอ่อ", "อ่ะ", "อะ", "อ้า", "อ๋อ", "เออ", "อืม", "อืมม", "แบบว่า", "ก็คือว่า", "คือว่า", "นะ", "นะครับ", "ครับ",
        "ค่ะ", "คะ", "นะคะ", "จ้ะ", "จ้า", "โอเค", "โอเคนะครับ", "ใช่มั้ย", "ใช่ไหม", "เนอะ", "อ่า", "ใช่", "อ้าว", "เนี่ย",
        "เนาะ", "แหละ", "uh", "um", "uhm", "erm", "like,", "okay", "okay,", "OK", "ok", "so,",
    ]
    private static let particleSuffixes = ["นะครับ", "นะคะ", "ครับ", "ค่ะ"]

    /// Timestamps, filler words and polite particles out; Thai number words → digits.
    static func speech(_ text: String) -> String {
        let ns = text as NSString
        let noTimes = timestamp.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        let converted = ThaiNumbers.convert(noTimes)
        var lines: [String] = []
        for line in converted.components(separatedBy: "\n") {
            var tokens: [String] = []
            for token in line.split(whereSeparator: \.isWhitespace).map(String.init) {
                if fillerTokens.contains(token) { continue }
                var t = token
                for suffix in particleSuffixes where t.hasSuffix(suffix) {
                    t = String(t.dropLast(suffix.count))
                    break
                }
                if !t.isEmpty { tokens.append(t) }
            }
            if !tokens.isEmpty { lines.append(tokens.joined(separator: " ")) }
        }
        return lines.joined(separator: "\n")
    }

    /// Drops page markers, page numbers and running headers/footers; re-joins hard-wrapped lines.
    static func pdf(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var counts: [String: Int] = [:]
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, t.count < 90 { counts[t, default: 0] += 1 }
        }
        var out: [String] = []
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if (counts[t] ?? 0) >= 3 { continue }
            if t.range(of: "^\\[Page \\d+\\]$", options: .regularExpression) != nil { continue }
            if t.range(of: "^\\d{1,4}$", options: .regularExpression) != nil { continue }
            if let last = out.last, !last.isEmpty, let first = t.first,
               last.range(of: "[.!?:;]$", options: .regularExpression) == nil, first.isLowercase || first == "(" || first == "," {
                out[out.count - 1] = last + " " + t
            } else {
                out.append(t)
            }
        }
        var joined = out.joined(separator: "\n")
        while joined.contains("\n\n\n") { joined = joined.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return joined.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LanguageDetector {
    static func isThai(_ text: String) -> Bool {
        var thai = 0
        var letters = 0
        for scalar in text.prefix(20_000).unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            if (0x0E00...0x0E7F).contains(scalar.value) { thai += 1 }
        }
        return letters > 0 && Double(thai) / Double(letters) > 0.3
    }
}

// MARK: - Facts

enum FactList {
    struct Parsed {
        var topic: String
        var facts: [String]
        var text: String { (topic.isEmpty ? "" : "TOPIC: \(topic)\n") + facts.joined(separator: "\n") }
    }

    /// Reads "TOPIC: …" + bullets; numbered / indented sub-points are kept as indented bullets.
    static func parse(_ raw: String) -> Parsed {
        var topic = ""
        var facts: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.uppercased().hasPrefix("TOPIC:") {
                if topic.isEmpty { topic = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
                continue
            }
            let indented = line.prefix(while: { $0 == " " || $0 == "\t" }).count >= 1
            var body = trimmed
            if let range = body.range(of: "^(?:[-*•]|\\d+[.)])\\s*", options: .regularExpression) {
                body.removeSubrange(range)
            }
            guard body.count >= 4 else { continue }
            if "-*•".contains(trimmed.first!), !indented {
                facts.append("- " + body)
            } else if !facts.isEmpty {
                facts.append("  - " + body)
            } else {
                facts.append("- " + body)
            }
        }
        return Parsed(topic: topic, facts: facts)
    }

    static func key(_ line: String) -> String {
        line.lowercased().filter { !$0.isWhitespace && !"-*>#=•".contains($0) }
    }

    static func trigrams(_ text: String) -> Set<String> {
        let chars = Array(text.lowercased().filter { !$0.isWhitespace && !"*_=`>#-".contains($0) })
        guard chars.count >= 3 else { return [] }
        var grams = Set<String>()
        for i in 0...(chars.count - 3) { grams.insert(String(chars[i..<i + 3])) }
        return grams
    }

    /// A fact mostly contained in an earlier one (lectures recap themselves at the end).
    static func isNearDuplicate(_ grams: Set<String>, of seen: [Set<String>], threshold: Double = 0.6) -> Bool {
        guard grams.count >= 8 else { return false }
        for other in seen {
            let shared = grams.intersection(other).count
            if shared > 0, Double(shared) / Double(min(grams.count, other.count)) >= threshold { return true }
        }
        return false
    }

    /// Drops fact lines copied from the worked example (the model sometimes appends one of its facts).
    static func removeExampleLines(_ raw: String, examples: [String]) -> String {
        raw.components(separatedBy: "\n").filter { line in
            line.trimmingCharacters(in: .whitespaces).count <= 20
                || !examples.contains { Grounding.overlap(line, with: $0, size: 10) > 0.5 }
        }.joined(separator: "\n")
    }

    /// An evenly spread sample of the facts that fits the character budget.
    static func sample(_ facts: [String], maxCharacters: Int) -> String {
        let all = facts.joined(separator: "\n")
        guard all.count > maxCharacters, !facts.isEmpty else { return all }
        let average = Double(all.count) / Double(facts.count)
        let keep = max(1, Int(Double(maxCharacters) / average))
        let step = Double(facts.count) / Double(keep)
        return (0..<keep).map { facts[min(facts.count - 1, Int(Double($0) * step))] }.joined(separator: "\n")
    }
}

// MARK: - Sections

enum SectionTools {
    static func heading(of section: String) -> String {
        for line in section.components(separatedBy: "\n") where line.hasPrefix("## ") {
            return String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }
        return String(section.components(separatedBy: "\n").first?.prefix(60) ?? "")
    }

    /// Makes sure a section starts with "## " and contains no "# " title.
    static func normalize(_ section: String, topic: String) -> String {
        // One "## " per section: a "# " title or any further "## " becomes a "### " sub-heading.
        var seenH2 = false
        var lines = section.components(separatedBy: "\n").map { line -> String in
            let h2: String
            if line.hasPrefix("# ") { h2 = "#" + line } else if line.hasPrefix("## ") { h2 = line } else { return line }
            defer { seenH2 = true }
            return seenH2 ? "#" + h2 : h2
        }
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        var text = lines.joined(separator: "\n")
        if !text.hasPrefix("## ") {
            text = "## \(topic.isEmpty ? "Notes" : topic)\n\n" + text
        }
        return text
    }

    /// Drops near-empty sections and merges a section into the previous one when they share a heading.
    static func merge(_ sections: [String]) -> [String] {
        var out: [String] = []
        for raw in sections {
            let section = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if section.filter({ !$0.isWhitespace }).count < 40 { continue }
            if let last = out.last, heading(of: last).lowercased() == heading(of: section).lowercased() {
                let body = section.components(separatedBy: "\n").filter { !$0.hasPrefix("## ") }.joined(separator: "\n")
                out[out.count - 1] = last + "\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                out.append(section)
            }
        }
        return out
    }

    /// True when the opening has a real paragraph (not only a title and the overview callout).
    static func hasHook(_ opening: String) -> Bool {
        opening.components(separatedBy: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("#") && !t.hasPrefix(">") && t.count > 40
        }
    }

    /// Headings + the first words of each section, for the opening writer.
    static func outline(_ sections: [String], perSection: Int) -> String {
        sections.map { section in
            let lines = section.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let head = lines.first { $0.hasPrefix("## ") } ?? "## (section)"
            let body = lines
                .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("> [!") }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "> ")).trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            return head + "\n" + String(body.prefix(perSection))
        }.joined(separator: "\n\n")
    }
}

/// Fixes the small format slips of a 3B model so callouts render properly.
enum MarkdownFixer {
    /// Inside the review-questions section, numbered "### 1. Question" headings become question callouts.
    static func headingQuestions(_ text: String) -> String {
        var inReview = false
        return text.components(separatedBy: "\n").map { line -> String in
            if line.hasPrefix("## ") {
                inReview = ["คำถาม", "Review", "question"].contains { line.contains($0) }
                return line
            }
            guard inReview, let range = line.range(of: "^#{3,6}\\s*\\d+[.)]\\s*", options: .regularExpression) else { return line }
            return "> [!question] " + line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    /// "1. Question?" followed by "**Answer:** …" → a question callout; answers without a question are dropped.
    static func questionCallouts(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        func isAnswer(_ line: String) -> Bool {
            line.range(of: "^\\s*>?\\s*\\*\\*(?:Answer|คำตอบ)\\s*[:：]\\*\\*", options: .regularExpression) != nil
        }
        var out: [String] = []
        for (index, line) in lines.enumerated() {
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            if isAnswer(next), let range = line.range(of: "^\\s*(?:\\d+[.)]|[-*])\\s+", options: .regularExpression),
               line.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
                out.append("> [!question] " + line[range.upperBound...].trimmingCharacters(in: .whitespaces))
                continue
            }
            if isAnswer(line) {
                let previousIsCallout = out.last?.trimmingCharacters(in: .whitespaces).hasPrefix(">") == true
                guard previousIsCallout else { continue } // an answer without its question
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                out.append(trimmed.hasPrefix(">") ? line : "> " + trimmed)
                continue
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    static func fix(_ text: String, thai: Bool) -> String {
        var out: [String] = []
        for var line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            // "* [!question] …", "- [!tip] …", "[!tip] …" → "> [!…] …"
            if !t.hasPrefix("> [!"),
               let match = t.range(of: "^(?:[*\\-•]\\s*|#{1,6}\\s*|>?\\s*)\\[!(\\w+)\\]", options: .regularExpression) {
                let marker = t[match]
                let kind = marker.drop(while: { $0 != "!" }).dropFirst().prefix(while: { $0 != "]" })
                let rest = t[match.upperBound...].trimmingCharacters(in: .whitespaces)
                line = "> [!\(kind)] \(rest)".trimmingCharacters(in: .whitespaces)
            }
            let fixed = line.trimmingCharacters(in: .whitespaces)
            if fixed.range(of: "^>\\s*\\[!summary\\]$", options: .regularExpression) != nil {
                line = "> [!summary] " + (thai ? "ภาพรวม" : "Overview")
            }
            // An answer line right under a callout belongs inside it.
            if fixed.range(of: "^\\*\\*(?:Answer|คำตอบ)\\s*[:：]\\*\\*", options: .regularExpression) != nil,
               out.last?.trimmingCharacters(in: .whitespaces).hasPrefix(">") == true {
                line = "> " + fixed
            }
            // "### ## Heading" → "## Heading"
            if let range = line.range(of: "^#{2,}\\s+(?=#{2,}\\s)", options: .regularExpression) {
                line.removeSubrange(range)
            }
            out.append(line)
        }
        var result = out.joined(separator: "\n")
        // A blank line before every callout header so neighbouring callouts don't merge.
        result = result.replacingOccurrences(of: "([^\\n])\\n(> \\[!)", with: "$1\n\n$2", options: .regularExpression)
        while result.contains("\n\n\n") { result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Checks the note against its sources.
enum Grounding {
    private static let number = try! NSRegularExpression(pattern: "\\d[\\d,]*(?:\\.\\d+)?")

    /// Every number in the text, without thousands separators ("12,000" → "12000").
    static func numbers(in text: String) -> Set<String> {
        let ns = text as NSString
        var out = Set<String>()
        for match in number.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var value = ns.substring(with: match.range).replacingOccurrences(of: ",", with: "")
            while value.hasSuffix(".") { value.removeLast() }
            out.insert(value)
            if value.contains(".") {
                var trimmed = value
                while trimmed.hasSuffix("0") { trimmed.removeLast() }
                if trimmed.hasSuffix(".") { trimmed.removeLast() }
                out.insert(trimmed)
            }
        }
        return out
    }

    /// Numbers up to 10 are counts and list positions ("2 types") — only larger ones are checked.
    static func isUngrounded(_ text: String, allowed: Set<String>) -> Bool {
        numbers(in: text).contains { value in
            guard let v = Double(value), v > 10 else { return false }
            return !allowed.contains(value)
        }
    }

    /// Removes paragraphs, bullets, table rows and whole callouts that state a number (> 10) not in the sources.
    static func dropUngroundedNumbers(_ note: String, allowed: Set<String>) -> String {
        let lines = note.components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("> [!") {
                var block = [line]
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    block.append(lines[j])
                    j += 1
                }
                if !isUngrounded(block.joined(separator: "\n"), allowed: allowed) { out += block }
                i = j
                continue
            }
            if t.hasPrefix("#") || !isUngrounded(t, allowed: allowed) { out.append(line) }
            i += 1
        }
        // A table left with only its header row is dropped.
        var cleaned: [String] = []
        var k = 0
        while k < out.count {
            let t = out[k].trimmingCharacters(in: .whitespaces)
            let next = k + 1 < out.count ? out[k + 1].trimmingCharacters(in: .whitespaces) : ""
            let after = k + 2 < out.count ? out[k + 2].trimmingCharacters(in: .whitespaces) : ""
            if t.hasPrefix("|"), next.hasPrefix("|"), next.range(of: "^\\|[-| :]+\\|$", options: .regularExpression) != nil,
               !after.hasPrefix("|") {
                k += 2
                continue
            }
            cleaned.append(out[k])
            k += 1
        }
        var text = cleaned.joined(separator: "\n")
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return text
    }

    /// Share of the output's 12-character pieces that also appear in `example` (1 = a copy of the example).
    static func overlap(_ output: String, with example: String, size: Int = 12) -> Double {
        let a = Array(output.filter { !$0.isWhitespace })
        let b = Array(example.filter { !$0.isWhitespace })
        guard a.count >= size, b.count >= size else { return 0 }
        var exampleGrams = Set<String>()
        for i in 0...(b.count - size) { exampleGrams.insert(String(b[i..<i + size])) }
        var total = 0
        var shared = 0
        for i in stride(from: 0, through: a.count - size, by: 2) {
            total += 1
            if exampleGrams.contains(String(a[i..<i + size])) { shared += 1 }
        }
        return total == 0 ? 0 : Double(shared) / Double(total)
    }
}

enum TextChunker {
    /// Splits on line boundaries (at a space for huge lines); a tiny last chunk is merged into the previous one.
    static func split(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }
        var chunks: [String] = []
        var current = ""
        for line in text.components(separatedBy: "\n") {
            if !current.isEmpty, current.count + line.count + 1 > maxCharacters {
                chunks.append(current)
                current = ""
            }
            var rest = Substring(line)
            while rest.count > maxCharacters {
                let window = rest.prefix(maxCharacters)
                let minimum = window.index(window.startIndex, offsetBy: Int(Double(maxCharacters) * 0.7))
                let cut = window[minimum...].lastIndex(of: " ") ?? window.endIndex
                chunks.append(String(rest[..<cut]))
                rest = rest[cut...].drop(while: { $0 == " " })
            }
            current += (current.isEmpty ? "" : "\n") + rest
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chunks.append(current) }
        if chunks.count > 1, let last = chunks.last, Double(last.count) < Double(maxCharacters) * 0.3 {
            chunks.removeLast()
            chunks[chunks.count - 1] += "\n" + last
        }
        return chunks
    }
}

enum NoteCleaner {
    /// Small models sometimes wrap the note in ```markdown fences or add chatter — strip that.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeLast() }
            text = lines.joined(separator: "\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func title(from markdown: String, fallback: String) -> String {
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2)).replacingOccurrences(of: "==", with: "")
                    .replacingOccurrences(of: "**", with: "")
            }
        }
        return fallback
    }
}
