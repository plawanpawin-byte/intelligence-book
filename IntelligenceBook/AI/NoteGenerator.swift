import Foundation
import Observation

enum OutputLanguage: String, CaseIterable, Identifiable {
    case auto, thai, english
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Same as source"
        case .thai: "Thai"
        case .english: "English"
        }
    }
}

// MARK: - Pipeline overview
//
// Tuned against the real Llama 3.2 3B (4-bit MLX) with the eval harness on the `eval` branch (tools/eval, "v5").
// A 3B model copies raw text when it sees it and invents numbers when it is asked to do too much at once, so:
//   1. Clean the source deterministically (speech fillers, timestamps, Thai number words → digits, PDF headers).
//   2. UNDERSTAND: every chunk → short written study facts (low temperature, worked example as a chat turn).
//   3. EXPLAIN: groups of facts (never the raw transcript) → note sections with paragraphs and callouts.
//   4. FRAME: title + hook + overview from the sections; key takeaways + review questions from the facts.
// Short material skips 4 so the note isn't padded.

/// Turns selected sources into a note.
@MainActor
@Observable
final class GenerationJob {
    enum Phase: Equatable {
        case preparing
        case loadingModel
        case reading(Int, Int)
        case writing(Int, Int)
        case framing
        case done
        case failed(String)
    }

    var phase: Phase = .preparing
    var output: String = ""
    var progress: Double = 0
    /// Estimated seconds left.
    var remaining: TimeInterval?

    var phaseText: String {
        switch phase {
        case .preparing: return "Preparing sources"
        case .loadingModel: return LLMService.shared.statusText
        case .reading(let i, let n): return "Understanding part \(i) of \(n)" + eta
        case .writing(let i, let n): return "Writing section \(i) of \(n)" + eta
        case .framing: return "Writing the introduction and review"
        case .done: return "Done"
        case .failed(let m): return m
        }
    }

    /// True while the visible output is note Markdown (not the intermediate study facts).
    var isWritingNote: Bool {
        switch phase {
        case .writing, .framing, .done: true
        default: false
        }
    }

    private var eta: String {
        guard let remaining, remaining > 45 else { return "" }
        return " · about \(Int(remaining / 60) + 1) min left"
    }

    struct SourceInput {
        let title: String
        let kind: SourceKind
        let text: String
    }

    func run(sources: [SourceInput], style: NoteStyle, language: OutputLanguage) async {
        let llm = LLMService.shared
        output = ""
        progress = 0
        do {
            phase = .loadingModel
            _ = try await llm.ensureLoaded()
            phase = .preparing

            let spoken = sources.contains { $0.kind == .audio || $0.kind == .recording }
            let texts = sources.map { SourceCleaner.clean($0.text, kind: $0.kind) }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let corpus = texts.joined(separator: "\n\n")
            let thai: Bool
            switch language {
            case .auto: thai = LanguageDetector.isThai(corpus)
            case .thai: thai = true
            case .english: thai = false
            }
            let kit = NotePrompts(thai: thai, spoken: spoken, style: style)

            let note: String
            if corpus.count < NotePrompts.shortCharacters {
                note = try await shortNote(corpus, kit: kit)
            } else {
                note = try await fullNote(texts, kit: kit)
            }
            // Lines or callouts that state a number the sources never mention are made up: drop them.
            let allowed = Grounding.numbers(in: texts.joined(separator: "\n"))
            output = MarkdownFixer.fix(Grounding.dropUngroundedNumbers(RepetitionGuard.clean(note), allowed: allowed), thai: thai)
            progress = 1
            phase = .done
        } catch is CancellationError {
            phase = .failed("Cancelled")
        } catch {
            phase = .failed(AppError.describe(error, during: "Writing the note"))
        }
    }

    /// One model call with a worked example. When thin material makes the model hand back the example itself
    /// (it happens with a 3B model), the call is repeated without the example.
    private func ask(
        system: String, prompt: String, maxTokens: Int, temperature: Float, example: FewShot,
        onUpdate: @escaping (String) -> Void
    ) async throws -> String {
        let llm = LLMService.shared
        let text = try await llm.generate(
            system: system, prompt: prompt, maxTokens: maxTokens, temperature: temperature, examples: [example], onUpdate: onUpdate
        )
        guard Grounding.overlap(text, with: example.assistant) > 0.2 else { return text }
        return try await llm.generate(
            system: system, prompt: prompt, maxTokens: maxTokens, temperature: temperature, onUpdate: onUpdate
        )
    }

