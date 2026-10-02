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
