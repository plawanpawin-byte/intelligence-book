"""Runs one evaluation job: python run.py <job-id>  (jobs are listed in jobs.json)."""
import json
import os
import sys
import time

import pipeline
import metrics
from backend import make_backend

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = {"th_short_recording": "recording", "th_talk_medium": "recording", "th_lecture_econ": "recording",
         "th_lecture_bio_long": "recording", "th_article": "web", "en_paper": "pdf"}


def main():
    jobs = json.load(open(os.path.join(HERE, "jobs.json")))
    wanted = sys.argv[1:] or [j["id"] for j in jobs["jobs"]]
    out_dir = os.environ.get("EVAL_OUT", os.path.join(HERE, "out"))
    os.makedirs(out_dir, exist_ok=True)
    llm = make_backend()
    print("backend:", llm.name)

    for job in jobs["jobs"]:
        if job["id"] not in wanted:
            continue
        cases = job["cases"] if "cases" in job else [job["case"]]
        sources = []
        for c in cases:
            text = open(os.path.join(HERE, "data", c + ".txt"), encoding="utf-8").read()
            sources.append({"title": c, "kind": KINDS[c], "text": text})
        start = len(llm.stats.calls)
        t0 = time.time()
        cfg = {**jobs.get("defaults", {}), **job.get("cfg", {})}
        if job["pipeline"] == "v0":
            note = pipeline.run_v0(llm, sources, job.get("style", "summary"))
        else:
            run = getattr(pipeline, "run_" + job["pipeline"])
            note = run(llm, sources, job.get("style", "summary"), job.get("language", "auto"), cfg)
        secs = time.time() - t0
        calls = llm.stats.calls[start:]
        p = sum(c["prompt_tokens"] for c in calls)
        g = sum(c["gen_tokens"] for c in calls)
        chars = sum(len(s["text"]) for s in sources)
        src_tokens = sum(llm.count_tokens(s["text"]) for s in sources)
        header = (f"<!-- job={job['id']} backend={llm.name} seconds={secs:.0f} calls={len(calls)} "
                  f"prompt_tokens={p} gen_tokens={g} source_chars={chars} source_tokens={src_tokens} "
                  f"note_chars={len(note)} metrics={metrics.report(note, chr(10).join(x['text'] for x in sources))} -->\n")
        open(os.path.join(out_dir, job["id"] + ".md"), "w", encoding="utf-8").write(header + note + "\n")
        json.dump(calls, open(os.path.join(out_dir, job["id"] + ".calls.json"), "w"), indent=1)
        print(header)


if __name__ == "__main__":
    main()
