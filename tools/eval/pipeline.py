"""Python mirror of the app's note pipeline, used to tune prompts against the real model.

v0 = the pipeline shipped in build 12 (baseline).
v1 = deep notes: clean → (study notes for long material) → write each section separately → hook intro → takeaways.
"""
import re
from collections import Counter

# ----------------------------------------------------------------------------- helpers

THAI = re.compile(r"[฀-๿]")
LETTER = re.compile(r"[A-Za-z฀-๿]")
TIMESTAMP = re.compile(r"^\[(?:\d{1,2}:)?\d{1,2}:\d{2}\]\s*", re.M)
PAGE = re.compile(r"^\[Page \d+\]\s*$", re.M)


def is_thai(text):
    letters = LETTER.findall(text[:20000])
    return bool(letters) and sum(1 for c in letters if THAI.match(c)) / len(letters) > 0.3


def clean_source(kind, text):
    if kind in ("audio", "recording"):
        text = TIMESTAMP.sub("", text)
        text = re.sub(r"[ \t]{2,}", " ", text)
        return text.strip()
    if kind == "pdf":
        lines = text.split("\n")
        counts = Counter(l.strip() for l in lines if 0 < len(l.strip()) < 90)
        repeated = {l for l, n in counts.items() if n >= 3}
        out = []
        for l in lines:
            s = l.strip()
            if s in repeated or PAGE.match(s) or re.fullmatch(r"\d{1,4}", s):
                continue
            # Join a hard-wrapped line onto the previous one.
            if out and out[-1] and s and not re.search(r"[.!?:;。]$", out[-1]) and (s[0].islower() or s[0] in "(,"):
                out[-1] += " " + s
            else:
                out.append(s)
        text = "\n".join(out)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()
    return text.strip()


def split(text, max_chars):
    if len(text) <= max_chars:
        return [text]
    chunks, cur = [], ""
    for para in text.split("\n"):
        if cur and len(cur) + len(para) + 1 > max_chars:
            chunks.append(cur)
            cur = ""
        while len(para) > max_chars:
            # cut at a space near the limit
            cut = para.rfind(" ", int(max_chars * 0.7), max_chars)
            cut = cut if cut > 0 else max_chars
            chunks.append(para[:cut])
            para = para[cut:].lstrip()
        cur = (cur + "\n" + para) if cur else para
    if cur.strip():
        chunks.append(cur)
    # Avoid a tiny last chunk: merge it into the previous one.
    if len(chunks) > 1 and len(chunks[-1]) < max_chars * 0.3:
        chunks[-2] += "\n" + chunks.pop()
    return chunks


def is_looping(text):
    counts = Counter()
    for line in text.split("\n"):
        k = key(line)
        if len(k) >= 16:
            counts[k] += 1
            if counts[k] >= 3:
                return True
    tail = text[-300:]
    if len(tail) == 300:
        for size in range(20, 101):
            unit = tail[-size:]
            if tail.endswith(unit * 3):
                return True
    return False


def key(line):
    t = line.strip()
    if t.startswith(("#", "> [!", "|", "```")):
        return ""
    return "".join(c for c in line.lower() if not c.isspace() and c not in "-*>#=•")


def dedupe(text):
    seen, out = set(), []
    for line in text.split("\n"):
        k = key(line)
        if len(k) >= 16:
            if k in seen:
                continue
            seen.add(k)
        out.append(line)
    text = "\n".join(out)
    text = re.sub(r"\n{3,}", "\n\n", text)
    lines = text.split("\n")
    while lines and (not lines[-1].strip() or lines[-1].strip().startswith("#") or lines[-1].strip() in (">",)
                     or lines[-1].strip().startswith("> [!")):
        lines.pop()
    return "\n".join(lines).strip()


def strip_fences(text):
    t = text.strip()
    if t.startswith("```"):
        lines = t.split("\n")[1:]
        if lines and lines[-1].strip().startswith("```"):
            lines = lines[:-1]
        t = "\n".join(lines)
    return t.strip()


# ----------------------------------------------------------------------------- v0 (baseline, build 12)

V0_SYNTAX = """FORMAT RULES (Obsidian-flavoured Markdown, the app renders colours from it):
- Start with "# " and a short, specific title.
- Right after the title add a summary callout:
  > [!summary] Summary
  > 2–3 sentences with the core idea.
- Use "## " for main sections and "### " for sub-sections.
- Use bullet lists ("- ") for points. Keep each bullet short.
- Highlight the single most important phrase in a paragraph or bullet with ==double equals==. Use highlights sparingly (max 1 per bullet).
- Use **bold** for key terms.
- Put key terms in a definition callout:
  > [!definition] Term
  > Short explanation.
- Put important insights in:  > [!tip] Title
- Put warnings, caveats or uncertainty in:  > [!warning] Title
- Put review questions in:  > [!question] Review questions
- Put code, formulas or commands in fenced code blocks with a language, e.g. ```python
- Use "- [ ] " for action items.
- Use a Markdown table only when comparing things.
- Never invent facts that are not in the source. If something is unclear, say so in a warning callout.
- Write each fact ONCE. Never repeat a sentence, bullet or section.
- Output only the note. No preamble, no closing remarks."""


def v0_system():
    return f"""You are IntelligenceBook, an expert note-taker. You turn source material into clear, well-structured, colourful study notes that are easy to read and faithful to the source.
Write the note in the same language as the source material (if it is Thai, write in Thai).

FAITHFULNESS (most important):
- Summarise ONLY what is written or said inside <content> … </content>.
- The source name and type (e.g. "Recording", "PDF", "Web link") are labels, NOT content. Never write about what a recording, file or link is.
- Timestamps like [00:12] only mark time; ignore them.
- Speech transcripts can contain small recognition errors; keep the speaker's meaning.
- If the content is short, the note must be short. Do not pad it with general knowledge.

{V0_SYNTAX}"""


V0_SUMMARY = ("Create a SUMMARY note: title, summary callout, \"## Key points\" (key takeaways as bullets with highlights), "
              "1–4 sections that group the main ideas, definition callouts for key terms, and a short question callout at the end.")
V0_EXTRACT = ("You extract the important information from a part of a longer document or lecture transcript (inside <content>). "
              "Output 4–8 concise bullet points (\"- \") with the key facts, definitions, numbers, names and arguments. "
              "Keep the original language of the text. Ignore timestamps. Each point once, no repetition. "
              "Do not add anything that is not in the text. Output only the bullets.")