    // MARK: Short material: facts → one compact section, no padding.

    private func shortNote(_ corpus: String, kit: NotePrompts) async throws -> String {
        phase = .reading(1, 1)
        progress = 0.1
        let factsText = try await ask(
            system: kit.factsSystem, prompt: kit.factsPrompt(corpus), maxTokens: 500, temperature: 0.2,
            example: kit.factsExample
        ) { [weak self] partial in self?.output = partial }
        let facts = FactList.parse(factsText)
        phase = .writing(1, 1)
        progress = 0.5
        var section = try await ask(
            system: kit.writeSystem(short: true), prompt: kit.writePrompt(facts.text), maxTokens: 600, temperature: 0.3,
            example: kit.writeExample
        ) { [weak self] partial in self?.output = partial }
        section = NoteCleaner.clean(section)
        if section.hasPrefix("#") {
            // The section heading becomes the note title.
            if let range = section.range(of: "^#{1,3} ", options: .regularExpression) {
                section.replaceSubrange(range, with: "# ")
            }
        } else {
            section = "# \(facts.topic.isEmpty ? "Note" : facts.topic)\n\n" + section
        }
        return section
    }

    // MARK: Full pipeline

    private func fullNote(_ texts: [String], kit: NotePrompts) async throws -> String {
        let llm = LLMService.shared
        var chunks: [String] = []
        for text in texts { chunks += TextChunker.split(text, maxCharacters: NotePrompts.chunkCharacters) }
        // Bound the runtime of very long material (3 h lectures) by merging neighbours, never dropping text.
        if chunks.count > NotePrompts.maxChunks {
            let per = Int((Double(chunks.count) / Double(NotePrompts.maxChunks)).rounded(.up))
            chunks = stride(from: 0, to: chunks.count, by: per).map { chunks[$0..<min($0 + per, chunks.count)].joined(separator: "\n") }
        }

        // Rough plan for the progress bar / ETA: facts per chunk, then ~ (chunks × 0.8) sections, then 2 framing calls.
        let estimatedCalls = Double(chunks.count) * 1.8 + 2
        var callsDone = 0.0
        let started = Date()
        func tick() {
            callsDone += 1
            progress = min(0.97, callsDone / estimatedCalls)
            let perCall = Date().timeIntervalSince(started) / callsDone
            remaining = perCall * max(0, estimatedCalls - callsDone)
        }

        // 1. Understand: chunk → study facts.
        var groups: [(topic: String, facts: [String])] = []
        var seen = Set<String>()
        var seenGrams: [Set<String>] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            phase = .reading(index + 1, chunks.count)
            let raw = try await ask(
                system: kit.factsSystem, prompt: kit.factsPrompt(chunk), maxTokens: 700, temperature: 0.2,
                example: kit.factsExample
            ) { [weak self] partial in self?.output = partial }
            tick()
            let parsed = FactList.parse(raw)
            var fresh: [String] = []
            for fact in parsed.facts {
                let key = FactList.key(fact)
                guard !key.isEmpty, !seen.contains(key) else { continue }
                let grams = FactList.trigrams(fact)
                if FactList.isNearDuplicate(grams, of: seenGrams) { continue }
                seen.insert(key)
                seenGrams.append(grams)
                fresh.append(fact)
            }
            if !fresh.isEmpty { groups.append((parsed.topic, fresh)) }
        }
        let allFacts = groups.flatMap { $0.facts }
        guard !allFacts.isEmpty else { throw AppError.message("The AI couldn’t find any content to write about") }

