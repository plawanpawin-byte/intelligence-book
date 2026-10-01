import Foundation
import Observation

enum OutputLanguage: String, CaseIterable, Identifiable {
    case auto, thai, english
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "ตามภาษาของแหล่งข้อมูล"
        case .thai: "ภาษาไทย"
        case .english: "English"
        }
    }

    var instruction: String {
        switch self {
        case .auto: "Write the note in the same language as the source material (if it is Thai, write in Thai)."
        case .thai: "เขียนโน้ตทั้งหมดเป็นภาษาไทย (คำศัพท์เทคนิคเก็บภาษาอังกฤษไว้ในวงเล็บได้)"
        case .english: "Write the whole note in English."
        }
    }
}

enum Prompts {
    /// The note syntax the app renders. It is plain Obsidian-flavoured Markdown, so it exports cleanly.
    static let syntaxGuide = """
    FORMAT RULES (Obsidian-flavoured Markdown, the app renders colours from it):
    - Start with "# " and a short, specific title.
    - Right after the title add a summary callout:
      > [!summary] สรุปสั้น
      > 2–3 sentences with the core idea.
    - Use "## " for main sections and "### " for sub-sections.
    - Use bullet lists ("- ") for points. Keep each bullet short.
    - Highlight the single most important phrase in a paragraph or bullet with ==double equals==. Use highlights sparingly (max 1 per bullet).
    - Use **bold** for key terms.
    - Put key terms in a definition callout:
      > [!definition] Term
      > Short explanation.
    - Put important insights in:  > [!tip] หัวข้อ
    - Put warnings, caveats or uncertainty in:  > [!warning] หัวข้อ
    - Put review questions in:  > [!question] คำถามทบทวน
    - Put code, formulas or commands in fenced code blocks with a language, e.g. ```python
    - Use "- [ ] " for action items.
    - Use a Markdown table only when comparing things.
    - Never invent facts that are not in the source. If something is unclear, say so in a warning callout.
    - Write each fact ONCE. Never repeat a sentence, bullet or section.
    - Output only the note. No preamble, no closing remarks.
    """

    static func system(language: OutputLanguage) -> String {
        """
        You are IntelligenceBook, an expert note-taker. You turn source material into clear, well-structured, \
        colourful study notes that are easy to read and faithful to the source.
        \(language.instruction)

        FAITHFULNESS (most important):
        - Summarise ONLY what is written or said inside <content> … </content>.
        - The source name and type (e.g. "อัดเสียง", "PDF", "YouTube") are labels, NOT content. \
        Never write about what a recording, file or link is.
        - Timestamps like [00:12] only mark time; ignore them.
        - Speech transcripts can contain small recognition errors; keep the speaker's meaning.
        - If the content is short, the note must be short. Do not pad it with general knowledge.

        \(syntaxGuide)
        """
    }

    static func task(for style: NoteStyle) -> String {
        switch style {
        case .summary:
            return """
            Create a SUMMARY note: title, summary callout, "## ประเด็นสำคัญ" (key takeaways as bullets with highlights), \
            1–4 sections that group the main ideas, definition callouts for key terms, and a short question callout at the end.
            """
        case .studyGuide:
            return """
            Create a STUDY GUIDE: title, summary callout, sections explaining each concept in more depth with examples, \
            definition callouts for every important term, tip callouts for things worth remembering, code blocks for any code \
            or formulas, and a final "## คำถามทบทวน" section with 5 questions and short answers.
            """
        case .outline:
            return """
            Create a hierarchical OUTLINE: title, summary callout, then nested bullet lists ("- " and indented "  - ") \
            following the structure of the material. Highlight the key phrase of each top-level bullet.
            """
        case .questions:
            return """
            Create a REVIEW QUESTIONS note: title, summary callout, then 8–12 questions. Format each one as:
            > [!question] คำถามที่ N
            > the question
            followed by a line "**คำตอบ:** short answer". Mix recall, understanding and application questions.
            """
        }
    }

    /// Short sources get a short note: the full template makes small models invent filler.
    static func shortTask(characters: Int) -> String {
        if characters < 600 {
            return """
            The content is very short. Create a SHORT note: a "# " title, one summary callout with 1–2 sentences, \
            then only the points actually stated in the content as 1–5 bullets. \
            Do NOT add definitions, questions, sections or anything not stated.
            """
        }
        return """
        The content is short. Create a compact note: title, summary callout, then at most 2 short sections \
        with bullets of what the content actually says. Add a definition or question callout only if the content supports it.
        """
    }

    static let extractorSystem = """
    You extract the important information from a part of a longer document or lecture transcript (inside <content>). \
    Output 4–8 concise bullet points ("- ") with the key facts, definitions, numbers, names and arguments. \
    Keep the original language of the text. Ignore timestamps. Each point once, no repetition. \
    Do not add anything that is not in the text. Output only the bullets.
    """
}

/// Turns selected sources into a note using map → reduce over chunks that fit the model's context.
@MainActor
@Observable
final class GenerationJob {
    enum Phase: Equatable {
        case preparing
        case loadingModel
        case reading(Int, Int)
        case writing
        case done
        case failed(String)
    }

    var phase: Phase = .preparing
    var output: String = ""
    var progress: Double = 0
    /// Estimated seconds left while reading a long source.
    var remaining: TimeInterval?

