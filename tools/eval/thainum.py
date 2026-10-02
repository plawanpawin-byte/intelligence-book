"""Deterministic Thai spoken-number → digits (speech transcripts spell numbers out).

Only sequences that contain a multiplier (สิบ ร้อย พัน หมื่น แสน ล้าน) are converted, so ordinary words
that start with a digit word (สามารถ, เก้าอี้, หกล้ม) are left alone. Colloquial forms are handled:
"หมื่นสอง" = 12,000, "ร้อยห้า" = 150, "พันสอง" = 1,200.
"""
import re

DIGITS = {"ศูนย์": 0, "หนึ่ง": 1, "เอ็ด": 1, "สอง": 2, "ยี่": 2, "สาม": 3, "สี่": 4, "ห้า": 5, "หก": 6, "เจ็ด": 7,
          "แปด": 8, "เก้า": 9}
MULT = {"สิบ": 10, "ร้อย": 100, "พัน": 1000, "หมื่น": 10000, "แสน": 100000, "ล้าน": 1000000}
WORDS = sorted(list(DIGITS) + list(MULT), key=len, reverse=True)
SEQ = re.compile("(?:" + "|".join(WORDS) + ")+")
# A Thai dependent vowel / tone mark / ending that would continue the previous syllable (e.g. สาม|ารถ).
CONTINUES = re.compile(r"^[ะ-ฺ็-๎าำ]|^(?:ธ|อี้|ล้ม)")
# Words that end with a number word (เรียบ|ร้อย).
BEFORE_BLOCK = ("เรียบ", "ร้อยเอ็ด")


def value(words):
    total, current, last_mult = 0, 0, None
    million = 0
    pending = None
    for w in words:
        if w in DIGITS:
            if pending is not None:  # two digits in a row → not a number we understand
                return None
            pending = DIGITS[w]
        else:
            m = MULT[w]
            if m == 1000000:
                million = (million + total + current + (pending or 0)) * 1000000 if (total + current + (pending or 0)) else 1000000
                total, current, pending, last_mult = 0, 0, None, None
                continue
            n = pending if pending is not None else 1
            if w == "สิบ" and pending == 2 and False:
                pass
            current += n * m
            pending = None
            last_mult = m
    if pending is not None:
        if last_mult and last_mult >= 100 and words[-1] in DIGITS and words[-1] not in ("เอ็ด",) and len(words) >= 2 \
                and words[-2] in MULT:
            current += pending * last_mult // 10  # colloquial: หมื่นสอง = 12,000
        else:
            current += pending
    return million + total + current


def tokenize(seq):
    out, i = [], 0
    while i < len(seq):
        for w in WORDS:
            if seq.startswith(w, i):
                out.append(w)
                i += len(w)
                break
        else:
            return None
    return out


PERCENT = re.compile("ร้อยละ\\s*(" + SEQ.pattern + "|[0-9][0-9,.]*)")


def convert(text):
    def pct(m):
        inner = m.group(1)
        if inner[0].isdigit():
            return inner + "%"
        words = tokenize(inner)
        v = value(words) if words else None
        return f"{v:,}%" if v is not None else m.group(0)
    text = PERCENT.sub(pct, text)

    def repl(m):
        seq = m.group(0)
        before = text[max(0, m.start() - 6):m.start()]
        after = text[m.end():m.end() + 3]
        words = tokenize(seq)
        if not words or not any(w in MULT for w in words):
            return seq
        if CONTINUES.match(after) or before.endswith(BEFORE_BLOCK):
            return seq
        if len(words) == 1 and words[0] in ("พัน", "แสน"):  # พัน(ธุ์), แสน(ดี) are mostly not numbers alone
            return seq
        if words[0] == "ยี่" and (len(words) < 2 or words[1] != "สิบ"):
            return seq
        v = value(words)
        if v is None:
            return seq
        s = f"{v:,}"
        # keep a space on each side so it doesn't glue into Thai words
        lead = "" if (m.start() == 0 or text[m.start() - 1].isspace()) else " "
        trail = "" if (m.end() == len(text) or text[m.end()].isspace()) else " "
        return lead + s + trail
    return SEQ.sub(repl, text)


if __name__ == "__main__":
    tests = {
        "ถ้าขายแก้วละสามสิบห้า ต้นทุนประมาณสิบแปดบาท": "35",
        "กำไรวันละแปดร้อยห้าสิบ": "850",
        "เครื่องชงมือสองประมาณหมื่นสอง": "12,000",
        "ราคาถูกดันขึ้นไปจนถึงร้อยห้าสิบ": "150",
        "Qd เท่ากับ หกร้อย ลบ สองพี": "600",
        "ทำได้เรียบร้อย": "เรียบร้อย",
        "เราสามารถทำได้": "สามารถ",
        "นั่งเก้าอี้": "เก้าอี้",
        "สายพันธุ์ใหม่": "พันธุ์",
        "ยี่สิบเอ็ดวัน": "21",
        "สองพันห้าร้อยหกสิบสามคน": "2,563",
        "สามล้านห้าแสนบาท": "3,500,000",
        "หนึ่งร้อยเปอร์เซ็นต์": "100",
        "ประมาณสี่สิบเปอร์เซ็นต์": "40",
        "พันสองบาท": "1,200",
        "สิบโมง": "10",
        "ร้อยละห้าสิบ": "50%", "ร้อยละ 30 ของ": "30%", "ร้อยละห้า": "5%",
        "หกล้ม": "หกล้ม",
    }
    for t, want in tests.items():
        out = convert(t)
        ok = want is None or want in out
        print("OK " if ok else "BAD", t, "→", out)