def v0_short(n):
    if n < 600:
        return ("The content is very short. Create a SHORT note: a \"# \" title, one summary callout with 1–2 sentences, "
                "then only the points actually stated in the content as 1–5 bullets. "
                "Do NOT add definitions, questions, sections or anything not stated.")
    return ("The content is short. Create a compact note: title, summary callout, then at most 2 short sections "
            "with bullets of what the content actually says. Add a definition or question callout only if the content supports it.")


def run_v0(llm, sources, style="summary", log=print):
    budget = 10000
    n = sum(len(s["text"]) for s in sources)
    corpus = "\n\n".join(f"[Source {i+1} · name: {s['title']}]\n<content>\n{s['text']}\n</content>"
                         for i, s in enumerate(sources))
    material = corpus
    if len(corpus) > budget:
        chunks = [p for s in sources for p in split(s["text"], budget)]
        digest = []
        for i, c in enumerate(chunks):
            b, _ = llm.chat(V0_EXTRACT, f"<content>\n{c}\n</content>", 280, temperature=0.2, guard=is_looping,
                            label=f"v0 extract {i+1}")
            digest.append(f"Part {i+1}:\n{b}")
        material = "<content>\n" + "\n\n".join(digest)[:budget] + "\n</content>"
    task = v0_short(n) if n < 2500 else V0_SUMMARY
    mt = 320 if n < 600 else 700 if n < 2500 else 2200
    note, _ = llm.chat(v0_system(), f"{task}\n\nSOURCE:\n{material}", mt, guard=is_looping, label="v0 write")
    return dedupe(strip_fences(note))


# ----------------------------------------------------------------------------- v1 (deep notes)

def lang_line(lang):
    return {
        "thai": "Write everything in Thai (ภาษาไทย). Keep technical terms in English in parentheses after the Thai term when the source uses them.",
        "english": "Write everything in English.",
    }[lang]


def kind_phrase(kinds):
    if kinds & {"audio", "recording"}:
        return "a transcript of spoken audio (a lecture, talk or voice memo) made by speech recognition"
    if "pdf" in kinds:
        return "text extracted from a PDF"
    if "web" in kinds:
        return "a web article"
    return "text"


FORMAT_SECTION = """FORMAT (Obsidian Markdown; the app renders colours from it):
- "### " for sub-topics inside the section.
- Explanations as short paragraphs (2–4 sentences). Bullets ("- ") for lists of items, steps or examples.
- **bold** for key terms; ==highlight== for the single most important phrase of a paragraph (at most one).
- A key term with its meaning:
  > [!definition] Term
  > what it means, in one or two sentences.
- An example from the material:
  > [!example] Example
  > the example, with its numbers.
- Something worth remembering or an exam hint:  > [!tip] Title
- A common mistake, caveat or limit:  > [!warning] Title
- Formulas or code in fenced code blocks.
- A Markdown table only when comparing several things.
- Output only the section. No preamble, no closing remarks."""


def v1_system(lang, kinds):
    return f"""You are an expert teacher writing outstanding study notes — the kind a top student would share with a friend who missed class.
{lang_line(lang)}

The material is {kind_phrase(kinds)}.

HOW TO WRITE
- First understand what is being taught, then EXPLAIN it in your own words, the way a good textbook does. Never copy the speaker's sentences, filler words or chit-chat.
- For every important idea say what it is, why it matters and how it works, and include the examples, numbers and names from the material.
- Be thorough: a reader who never saw the material must understand it fully from your note.
- Stay faithful: never invent facts, numbers, names or claims. You may add a short clarification of a term only if it is common knowledge.
- Speech recognition makes mistakes: when a word is clearly misheard, write the correct term the speaker meant.
- Ignore greetings, attendance, jokes and classroom management. Keep assignments, deadlines and exam hints.
- Say each thing once."""


def v1_section_prompt(unit_text, index, total, covered, from_notes, style):
    where = f"part {index} of {total}" if total > 1 else "the whole material"
    covered_txt = ""
    if covered:
        covered_txt = "\nALREADY COVERED in earlier sections (do not repeat these):\n" + "\n".join(f"- {c}" for c in covered) + "\n"
    source_label = "STUDY NOTES of this part" if from_notes else "MATERIAL"
    depth = {
        "summary": "Cover every main idea of this part with a clear explanation (aim for 250–450 words).",
        "studyGuide": "Explain every concept of this part in depth with its examples (aim for 400–700 words). Add a definition callout for each key term.",
        "outline": "Write it as a nested bullet outline (\"- \" and indented \"  - \"), each bullet a full, informative phrase.",
        "questions": "Write 3–5 review questions about this part, each as a > [!question] callout followed by \"**Answer:**\" with a full answer.",
    }[style]
    return f"""<{source_label.lower().replace(' ', '_')}>
{unit_text}
</{source_label.lower().replace(' ', '_')}>
{covered_txt}
TASK: Write the note section for {where}.
- Start with a "## " heading that names the topic of this part (not "Part {index}").
- {depth}
- Organise it with "### " sub-topics when the part covers more than one idea.

{FORMAT_SECTION}"""


V1_STUDY_NOTES = """Read this part of the material and write dense study notes about it.
- Start with a line "TOPIC: " and the topic of this part in a few words.
- Then 6–12 bullets. Each bullet is a complete sentence that explains one idea: what, why or how, with any example, number or name.
- Include definitions of terms, steps of processes, causes and effects, and any exam hint or assignment.
- Skip filler and chit-chat. Do not invent anything."""


def v1_intro_prompt(body, style):
    return f"""<note_body>
{body}
</note_body>

TASK: Write the OPENING of this note. Output exactly these three parts:
1. "# " and a specific, informative title (not "Summary", not "Lecture notes").
2. A hook paragraph (2–4 sentences) that makes the reader want to keep reading: open with the most surprising fact, an intriguing question, or why this topic matters in real life — taken from the note body. Then say in one sentence what the reader will learn.
3. The big picture:
> [!summary] Overview
> 3–5 sentences that connect the main ideas of the whole note into one story.

Output only these three parts."""


def v1_outro_prompt(body, style):
    nq = {"summary": 4, "studyGuide": 6, "outline": 3, "questions": 0}[style]
    q = ""
    if nq:
        q = f"""
2. "## Review questions" then {nq} questions that test understanding (not just recall). Format each as:
> [!question] the question
> **Answer:** a complete answer in 1–3 sentences."""
    return f"""<note_body>
{body}
</note_body>

TASK: Write the ENDING of this note. Output:
1. "## Key takeaways" then 5–7 bullets ("- "). Each bullet is one full sentence with a key insight from the note; highlight its key phrase with ==double equals==.{q}

Output only these parts."""