    var phaseText: String {
        switch phase {
        case .preparing: return "กำลังเตรียมแหล่งข้อมูล"
        case .loadingModel: return LLMService.shared.statusText
        case .reading(let i, let n):
            if let remaining, remaining > 60 { return "กำลังอ่านส่วนที่ \(i) จาก \(n) · เหลืออีกราว \(Int(remaining / 60) + 1) นาที" }
            return "กำลังอ่านส่วนที่ \(i) จาก \(n)"
        case .writing: return "กำลังเขียนโน้ต"
        case .done: return "เสร็จแล้ว"
        case .failed(let m): return m
        }
    }

    struct SourceInput {
        let title: String
        let kind: SourceKind
        let text: String
    }

    func run(sources: [SourceInput], style: NoteStyle, language: OutputLanguage) async {
        let llm = LLMService.shared
        let variant = DeviceProfile.selected
        output = ""
        progress = 0

        do {
            phase = .loadingModel
            _ = try await llm.ensureLoaded()

            let budget = variant.chunkCharacters
            let contentLength = sources.reduce(0) { $0 + $1.text.count }
            let fullCorpus = sources.enumerated().map { index, source in
                GenerationJob.wrap(source, index: index)
            }.joined(separator: "\n\n")

            var material = fullCorpus
            if fullCorpus.count > budget {
                material = try await condense(sources: sources, budget: budget)
            }

            phase = .writing
            progress = 0.9
            let task = contentLength < 2_500 ? Prompts.shortTask(characters: contentLength) : Prompts.task(for: style)
            let maxTokens: Int
            switch contentLength {
            case ..<600: maxTokens = 320
            case ..<2_500: maxTokens = 700
            default: maxTokens = variant.maxOutputTokens
            }
            let note = try await llm.generate(
                system: Prompts.system(language: language),
                prompt: """
                \(task)

                SOURCE:
                \(material)
                """,
                maxTokens: maxTokens,
                continueIfCut: true
            ) { [weak self] partial in
                self?.output = partial
            }
            output = NoteCleaner.clean(note)
            progress = 1
            phase = .done
        } catch is CancellationError {
            phase = .failed("ยกเลิกแล้ว")
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Source label outside the content tags so the model doesn't summarise the label itself.
    static func wrap(_ source: SourceInput, index: Int) -> String {
        "[แหล่งที่ \(index + 1) · ชื่อ: \(source.title)]\n<content>\n\(source.text)\n</content>"
    }

    /// Map step: compress each chunk into bullets, repeated until everything fits the budget.
    private func condense(sources: [SourceInput], budget: Int) async throws -> String {
        let llm = LLMService.shared
        var chunks: [(title: String, text: String)] = []
        for source in sources {
            for piece in TextChunker.split(source.text, maxCharacters: budget) {
                chunks.append((source.title, piece))
            }
        }

        // Keep runtime bounded on very long material (2–3 h lectures): sample evenly.
        let maxChunks = 24
        if chunks.count > maxChunks {
            let step = Double(chunks.count) / Double(maxChunks)
            chunks = (0..<maxChunks).map { chunks[Int(Double($0) * step)] }
        }

        let started = Date()
        var digest: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            phase = .reading(index + 1, chunks.count)
            progress = 0.85 * Double(index) / Double(chunks.count)
            if index > 0 {
                let perChunk = Date().timeIntervalSince(started) / Double(index)
                remaining = perChunk * Double(chunks.count - index + 2)
            }
            let bullets = try await llm.generate(
                system: Prompts.extractorSystem,
                prompt: "<content>\n\(chunk.text)\n</content>",
                maxTokens: 280,
                temperature: 0.2
            ) { [weak self] partial in
                self?.output = partial
            }
            digest.append("ส่วนที่ \(index + 1):\n\(bullets)")
        }
        remaining = nil

        var joined = digest.joined(separator: "\n\n")
        var rounds = 0
        while joined.count > budget && rounds < 2 {
            rounds += 1
            let groups = TextChunker.split(joined, maxCharacters: budget)
            var reduced: [String] = []
            for (index, group) in groups.enumerated() {
                try Task.checkCancellation()
                phase = .reading(index + 1, groups.count)
                reduced.append(try await llm.generate(
                    system: Prompts.extractorSystem,
                    prompt: "<content>\n\(group)\n</content>",
                    maxTokens: 350,
                    temperature: 0.2
                ))
            }
            joined = reduced.joined(separator: "\n\n")
        }
        return "<content>\n\(String(joined.prefix(budget)))\n</content>"
    }
}

enum TextChunker {
    /// Splits on paragraph boundaries, falling back to hard cuts for huge paragraphs.
    static func split(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return [text] }
        var chunks: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            if current.count + paragraph.count + 1 > maxCharacters, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            if paragraph.count > maxCharacters {
                var rest = Substring(paragraph)
                while rest.count > maxCharacters {
                    chunks.append(String(rest.prefix(maxCharacters)))
                    rest = rest.dropFirst(maxCharacters)
                }
                current = String(rest)
            } else {
                current += (current.isEmpty ? "" : "\n") + paragraph
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chunks.append(current) }
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
        if let range = text.range(of: "\n# "), !text.hasPrefix("# "), text.distance(from: text.startIndex, to: range.lowerBound) < 200 {
            text = String(text[text.index(after: range.lowerBound)...])
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