        // 2. Explain: merge neighbouring fact groups into sections of a digestible size.
        var units: [(topic: String, facts: [String])] = []
        for group in groups {
            let size = group.facts.reduce(0) { $0 + $1.count }
            if let last = units.last, last.facts.reduce(0, { $0 + $1.count }) + size <= NotePrompts.groupCharacters {
                units[units.count - 1].facts += group.facts
            } else {
                units.append(group)
            }
        }
        // Re-estimate now that the number of sections is known.
        var sections: [String] = []
        var finished = ""
        for (index, unit) in units.enumerated() {
            try Task.checkCancellation()
            phase = .writing(index + 1, units.count)
            let facts = (unit.topic.isEmpty ? "" : "TOPIC: \(unit.topic)\n") + unit.facts.joined(separator: "\n")
            let prefix = finished
            var section = try await ask(
                system: kit.writeSystem(short: false), prompt: kit.writePrompt(facts), maxTokens: 1000, temperature: 0.3,
                example: kit.writeExample
            ) { [weak self] partial in self?.output = prefix + partial }
            tick()
            section = SectionTools.normalize(NoteCleaner.clean(section), topic: unit.topic)
            sections.append(section)
            finished += section + "\n\n"
        }
        let merged = SectionTools.merge(sections)
        sections = merged.isEmpty ? sections.filter { !$0.isEmpty } : merged
        if sections.isEmpty { sections = ["## Notes\n\n" + allFacts.joined(separator: "\n")] }

        // 3. Frame: opening from the sections, ending from the facts.
        phase = .framing
        let body = sections.joined(separator: "\n\n")
        let outline = SectionTools.outline(sections, perSection: max(200, 5000 / max(1, sections.count)))
        var opening = try await ask(
            system: kit.openSystem, prompt: kit.openPrompt(outline), maxTokens: 450, temperature: 0.4,
            example: kit.openExample
        ) { [weak self] partial in self?.output = partial + "\n\n" + body }
        tick()
        opening = NoteCleaner.clean(opening)
        if !opening.hasPrefix("# ") {
            opening = "# \(SectionTools.heading(of: sections[0]))\n\n" + opening
        }
        let frontAndBody = opening + "\n\n" + body
        let ending = try await llm.generate(
            system: kit.closeSystem, prompt: kit.closePrompt(FactList.sample(allFacts, maxCharacters: 5000)),
            maxTokens: 1000, temperature: 0.3
        ) { [weak self] partial in self?.output = frontAndBody + "\n\n" + partial }
        tick()
        remaining = nil
        return frontAndBody + "\n\n" + NoteCleaner.clean(ending)
    }
}

// MARK: - Prompts

/// Every prompt of the pipeline. Keep in sync with tools/eval/pipeline.py (v5) when tuning.
struct NotePrompts {
    let thai: Bool
    let spoken: Bool
    let style: NoteStyle

    static let shortCharacters = 1_500
    static let chunkCharacters = 3_500
    static let groupCharacters = 1_500
    static let maxChunks = 36

    private var languageRule: String {
        thai ? "Write in Thai (ภาษาไทย), keeping English technical terms in parentheses." : "Write in English."
    }

    // Understand

    var factsSystem: String {
        let speech = spoken
            ? " The material is a speech-recognition transcript: ignore filler words, greetings and classroom chit-chat, and fix clearly misheard words."
            : ""
        return "You turn material into accurate study facts. \(languageRule)\(speech)\n"
            + "Output a line \"TOPIC: \" with the topic, then bullets. Each bullet is one complete, clear written sentence "
            + "with one fact, definition, cause→effect, step, example (with its numbers), name, exam hint or to-do. "
            + "Cover everything important, in order. Keep cause and effect in the right direction. "
            + "Copy every number exactly as written in the material and never calculate new numbers. "
            + "Only facts that are in the material — never add your own."
    }

    func factsPrompt(_ material: String) -> String { "<material>\n\(material)\n</material>" }

    var factsExample: FewShot {
        FewShot(user: factsPrompt(thai ? Examples.thaiSpeech : Examples.englishSpeech),
                assistant: thai ? Examples.thaiFacts : Examples.englishFacts)
    }

    // Explain

    func writeSystem(short: Bool) -> String {
        var text = "You are an expert teacher who turns study facts into a beautiful, easy-to-understand note section. \(languageRule)\n"
            + "Explain the facts so they connect into an understandable story: what each idea is, why it happens, how it works. "
            + "Use every fact given and keep all numbers, names and examples exactly, but never add a fact, number or "
            + "example that is not given and never calculate new numbers. Make a table only when the facts give every value in it. "
            + "Format: \"## \" heading that names the idea in an interesting way; short paragraphs; **bold** key terms; "
            + "==highlight== the most important phrase; > [!definition] Term, > [!example] Title, > [!tip] Title, "
            + "> [!warning] Title callouts; a table when comparing; \"- [ ] \" for to-dos. Output only the section."
        if short {
            text += " The material is SHORT: write a compact section — one short paragraph that explains it, then bullets "
                + "for the points (and \"- [ ] \" to-dos if any). No tables, no extra callouts, nothing that is not given."
        } else {
            text += " Each fact appears ONCE — in a paragraph, a bullet or a callout, never repeated in another form. "
                + "Prefer explanatory paragraphs that connect the facts (because…, so…, for example…) over bare bullet lists."
            switch style {
            case .summary: break
            case .studyGuide:
                text += " Go deeper: explain every term with a > [!definition] callout and every example step by step."
            case .outline:
                text += " Write the section as a nested bullet outline (\"- \" and indented \"  - \") of full, informative phrases."
            case .questions:
                text += " After the explanation add 2 > [!question] callouts about this section, each followed by a line \"> **Answer:** …\"."
            }
        }
        return text
    }