SHORT_PROMPT = """<material>
{text}
</material>

TASK: This material is short. Write a short, clear note about it:
- "# " and a specific title.
- One or two sentences saying what this is about, written to catch the reader's interest.
- The points that are actually in the material, as bullets with full sentences (keep every number and name).
- If the material contains to-dos or next steps, list them as "- [ ] " items under "## Next steps".
Do NOT add anything that is not in the material. Output only the note."""


def condense_body(sections, limit=9000):
    """Text given to the intro/outro writers: full sections, or headings + first paragraphs when long."""
    body = "\n\n".join(sections)
    if len(body) <= limit:
        return body
    per = max(600, limit // max(1, len(sections)))
    return "\n\n".join(s[:per] for s in sections)


def first_heading(section):
    for l in section.split("\n"):
        if l.startswith("## "):
            return l[3:].strip()
    return section.strip().split("\n")[0][:60]


def gist(section):
    head = first_heading(section)
    subs = [l[4:].strip() for l in section.split("\n") if l.startswith("### ")]
    return head + (": " + ", ".join(subs[:5]) if subs else "")


def fix_section(text):
    t = dedupe(strip_fences(text))
    # Demote a stray "# " title to "## ".
    t = re.sub(r"^# ", "## ", t, flags=re.M)
    return t


def run_v1(llm, sources, style="summary", language="auto", cfg=None, log=print):
    cfg = cfg or {}
    chunk_chars = cfg.get("chunk_chars", 6000)
    max_units = cfg.get("max_units", 6)
    temp = cfg.get("temperature", 0.4)
    rp = cfg.get("rep_penalty", 1.1)
    kinds = {s["kind"] for s in sources}
    texts = [clean_source(s["kind"], s["text"]) for s in sources]
    corpus = "\n\n".join(texts)
    lang = language if language != "auto" else ("thai" if is_thai(corpus) else "english")
    system = v1_system(lang, kinds)
    n = len(corpus)

    def chat(prompt, mt, label, t=temp, cont=True):
        out, cut = llm.chat(system, prompt, mt, temperature=t, rep_penalty=rp, guard=is_looping, label=label)
        if cut and cont:
            more, _ = llm.chat(system, prompt + "\n\n---\nWHAT YOU WROTE SO FAR (cut off by length):\n" + out +
                               "\n---\nContinue exactly where it stops. Do not repeat anything. Output only the continuation.",
                               mt // 2, temperature=t, rep_penalty=rp, guard=is_looping, label=label + " (cont)")
            out = out + more
        return out

    # Very short material: one compact call, no padding.
    if n < cfg.get("short_chars", 1200):
        note = chat(SHORT_PROMPT.format(text=corpus), 500, "short")
        return dedupe(strip_fences(note))

    chunks = []
    for t in texts:
        chunks += split(t, chunk_chars)

    # Long material: compress each chunk into study notes, then group them into ≤ max_units sections.
    from_notes = len(chunks) > max_units
    if from_notes:
        notes = []
        for i, c in enumerate(chunks):
            sn = chat(f"<material>\n{c}\n</material>\n\n{V1_STUDY_NOTES}", 650, f"study {i+1}/{len(chunks)}", t=0.3, cont=False)
            notes.append(dedupe(sn))
        per = -(-len(notes) // max_units)
        units = ["\n\n".join(notes[i:i + per]) for i in range(0, len(notes), per)]
    else:
        units = chunks

    mt = {"summary": 900, "studyGuide": 1300, "outline": 800, "questions": 700}[style]
    sections, covered = [], []
    for i, u in enumerate(units):
        s = chat(v1_section_prompt(u, i + 1, len(units), covered, from_notes, style), mt, f"section {i+1}/{len(units)}")
        s = fix_section(s)
        sections.append(s)
        covered.append(gist(s))

    body = condense_body(sections)
    intro = dedupe(strip_fences(chat(v1_intro_prompt(body, style), 450, "intro")))
    outro = dedupe(strip_fences(chat(v1_outro_prompt(body, style), 900 if style != "questions" else 400, "outro")))
    if not intro.startswith("# "):
        intro = "# " + (first_heading(sections[0]) if sections else "Note") + "\n\n" + intro
    return dedupe("\n\n".join([intro] + sections + [outro]))


# ----------------------------------------------------------------------------- v2 (understand → explain → frame)
#
# Lessons from run 1 (v1):
# - When the section writer sees the raw transcript, a 3B model copies spoken sentences ("อ่ะ", "นะครับ").
# - A "continue" pass restarts the section from scratch → whole sections repeated.
# - Temperature 0.4 + abstract rewriting → invented/inverted facts.
# v2: deterministic clean-up of speech, small chunks, one "explain" pass per chunk with a worked example,
#     the frame (title/hook/overview, takeaways/questions) written from the explained sections only.

FILLER_TOKENS = {
    "เอ่อ", "อ่ะ", "อะ", "อ้า", "อ๋อ", "เออ", "อืม", "อืมม", "แบบว่า", "ก็คือว่า", "คือว่า", "นะ", "นะครับ", "ครับ",
    "ค่ะ", "คะ", "นะคะ", "จ้ะ", "จ้า", "โอเค", "โอเคนะครับ", "ใช่มั้ย", "ใช่ไหม", "เนอะ", "อ่า", "uh", "um", "uhm",
    "erm", "like,", "okay", "okay,", "OK", "ok", "so,",
}
PARTICLE_SUFFIX = re.compile(r"(?:นะครับ|นะคะ|ครับ|ค่ะ)$")


def preclean_speech(text):
    """Removes timestamps, filler words and polite particles from a speech transcript; Thai numbers → digits."""
    import thainum
    text = thainum.convert(TIMESTAMP.sub("", text))
    out_lines = []
    for line in text.split("\n"):
        tokens = []
        for tok in line.split():
            if tok in FILLER_TOKENS:
                continue
            tok2 = PARTICLE_SUFFIX.sub("", tok)
            if tok2:
                tokens.append(tok2)
        if tokens:
            out_lines.append(" ".join(tokens))
    return "\n".join(out_lines)


V2_EXAMPLE_TH = """EXAMPLE
<material>
วันนี้เราจะคุยเรื่องดอกเบี้ยทบต้น compound interest ก็คือดอกเบี้ยที่คิดจากเงินต้นบวกดอกเบี้ยเดิมที่สะสมไว้ ต่างจากดอกเบี้ยธรรมดาที่คิดจากเงินต้นอย่างเดียว สมมุติฝากหนึ่งหมื่นบาท ดอกเบี้ยปีละสิบเปอร์เซ็นต์ ปีแรกได้หนึ่งพัน ปีที่สองได้หนึ่งพันหนึ่งร้อย เพราะคิดจากหนึ่งหมื่นหนึ่งพัน ยิ่งนานยิ่งโตเร็ว เลยต้องเริ่มออมเร็ว ข้อสอบชอบออกให้คำนวณสองปีนะ
</material>
OUTPUT
## ดอกเบี้ยทบต้น: ทำไมเงินออมยิ่งนานยิ่งโตเร็ว

**ดอกเบี้ยทบต้น (Compound interest)** คือดอกเบี้ยที่คำนวณจากเงินต้นรวมกับดอกเบี้ยที่สะสมไว้แล้ว ต่างจาก **ดอกเบี้ยธรรมดา** ที่คิดจากเงินต้นเพียงอย่างเดียว ผลคือดอกเบี้ยจะ ==เพิ่มขึ้นทุกปีแม้อัตราดอกเบี้ยเท่าเดิม== เงินจึงเติบโตเร็วขึ้นเรื่อยๆ ตามเวลา

> [!example] ตัวอย่าง
> ฝาก 10,000 บาท ดอกเบี้ย 10% ต่อปี
> - ปีที่ 1: ได้ดอกเบี้ย 1,000 บาท → รวม 11,000 บาท
> - ปีที่ 2: ได้ดอกเบี้ย 1,100 บาท (คิดจาก 11,000) → รวม 12,100 บาท

> [!tip] ข้อคิดและข้อสอบ
> เพราะเงินยิ่งโตเร็วขึ้นตามเวลา การเริ่มออมเร็วจึงได้เปรียบ — ข้อสอบมักให้คำนวณดอกเบี้ยทบต้น 2 ปี
"""

V2_EXAMPLE_EN = """EXAMPLE
<material>
so today compound interest, it's interest calculated on the principal plus the interest you already earned, unlike simple interest which is only on the principal. say you put in ten thousand at ten percent a year, first year you get a thousand, second year eleven hundred because it's on eleven thousand. the longer the faster it grows so start saving early. the exam usually asks you to compute two years
</material>
OUTPUT
## Compound interest: why savings grow faster over time

**Compound interest** is interest calculated on the principal *plus* the interest already earned, unlike **simple interest**, which is calculated on the principal only. As a result the interest ==grows every year even at the same rate==, so money grows faster and faster over time.

> [!example] Example
> Deposit 10,000 at 10% per year
> - Year 1: 1,000 interest → 11,000 in total
> - Year 2: 1,100 interest (on 11,000) → 12,100 in total

> [!tip] Takeaway and exam hint
> Because growth speeds up over time, starting to save early pays off — exams often ask for a 2-year compound interest calculation.
"""


def v2_system(lang, kinds):
    spoken = bool(kinds & {"audio", "recording"})
    src = kind_phrase(kinds)
    speech_rules = ""
    if spoken:
        speech_rules = """
- The material is SPEECH turned into text by speech recognition. Speakers ramble, repeat themselves and use filler. \
Turn it into clean WRITTEN language like a textbook. Never copy the speaker's sentences.
- Speech recognition mishears words. When a word is clearly wrong, write the term the speaker meant.
- Numbers are often spelled out in words ("สามสิบห้า", "ten thousand"). Write them as digits (35, 10,000).
- Skip greetings, attendance, jokes and classroom management. Keep assignments, deadlines and exam hints."""
    return f"""You are an expert teacher who writes outstanding study notes.
{lang_line(lang)}
The material is {src}.

RULES
- Understand first, then EXPLAIN in your own words: what each idea is, why it matters, how it works.
- Keep every example, number, formula and name from the material, and keep cause and effect in the right direction.
- Never invent facts. If the material doesn't say it, don't write it.{speech_rules}
- Say each thing once."""


def v2_explain_prompt(chunk, lang, covered, style):
    example = V2_EXAMPLE_TH if lang == "thai" else V2_EXAMPLE_EN
    cov = ""
    if covered:
        cov = "\nTopics already written in earlier sections (don't explain them again, only add what is new):\n" + \
              "\n".join(f"- {c}" for c in covered[-6:]) + "\n"
    depth = {
        "summary": "Explain every idea in this material clearly (about 200–400 words).",
        "studyGuide": "Explain every idea in depth (about 350–600 words); add a > [!definition] callout for each key term.",
        "outline": "Use a nested bullet outline (\"- \" and indented \"  - \") of full informative phrases instead of paragraphs.",
        "questions": "After the explanation add 2–3 > [!question] callouts, each with a line \"> **Answer:** …\".",
    }[style]
    return f"""Write one section of a study note that explains the material below, like the example.

{example}
NOW THE REAL MATERIAL
<material>
{chunk}
</material>
{cov}
INSTRUCTIONS
- Start with "## " and a specific heading that names the idea (a short phrase, can say why it matters).
- {depth}
- Short paragraphs; **bold** key terms; ==highlight== the single most important phrase of a paragraph.
- Put worked examples with their numbers in a > [!example] callout; definitions in > [!definition] Term; \
exam hints or insights in > [!tip]; caveats or common mistakes in > [!warning]. "### " sub-headings if the part has several ideas.
- Use a Markdown table when the material compares several things.
OUTPUT (only the section):"""


def v2_frame_open_prompt(outline_text, lang):
    return f"""Here is the outline of a study note (section headings with their key points):
<outline>
{outline_text}
</outline>

Write the OPENING of this note. Output exactly:
# <a specific, informative title for the whole note>

<a hook paragraph of 2–3 sentences that makes people want to read on: start with the most surprising fact, a striking number, \
or a question the note answers — taken from the outline — then say what the reader will understand by the end>

> [!summary] Overview
> <3–5 sentences that connect all the main ideas into one story, in order>

Only output the opening."""


def v2_frame_close_prompt(outline_text, style):
    nq = {"summary": 4, "studyGuide": 6, "outline": 3, "questions": 0}[style]
    q = ""
    if nq:
        q = f"""

## Review questions

> [!question] <question 1 — tests understanding, not just recall>
> **Answer:** <complete answer>

(… {nq} questions in total, same format)"""
    return f"""Here is the outline of a study note (section headings with their key points):
<outline>
{outline_text}
</outline>

Write the ENDING of this note. Output exactly:
## Key takeaways

- <one full sentence with a key insight, its key phrase in ==highlight==>
(… 4–6 bullets){q}

Only output the ending. Write the headings in the language of the note."""


def outline_of(sections, per_section=420):
    """Headings + the first lines of every section, for the framing calls."""
    parts = []
    for s in sections:
        lines = [l for l in s.split("\n") if l.strip()]
        head = next((l for l in lines if l.startswith("## ")), "## (section)")
        body = " ".join(l.strip("> ").strip() for l in lines if not l.startswith("#") and not l.strip().startswith("> [!"))
        parts.append(head + "\n" + body[:per_section])
    return "\n\n".join(parts)


V2_SHORT = """Turn this short material into a short, clear note, written properly (not copied).

<material>
{text}
</material>

Output:
# <specific title>

<1–2 sentences: what this is about, written to catch interest>

- <each point that is actually in the material, as a full clear sentence, numbers as digits>
(if the material has to-dos or next steps, add "## Next steps" with "- [ ] " items)

Do NOT add anything that is not in the material. Only output the note."""


HEADING_SYNONYMS = {"key takeaways", "review questions", "สรุป", "summary", "overview"}


def merge_sections(sections):
    """Drops sections that are empty, and merges a section into the previous one when they share a heading."""
    out = []
    for s in sections:
        s = s.strip()
        if len(re.sub(r"\s", "", s)) < 40:
            continue
        h = first_heading(s).strip().lower()
        if out and first_heading(out[-1]).strip().lower() == h:
            body = "\n".join(l for l in s.split("\n") if not l.startswith("## "))
            out[-1] += "\n\n" + body.strip()
        else:
            out.append(s)
    return out


def run_v2(llm, sources, style="summary", language="auto", cfg=None, log=print):
    cfg = cfg or {}
    chunk_chars = cfg.get("v2_chunk_chars", 3500)
    temp = cfg.get("v2_temperature", 0.3)
    rp = cfg.get("rep_penalty", 1.1)
    max_chunks = cfg.get("v2_max_chunks", 30)
    kinds = {s["kind"] for s in sources}
    texts = []
    for s in sources:
        t = clean_source(s["kind"], s["text"])
        if s["kind"] in ("audio", "recording"):
            t = preclean_speech(t)
        texts.append(t)
    corpus = "\n\n".join(texts)
    lang = language if language != "auto" else ("thai" if is_thai(corpus) else "english")
    system = v2_system(lang, kinds)

    def chat(prompt, mt, label, t=temp):
        out, _ = llm.chat(system, prompt, mt, temperature=t, rep_penalty=rp, guard=is_looping, label=label)
        return dedupe(strip_fences(out))

    if len(corpus) < cfg.get("v2_short_chars", 1200):
        return chat(V2_SHORT.format(text=corpus), 600, "short")

    chunks = []
    for t in texts:
        chunks += split(t, chunk_chars)
    if len(chunks) > max_chunks:  # very long: merge neighbours instead of dropping material
        per = -(-len(chunks) // max_chunks)
        chunks = ["\n".join(chunks[i:i + per]) for i in range(0, len(chunks), per)]

    mt = {"summary": 800, "studyGuide": 1100, "outline": 700, "questions": 900}[style]
    sections, covered = [], []
    for i, c in enumerate(chunks):
        s = chat(v2_explain_prompt(c, lang, covered, style), mt, f"explain {i+1}/{len(chunks)}")
        s = re.sub(r"^# ", "## ", s, flags=re.M)
        if not s.lstrip().startswith("## "):
            s = "## " + (s.split("\n")[0][:60] if s else f"Part {i+1}") + "\n\n" + "\n".join(s.split("\n")[1:])
        sections.append(s)
        covered.append(first_heading(s))
    sections = merge_sections(sections)

    outline = outline_of(sections, per_section=max(200, 6000 // max(1, len(sections))))
    opening = chat(v2_frame_open_prompt(outline, lang), 450, "open")
    if not opening.lstrip().startswith("# "):
        opening = "# " + first_heading(sections[0]) + "\n\n" + opening
    closing = chat(v2_frame_close_prompt(outline, style), 900, "close") if style != "outline" or True else ""
    return dedupe("\n\n".join([opening] + sections + [closing]))


# ----------------------------------------------------------------------------- v3 (facts → explain → frame, few-shot as chat turns)
#
# Run 3 (v2) lessons: an inline example leaks into the note; the writer copies raw speech when it sees it;
# the most accurate thing a 3B model does is extracting short written facts (v0 key points were correct).
# v3: 1) every chunk → written study FACTS (few-shot turn, low temperature)
#     2) facts (never raw text) → explained SECTIONS (few-shot turn)
#     3) opening (title, hook, overview) from the sections; ending (takeaways, questions) from the facts.

EX_TH_SPEECH = ("โอเค เอ่อ วันนี้นะครับเรื่องภูเขาไฟ ภูเขาไฟเนี่ยมันเกิดจากแมกม่า magma ก็คือหินที่มันหลอมละลายอยู่ใต้เปลือกโลก "
                "มันร้อนมาก ประมาณพันองศา แล้วมันเบากว่าหินรอบๆ ก็เลยดันขึ้นมาตามรอยแตก พอออกมาข้างนอกแล้วเราเรียกว่าลาวา lava นะ "
                "จำไว้ ข้อสอบชอบถาม แมกม่าอยู่ข้างใน ลาวาอยู่ข้างนอก อ่ะ ทีนี้ภูเขาไฟมีกี่แบบ มีสองแบบหลักๆ "
                "แบบแรกภูเขาไฟรูปโล่ shield volcano ลาวาเหลว ไหลไปไกล ไม่ค่อยระเบิด อย่างฮาวาย แบบที่สองภูเขาไฟสลับชั้น "
                "stratovolcano ลาวาหนืด แก๊สออกไม่ได้ ก็สะสมแรงดันแล้วระเบิดรุนแรง อย่างฟูจิ เอ่อ ภูเขาไฟปินาตูโบปีเก้าหนึ่ง "
                "ระเบิดแล้วเถ้าไปบังแดด โลกเย็นลงประมาณครึ่งองศาเกือบสองปี เดี๋ยวสัปดาห์หน้าควิซนะ")
EX_TH_FACTS = """TOPIC: ภูเขาไฟเกิดขึ้นอย่างไรและมีกี่แบบ
- ภูเขาไฟเกิดจาก **แมกมา (magma)** คือหินหลอมเหลวใต้เปลือกโลกที่ร้อนประมาณ 1,000 °C และเบากว่าหินรอบข้าง จึงดันตัวขึ้นมาตามรอยแตกของเปลือกโลก
- เมื่อแมกมาออกมาสู่ผิวโลกจะเรียกว่า **ลาวา (lava)** — แมกมาอยู่ใต้ผิวโลก ลาวาอยู่บนผิวโลก (อาจารย์บอกว่าออกข้อสอบบ่อย)
- ภูเขาไฟมี 2 แบบหลัก แบ่งตามความหนืดของลาวา
- **ภูเขาไฟรูปโล่ (shield volcano)**: ลาวาเหลว ไหลไปได้ไกล จึงไม่ค่อยระเบิด เช่น ภูเขาไฟในฮาวาย
- **ภูเขาไฟสลับชั้น (stratovolcano)**: ลาวาหนืดจนแก๊สออกไม่ได้ แรงดันจึงสะสมจนระเบิดรุนแรง เช่น ภูเขาไฟฟูจิ
- ตัวอย่างผลกระทบ: ภูเขาไฟปินาตูโบระเบิดในปี 1991 เถ้าถ่านบังแสงอาทิตย์ ทำให้โลกเย็นลงประมาณ 0.5 °C นานเกือบ 2 ปี
- งานที่ต้องทำ: มีควิซสัปดาห์หน้า"""
EX_TH_SECTION = """## ภูเขาไฟ: ทำไมบางลูกไหลเอื่อย แต่บางลูกระเบิดรุนแรง

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

- [ ] เตรียมตัวควิซสัปดาห์หน้า"""

EX_EN_SPEECH = ("ok so uh today volcanoes. a volcano starts with magma, that's melted rock under the crust, it's like a thousand "
                "degrees and lighter than the rock around it so it pushes up through cracks. once it comes out we call it lava, "
                "remember that, magma inside, lava outside, it's on every exam. there are two main types. shield volcanoes, runny "
                "lava, flows far, doesn't really explode, like hawaii. and stratovolcanoes, thick lava, the gas can't escape so "
                "pressure builds and boom, like fuji. pinatubo in ninety one, the ash blocked sunlight and the earth cooled about "
                "half a degree for almost two years. quiz next week")
EX_EN_FACTS = """TOPIC: How volcanoes form and their two main types
- A volcano starts with **magma**: molten rock under the Earth's crust, about 1,000 °C and lighter than the surrounding rock, so it rises through cracks.
- Once magma reaches the surface it is called **lava** — magma is underground, lava is on the surface (a frequent exam question).
- There are 2 main types, depending on how thick (viscous) the lava is.
- **Shield volcano**: runny lava that flows far, so it rarely explodes — e.g. Hawaii.
- **Stratovolcano**: thick lava traps gas, pressure builds up and it erupts violently — e.g. Mount Fuji.
- Example of impact: Pinatubo's 1991 eruption blocked sunlight with ash and cooled the Earth by about 0.5 °C for almost 2 years.
- To do: quiz next week."""
EX_EN_SECTION = """## Volcanoes: why some ooze and others explode

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

- [ ] Prepare for next week's quiz"""


def v3_facts_system(lang, spoken):
    lang_rule = "Write in Thai (ภาษาไทย), keeping English technical terms in parentheses." if lang == "thai" else "Write in English."
    speech = (" The material is a speech-recognition transcript: ignore filler words, greetings and classroom chit-chat, "
              "and fix clearly misheard words.") if spoken else ""
    return (f"You turn material into accurate study facts. {lang_rule}{speech}\n"
            "Output a line \"TOPIC: \" with the topic, then bullets. Each bullet is one complete, clear written sentence "
            "with one fact, definition, cause→effect, step, example (with its numbers), name, exam hint or to-do. "
            "Cover everything important, in order. Keep cause and effect in the right direction. "
            "Copy every number exactly as written in the material and never calculate new numbers. "
            "Only facts that are in the material — never add your own.")


def v3_write_system(lang):
    lang_rule = "Write in Thai (ภาษาไทย), keeping English technical terms in parentheses." if lang == "thai" else "Write in English."
    return (f"You are an expert teacher who turns study facts into a beautiful, easy-to-understand note section. {lang_rule}\n"
            "Explain the facts so they connect into an understandable story: what each idea is, why it happens, how it works. "
            "Use every fact given and keep all numbers, names and examples exactly, but never add a fact, number or "
            "example that is not given and never calculate new numbers. Make a table only when the facts give every value in it. "
            "Format: \"## \" heading that names the idea in an interesting way; short paragraphs; **bold** key terms; "
            "==highlight== the most important phrase; > [!definition] Term, > [!example] Title, > [!tip] Title, "
            "> [!warning] Title callouts; a table when comparing; \"- [ ] \" for to-dos. Output only the section.")


def split_facts(text):
    topic, bullets = "", []
    for line in text.split("\n"):
        t = line.strip()
        if t.upper().startswith("TOPIC:"):
            topic = topic or t[6:].strip()
        elif t.startswith(("- ", "* ", "• ")) and len(t) > 6:
            bullets.append("- " + t[2:].strip())
    return topic, bullets


def run_v3(llm, sources, style="summary", language="auto", cfg=None, log=print, _texts=None):
    cfg = cfg or {}
    chunk_chars = cfg.get("v3_chunk_chars", 3500)
    group_chars = cfg.get("v3_group_chars", 2200)
    rp = cfg.get("rep_penalty", 1.1)
    kinds = {s["kind"] for s in sources}
    spoken = bool(kinds & {"audio", "recording"})
    texts = _texts
    if texts is None:
        texts = []
        for s in sources:
            t = clean_source(s["kind"], s["text"])
            if s["kind"] in ("audio", "recording"):
                t = preclean_speech(t)
            texts.append(t)
    corpus = "\n\n".join(texts)
    lang = language if language != "auto" else ("thai" if is_thai(corpus) else "english")
    th = lang == "thai"
    ex_src, ex_facts, ex_sec = (EX_TH_SPEECH, EX_TH_FACTS, EX_TH_SECTION) if th else (EX_EN_SPEECH, EX_EN_FACTS, EX_EN_SECTION)

    def facts_of(text, label):
        out, _ = llm.chat(v3_facts_system(lang, spoken), f"<material>\n{text}\n</material>", 700, temperature=0.2,
                          rep_penalty=rp, guard=is_looping, label=label,
                          history=[(f"<material>\n{ex_src}\n</material>", ex_facts)])
        return split_facts(dedupe(out))

    def write_section(topic, bullets, label, extra=""):
        facts = (f"TOPIC: {topic}\n" if topic else "") + "\n".join(bullets)
        out, _ = llm.chat(v3_write_system(lang) + extra, f"<facts>\n{facts}\n</facts>", 1000, temperature=0.3,
                          rep_penalty=rp, guard=is_looping, label=label,
                          history=[(f"<facts>\n{ex_facts}\n</facts>", ex_sec)])
        s = dedupe(strip_fences(out))
        s = re.sub(r"^# ", "## ", s, flags=re.M)
        if not s.lstrip().startswith("## "):
            s = f"## {topic or 'Notes'}\n\n{s}"
        return s

    # 1. facts per chunk
    chunks = []
    for t in texts:
        chunks += split(t, chunk_chars)
    groups = []  # (topic, bullets)
    seen = set()
    seen_grams = []
    for i, c in enumerate(chunks):
        topic, bullets = facts_of(c, f"facts {i+1}/{len(chunks)}")
        fresh = []
        for b in bullets:
            k = key(b)
            if not k or k in seen:
                continue
            if globals().get("_dedupe_mode") == "fuzzy":
                if near_duplicate(b, seen_grams):
                    continue
                seen_grams.append(trigrams(b))
            seen.add(k)
            fresh.append(b)
        if fresh:
            groups.append((topic, fresh))

    all_facts = [b for _, bs in groups for b in bs]
    if not all_facts:
        return "# Note\n\n" + corpus[:2000]

    # Short material: a single section is the whole body.
    # 2. merge neighbouring fact groups up to group_chars, then write one section per group
    units = []
    for topic, bs in groups:
        if units and sum(len(x) for x in units[-1][1]) + sum(len(x) for x in bs) <= group_chars:
            units[-1][1].extend(bs)
        else:
            units.append([topic, list(bs)])
    sections = [write_section(t, bs, f"write {i+1}/{len(units)}") for i, (t, bs) in enumerate(units)]
    sections = merge_sections(sections)

    # 3. frame
    outline = outline_of(sections, per_section=max(200, 5000 // max(1, len(sections))))
    frame_sys = ("You write the opening of study notes. " + ("Write in Thai (ภาษาไทย)." if th else "Write in English.") +
                 " Use only what is in the outline. Never mention 'the outline', 'the transcript' or 'the speaker'.")
    ex_outline = outline_of([ex_sec], 500)
    ex_open = ("""# ภูเขาไฟ: ทำไมบางลูกไหลเอื่อย แต่บางลูกระเบิดจนโลกเย็นลง

รู้ไหมว่าการระเบิดของภูเขาไฟลูกเดียวทำให้ทั้งโลกเย็นลงได้ราว 0.5 °C นานเกือบ 2 ปี? ความรุนแรงขนาดนั้นไม่ได้เกิดกับภูเขาไฟทุกลูก — \
บางลูกแค่มีลาวาไหลเอื่อยๆ โน้ตนี้จะพาไปเข้าใจว่าอะไรเป็นตัวตัดสิน

> [!summary] ภาพรวม
> ภูเขาไฟเกิดจากแมกมาที่ร้อนราว 1,000 °C ดันตัวขึ้นมาตามรอยแตกของเปลือกโลก และเรียกว่าลาวาเมื่อออกมาถึงผิวโลก \
ความหนืดของลาวาเป็นตัวแบ่งภูเขาไฟเป็น 2 แบบ: ภูเขาไฟรูปโล่ที่ลาวาเหลวและไม่ค่อยระเบิด กับภูเขาไฟสลับชั้นที่ลาวาหนืดจนแก๊สสะสมแรงดันและระเบิดรุนแรง \
การระเบิดครั้งใหญ่ส่งผลไปไกลถึงอุณหภูมิของทั้งโลก""" if th else """# Volcanoes: why some ooze while others explode hard enough to cool the planet

One volcanic eruption cooled the whole Earth by about 0.5 °C for almost two years. Yet most volcanoes never do anything like that — \
some just let lava ooze out. This note explains what makes the difference.

> [!summary] Overview
> Volcanoes start with magma at about 1,000 °C rising through cracks in the crust; at the surface it is called lava. \
The lava's viscosity splits volcanoes into two types: shield volcanoes with runny lava that rarely explode, and stratovolcanoes \
whose thick lava traps gas until they erupt violently. Large eruptions can even change the global temperature.""")
    open_task = "Write the opening of this note: a \"# \" title, a hook paragraph that makes people want to read on (start from the most surprising fact or number), and a > [!summary] overview that connects all the main ideas."
    opening, _ = llm.chat(frame_sys, f"<outline>\n{outline}\n</outline>\n\n{open_task}", 450, temperature=0.4,
                          rep_penalty=rp, guard=is_looping, label="open",
                          history=[(f"<outline>\n{ex_outline}\n</outline>\n\n{open_task}", ex_open)])
    _unused = (frame_sys, f"""<outline>
{outline}
</outline>

Write the opening of this note, exactly in this form:
# <specific, informative title>

<hook: 2–3 sentences that make people want to read on — start with the most surprising fact or striking number from the outline, or the question this note answers; end with what the reader will understand>

> [!summary] {'ภาพรวม' if th else 'Overview'}
> <3–5 sentences that connect all the main ideas into one story>""")
    opening = dedupe(strip_fences(opening))
    if not opening.lstrip().startswith("# "):
        opening = "# " + first_heading(sections[0]) + "\n\n" + opening

    facts_text = "\n".join(all_facts)
    if len(facts_text) > 5000:
        step = len(all_facts) / (5000 / (len(facts_text) / len(all_facts)))
        facts_text = "\n".join(all_facts[int(i * step)] for i in range(int(len(all_facts) / step)))
    nq = {"summary": 4, "studyGuide": 6, "outline": 3, "questions": 8}[style]
    h_take, h_q, h_ans = ("ประเด็นสำคัญ", "คำถามทบทวน", "คำตอบ") if th else ("Key takeaways", "Review questions", "Answer")
    ending, _ = llm.chat(("You write the end of study notes. " + ("Write in Thai (ภาษาไทย)." if th else "Write in English.") +
                          " Use only the given facts."), f"""<facts>
{facts_text}
</facts>

Write exactly:
## {h_take}
- <one full sentence with the most important insight; its key phrase in ==highlight==>
(5 bullets in total, the most important ideas, not details)

## {h_q}
> [!question] <a question that checks understanding (why/how), not just a word>
> **{h_ans}:** <a complete 1–2 sentence answer from the facts>

({nq} questions in total, same format)""", 1000, temperature=0.3, rep_penalty=rp, guard=is_looping, label="close")
    ending = dedupe(strip_fences(ending))
    return dedupe("\n\n".join([opening] + sections + [ending]))


CALLOUT_ANSWER = re.compile(r"^(\*\*(?:Answer|คำตอบ)\s*[:：]\*\*.*)$", re.M)


def normalize_markdown(text, th):
    """Fixes the small format slips of a 3B model so the app renders callouts properly."""
    lines = text.split("\n")
    out = []
    for i, line in enumerate(lines):
        t = line.strip()
        # "* [!question] …" / "- [!question] …" / "[!tip] …" → "> [!question] …"
        m = re.match(r"^(?:[*\-•]\s*|>?\s*)\[!(\w+)\]\s*(.*)$", t)
        if m and not t.startswith("> [!"):
            line = f"> [!{m.group(1)}] {m.group(2)}".rstrip()
            t = line
        # "> [!summary]" without a title
        if re.fullmatch(r">\s*\[!summary\]\s*", t):
            line = "> [!summary] " + ("ภาพรวม" if th else "Overview")
        # an answer line directly under a callout belongs inside it
        if re.match(r"^\*\*(?:Answer|คำตอบ)\s*[:：]\*\*", t) and out and out[-1].lstrip().startswith(">"):
            line = "> " + t
        # "### ## Heading" → "## Heading"
        line = re.sub(r"^#{2,}\s+(#{2,}\s+)", r"\1", line)
        out.append(line)
    text = "\n".join(out)
    # a blank line before every callout header so callouts don't merge
    text = re.sub(r"([^\n])\n(> \[!)", r"\1\n\n\2", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


V4_SHORT_RULE = (" The material is SHORT: write a compact section — one short paragraph that explains it, then bullets "
                 "for the points (and \"- [ ] \" to-dos if any). No tables, no extra callouts, nothing that is not given.")


def run_v4(llm, sources, style="summary", language="auto", cfg=None, log=print):
    """v3 + Thai number normalisation, strict numbers, short path, markdown fix-ups."""
    cfg = cfg or {}
    kinds = {s["kind"] for s in sources}
    spoken = bool(kinds & {"audio", "recording"})
    texts = []
    for s in sources:
        t = clean_source(s["kind"], s["text"])
        if s["kind"] in ("audio", "recording"):
            t = preclean_speech(t)
        texts.append(t)
    corpus = "\n\n".join(texts)
    lang = language if language != "auto" else ("thai" if is_thai(corpus) else "english")
    th = lang == "thai"
    if len(corpus) < cfg.get("v4_short_chars", 1500):
        ex_src, ex_facts, ex_sec = (EX_TH_SPEECH, EX_TH_FACTS, EX_TH_SECTION) if th else (EX_EN_SPEECH, EX_EN_FACTS, EX_EN_SECTION)
        rp = cfg.get("rep_penalty", 1.1)
        out, _ = llm.chat(v3_facts_system(lang, spoken), f"<material>\n{corpus}\n</material>", 500, temperature=0.2,
                          rep_penalty=rp, guard=is_looping, label="facts",
                          history=[(f"<material>\n{ex_src}\n</material>", ex_facts)])
        topic, bullets = split_facts(dedupe(out))
        facts = (f"TOPIC: {topic}\n" if topic else "") + "\n".join(bullets)
        sec, _ = llm.chat(v3_write_system(lang) + V4_SHORT_RULE, f"<facts>\n{facts}\n</facts>", 600, temperature=0.3,
                          rep_penalty=rp, guard=is_looping, label="write",
                          history=[(f"<facts>\n{ex_facts}\n</facts>", ex_sec)])
        sec = dedupe(strip_fences(sec))
        sec = re.sub(r"^#{1,3} ", "# ", sec, count=1) if sec.lstrip().startswith("#") else f"# {topic or 'Note'}\n\n{sec}"
        return normalize_markdown(sec, th)
    cfg = dict(cfg)
    note = run_v3(llm, sources, style, language, cfg, log, _texts=texts)
    return normalize_markdown(note, th)



# ----------------------------------------------------------------------------- v5 = v4 + better fact parsing, fuzzy dedupe, smaller groups

def split_facts_v5(text):
    """Keeps sub-points (numbered / indented lines and short "ข้อ 1:" headers) as indented bullets."""
    topic, bullets = "", []
    for line in text.split("\n"):
        raw = line.rstrip()
        t = raw.strip()
        if not t:
            continue
        if t.upper().startswith("TOPIC:"):
            topic = topic or t[6:].strip()
            continue
        indented = len(raw) - len(raw.lstrip()) >= 1
        body = re.sub(r"^(?:[-*•]|\d+[.)])\s*", "", t)
        if len(body) < 4:
            continue
        if t[0] in "-*•" and not indented:
            bullets.append("- " + body)
        elif bullets:
            bullets.append("  - " + body)
        else:
            bullets.append("- " + body)
    return topic, bullets


def trigrams(text):
    t = re.sub(r"[\s*_=`>#\-]", "", text.lower())
    return {t[i:i + 3] for i in range(max(0, len(t) - 2))}


def near_duplicate(a, seen_sets, threshold=0.6):
    ga = trigrams(a)
    if len(ga) < 8:
        return False
    for gb in seen_sets:
        inter = len(ga & gb)
        if inter and inter / min(len(ga), len(gb)) >= threshold:
            return True
    return False


SPEECH_EXTRA = {"ใช่", "อ้าว", "เนี่ย", "เนาะ", "แหละ"}
WRITE_RULE_V5 = (" Each fact appears ONCE — in a paragraph, a bullet or a callout, never repeated in another form. "
                 "Prefer explanatory paragraphs that connect the facts (because…, so…, for example…) over bare bullet lists.")


def run_v5(llm, sources, style="summary", language="auto", cfg=None, log=print):
    global split_facts, FILLER_TOKENS
    cfg = dict(cfg or {})
    cfg.setdefault("v3_group_chars", 1500)
    old_split, old_write, old_fill = split_facts, v3_write_system, FILLER_TOKENS
    split_facts = split_facts_v5
    FILLER_TOKENS = FILLER_TOKENS | SPEECH_EXTRA
    globals()["v3_write_system"] = lambda lang: old_write(lang) + WRITE_RULE_V5
    globals()["_dedupe_mode"] = "fuzzy"
    try:
        return run_v4(llm, sources, style, language, cfg, log)
    finally:
        split_facts, FILLER_TOKENS = old_split, old_fill
        globals()["v3_write_system"] = old_write
        globals()["_dedupe_mode"] = "exact"
