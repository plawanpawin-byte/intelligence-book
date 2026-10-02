"""Cheap automatic checks for a generated note vs its source(s)."""
import re
import sys

FILLERS = ["อ่ะ", "เอ่อ", "นะครับ", "ใช่มั้ย", "โอเค", "เดี๋ยว", "uh ", "um "]


def grams(text, n=14):
    t = re.sub(r"\s+", "", text)
    return {t[i:i + n] for i in range(0, max(0, len(t) - n + 1), 3)}


def report(note, source):
    body = "\n".join(l for l in note.split("\n") if not l.startswith("<!--"))
    src = grams(source)
    ng = grams(body)
    copy = len(ng & src) / max(1, len(ng))
    heads = [l.strip() for l in body.split("\n") if l.startswith("#")]
    dup_heads = len(heads) - len(set(heads))
    fill = sum(body.count(f) for f in FILLERS)
    return {"chars": len(body), "copy_ratio": round(copy, 3), "fillers": fill, "dup_headings": dup_heads,
            "sections": sum(1 for h in heads if h.startswith("## ")), "callouts": body.count("> [!")}


if __name__ == "__main__":
    print(report(open(sys.argv[1]).read(), open(sys.argv[2]).read()))