    func writePrompt(_ facts: String) -> String { "<facts>\n\(facts)\n</facts>" }

    var writeExample: FewShot {
        FewShot(user: writePrompt(thai ? Examples.thaiFacts : Examples.englishFacts),
                assistant: thai ? Examples.thaiSection : Examples.englishSection)
    }

    // Frame

    var openSystem: String {
        "You write the opening of study notes. " + (thai ? "Write in Thai (ภาษาไทย)." : "Write in English.")
            + " Use only what is in the outline. Never mention 'the outline', 'the transcript' or 'the speaker'."
    }

    private static let openTask = "Write the opening of this note: a \"# \" title, a hook paragraph that makes people want to read on "
        + "(start from the most surprising fact or number), and a > [!summary] overview that connects all the main ideas."

    func openPrompt(_ outline: String) -> String { "<outline>\n\(outline)\n</outline>\n\n\(Self.openTask)" }

    var openExample: FewShot {
        FewShot(user: openPrompt(SectionTools.outline([thai ? Examples.thaiSection : Examples.englishSection], perSection: 500)),
                assistant: thai ? Examples.thaiOpening : Examples.englishOpening)
    }

    var closeSystem: String {
        "You write the end of study notes. " + (thai ? "Write in Thai (ภาษาไทย)." : "Write in English.") + " Use only the given facts."
    }

    func closePrompt(_ facts: String) -> String {
        let questions: Int
        switch style {
        case .summary: questions = 4
        case .studyGuide: questions = 6
        case .outline: questions = 3
        case .questions: questions = 8
        }
        let takeaways = thai ? "ประเด็นสำคัญ" : "Key takeaways"
        let review = thai ? "คำถามทบทวน" : "Review questions"
        let answer = thai ? "คำตอบ" : "Answer"
        return """
        <facts>
        \(facts)
        </facts>

        Write exactly:
        ## \(takeaways)
        - <one full sentence with the most important insight; its key phrase in ==highlight==>
        (5 bullets in total, the most important ideas, not details)

        ## \(review)
        > [!question] <a question that checks understanding (why/how), not just a word>
        > **\(answer):** <a complete 1–2 sentence answer from the facts>

        (\(questions) questions in total, same format)
        """
    }
}

// MARK: - Worked examples (shown to the model as earlier chat turns)

enum Examples {
    static let thaiSpeech = "โอเค เอ่อ วันนี้นะครับเรื่องภูเขาไฟ ภูเขาไฟเนี่ยมันเกิดจากแมกม่า magma ก็คือหินที่มันหลอมละลายอยู่ใต้เปลือกโลก "
        + "มันร้อนมาก ประมาณพันองศา แล้วมันเบากว่าหินรอบๆ ก็เลยดันขึ้นมาตามรอยแตก พอออกมาข้างนอกแล้วเราเรียกว่าลาวา lava นะ "
        + "จำไว้ ข้อสอบชอบถาม แมกม่าอยู่ข้างใน ลาวาอยู่ข้างนอก อ่ะ ทีนี้ภูเขาไฟมีกี่แบบ มีสองแบบหลักๆ "
        + "แบบแรกภูเขาไฟรูปโล่ shield volcano ลาวาเหลว ไหลไปไกล ไม่ค่อยระเบิด อย่างฮาวาย แบบที่สองภูเขาไฟสลับชั้น "
        + "stratovolcano ลาวาหนืด แก๊สออกไม่ได้ ก็สะสมแรงดันแล้วระเบิดรุนแรง อย่างฟูจิ เอ่อ ภูเขาไฟปินาตูโบปีเก้าหนึ่ง "
        + "ระเบิดแล้วเถ้าไปบังแดด โลกเย็นลงประมาณครึ่งองศาเกือบสองปี เดี๋ยวสัปดาห์หน้าควิซนะ"

    static let thaiFacts = """
    TOPIC: ภูเขาไฟเกิดขึ้นอย่างไรและมีกี่แบบ
    - ภูเขาไฟเกิดจาก **แมกมา (magma)** คือหินหลอมเหลวใต้เปลือกโลกที่ร้อนประมาณ 1,000 °C และเบากว่าหินรอบข้าง จึงดันตัวขึ้นมาตามรอยแตกของเปลือกโลก
    - เมื่อแมกมาออกมาสู่ผิวโลกจะเรียกว่า **ลาวา (lava)** — แมกมาอยู่ใต้ผิวโลก ลาวาอยู่บนผิวโลก (อาจารย์บอกว่าออกข้อสอบบ่อย)
    - ภูเขาไฟมี 2 แบบหลัก แบ่งตามความหนืดของลาวา
    - **ภูเขาไฟรูปโล่ (shield volcano)**: ลาวาเหลว ไหลไปได้ไกล จึงไม่ค่อยระเบิด เช่น ภูเขาไฟในฮาวาย
    - **ภูเขาไฟสลับชั้น (stratovolcano)**: ลาวาหนืดจนแก๊สออกไม่ได้ แรงดันจึงสะสมจนระเบิดรุนแรง เช่น ภูเขาไฟฟูจิ
    - ตัวอย่างผลกระทบ: ภูเขาไฟปินาตูโบระเบิดในปี 1991 เถ้าถ่านบังแสงอาทิตย์ ทำให้โลกเย็นลงประมาณ 0.5 °C นานเกือบ 2 ปี
    - งานที่ต้องทำ: มีควิซสัปดาห์หน้า
    """

    static let thaiSection = """
    ## ภูเขาไฟ: ทำไมบางลูกไหลเอื่อย แต่บางลูกระเบิดรุนแรง

    ภูเขาไฟเริ่มต้นจาก **แมกมา (magma)** หินหลอมเหลวที่ร้อนราว 1,000 °C ใต้เปลือกโลก เพราะแมกมาเบากว่าหินรอบข้าง มันจึงค่อยๆ ดันตัวขึ้นมาตามรอยแตก และเมื่อพ้นผิวโลกออกมาเราจะเรียกมันว่า **ลาวา (lava)**

    > [!tip] จำให้แม่น (ออกสอบบ่อย)
    > **แมกมา** = อยู่ใต้ผิวโลก · **ลาวา** = ออกมาอยู่บนผิวโลกแล้ว

    ### สองแบบหลัก แบ่งตามความหนืดของลาวา
    สิ่งที่ตัดสินว่าภูเขาไฟจะ "ไหล" หรือ "ระเบิด" คือ ==ความหนืดของลาวา== ยิ่งลาวาหนืด แก๊สยิ่งหนีออกไม่ได้ แรงดันจึงสะสมจนปะทุอย่างรุนแรง

    | แบบ | ลาวา | การปะทุ | ตัวอย่าง |
    |---|---|---|---|
    | ภูเขาไฟรูปโล่ (shield volcano) | เหลว ไหลไปไกล | ไม่ค่อยระเบิด | ฮาวาย |
    | ภูเขาไฟสลับชั้น (stratovolcano) | หนืด แก๊สออกไม่ได้ | ระเบิดรุนแรง | ฟูจิ |

    > [!example] ภูเขาไฟเปลี่ยนอุณหภูมิโลกได้
    > การระเบิดของภูเขาไฟปินาตูโบในปี 1991 ส่งเถ้าถ่านขึ้นไปบังแสงอาทิตย์ ทำให้โลกเย็นลงประมาณ 0.5 °C นานเกือบ 2 ปี

    - [ ] เตรียมตัวควิซสัปดาห์หน้า
    """

    static let thaiOpening = """
    # ภูเขาไฟ: ทำไมบางลูกไหลเอื่อย แต่บางลูกระเบิดจนโลกเย็นลง

    รู้ไหมว่าการระเบิดของภูเขาไฟลูกเดียวทำให้ทั้งโลกเย็นลงได้ราว 0.5 °C นานเกือบ 2 ปี? ความรุนแรงขนาดนั้นไม่ได้เกิดกับภูเขาไฟทุกลูก — บางลูกแค่มีลาวาไหลเอื่อยๆ โน้ตนี้จะพาไปเข้าใจว่าอะไรเป็นตัวตัดสิน

    > [!summary] ภาพรวม
    > ภูเขาไฟเกิดจากแมกมาที่ร้อนราว 1,000 °C ดันตัวขึ้นมาตามรอยแตกของเปลือกโลก และเรียกว่าลาวาเมื่อออกมาถึงผิวโลก ความหนืดของลาวาเป็นตัวแบ่งภูเขาไฟเป็น 2 แบบ: ภูเขาไฟรูปโล่ที่ลาวาเหลวและไม่ค่อยระเบิด กับภูเขาไฟสลับชั้นที่ลาวาหนืดจนแก๊สสะสมแรงดันและระเบิดรุนแรง การระเบิดครั้งใหญ่ส่งผลไปไกลถึงอุณหภูมิของทั้งโลก
    """

    static let englishSpeech = "ok so uh today volcanoes. a volcano starts with magma, that's melted rock under the crust, it's like a thousand "
        + "degrees and lighter than the rock around it so it pushes up through cracks. once it comes out we call it lava, "
        + "remember that, magma inside, lava outside, it's on every exam. there are two main types. shield volcanoes, runny "
        + "lava, flows far, doesn't really explode, like hawaii. and stratovolcanoes, thick lava, the gas can't escape so "
        + "pressure builds and boom, like fuji. pinatubo in ninety one, the ash blocked sunlight and the earth cooled about "
        + "half a degree for almost two years. quiz next week"

    static let englishFacts = """
    TOPIC: How volcanoes form and their two main types
    - A volcano starts with **magma**: molten rock under the Earth's crust, about 1,000 °C and lighter than the surrounding rock, so it rises through cracks.
    - Once magma reaches the surface it is called **lava** — magma is underground, lava is on the surface (a frequent exam question).
    - There are 2 main types, depending on how thick (viscous) the lava is.
    - **Shield volcano**: runny lava that flows far, so it rarely explodes — e.g. Hawaii.
    - **Stratovolcano**: thick lava traps gas, pressure builds up and it erupts violently — e.g. Mount Fuji.
    - Example of impact: Pinatubo's 1991 eruption blocked sunlight with ash and cooled the Earth by about 0.5 °C for almost 2 years.
    - To do: quiz next week.
    """

    static let englishSection = """
    ## Volcanoes: why some ooze and others explode

    Every volcano starts with **magma**, molten rock at about 1,000 °C beneath the crust. Because it is lighter than the rock around it, magma rises through cracks — and once it reaches the surface it is called **lava**.

    > [!tip] Remember (frequent exam question)
    > **Magma** = below the surface · **Lava** = on the surface

    ### Two main types, decided by the lava's thickness
    Whether a volcano flows or explodes depends on ==how viscous its lava is==: thick lava traps gas, so pressure builds until it erupts violently.

    | Type | Lava | Eruption | Example |
    |---|---|---|---|
    | Shield volcano | runny, flows far | rarely explosive | Hawaii |
    | Stratovolcano | thick, traps gas | violent | Mount Fuji |

    > [!example] A volcano can cool the planet
    > Pinatubo's 1991 eruption sent ash high enough to block sunlight, cooling the Earth by about 0.5 °C for almost 2 years.

    - [ ] Prepare for next week's quiz
    """

    static let englishOpening = """
    # Volcanoes: why some ooze while others explode hard enough to cool the planet

    One volcanic eruption cooled the whole Earth by about 0.5 °C for almost two years. Yet most volcanoes never do anything like that — some just let lava ooze out. This note explains what makes the difference.

    > [!summary] Overview
    > Volcanoes start with magma at about 1,000 °C rising through cracks in the crust; at the surface it is called lava. The lava's viscosity splits volcanoes into two types: shield volcanoes with runny lava that rarely explode, and stratovolcanoes whose thick lava traps gas until they erupt violently. Large eruptions can even change the global temperature.
    """
}

extension SourceCleaner {
    static func clean(_ text: String, kind: SourceKind) -> String {
        switch kind {
        case .audio, .recording: return speech(text)
        case .pdf: return pdf(text)
        default: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
