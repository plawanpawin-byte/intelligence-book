"""Model backends for the note-pipeline evaluation.

`mlx`   – mlx-community/Llama-3.2-3B-Instruct-4bit, the exact weights the iOS app runs.
`llama` – llama.cpp server with a Q4_K_M GGUF of the same model (fallback when Metal is missing).
"""
import json
import os
import subprocess
import time
import urllib.request

MLX_REPO = "mlx-community/Llama-3.2-3B-Instruct-4bit"
GGUF = "bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M"


class Stats:
    def __init__(self):
        self.calls = []

    def add(self, **kw):
        self.calls.append(kw)

    def totals(self):
        p = sum(c["prompt_tokens"] for c in self.calls)
        g = sum(c["gen_tokens"] for c in self.calls)
        t = sum(c["seconds"] for c in self.calls)
        return p, g, t


class MLXBackend:
    name = "mlx"

    def __init__(self):
        from mlx_lm import load
        self.model, self.tokenizer = load(MLX_REPO)
        self.stats = Stats()

    def count_tokens(self, text):
        return len(self.tokenizer.encode(text))

    def chat(self, system, user, max_tokens, temperature=0.4, top_p=0.9, rep_penalty=1.1, rep_ctx=96,
             guard=None, label="", history=()):
        from mlx_lm import stream_generate
        from mlx_lm.sample_utils import make_sampler, make_logits_processors
        msgs = [{"role": "system", "content": system}]
        for u, a in history:
            msgs += [{"role": "user", "content": u}, {"role": "assistant", "content": a}]
        msgs.append({"role": "user", "content": user})
        prompt = self.tokenizer.apply_chat_template(msgs, add_generation_prompt=True)
        sampler = make_sampler(temp=temperature, top_p=top_p)
        procs = make_logits_processors(repetition_penalty=rep_penalty, repetition_context_size=rep_ctx) \
            if rep_penalty and rep_penalty != 1.0 else None
        text, finish, last_check = "", None, 0
        n_gen, t0 = 0, time.time()
        resp = None
        for resp in stream_generate(self.model, self.tokenizer, prompt, max_tokens=max_tokens,
                                    sampler=sampler, logits_processors=procs):
            text += resp.text
            n_gen += 1
            finish = resp.finish_reason
            if guard and len(text) - last_check > 40:
                last_check = len(text)
                if guard(text):
                    finish = "loop"
                    break
        secs = time.time() - t0
        self.stats.add(label=label, output=text, prompt_tokens=len(prompt), gen_tokens=n_gen, seconds=secs,
                       finish=finish, prompt_tps=getattr(resp, "prompt_tps", 0),
                       gen_tps=getattr(resp, "generation_tps", 0))
        return text, finish == "length"


class LlamaCppBackend:
    name = "llama.cpp"

    def __init__(self, port=8089):
        self.url = f"http://127.0.0.1:{port}"
        self.proc = subprocess.Popen(
            ["llama-server", "-hf", GGUF, "-c", "16384", "--port", str(port), "-ngl", os.environ.get("LLAMA_NGL", "0")],
            stdout=open("llama-server.log", "w"), stderr=subprocess.STDOUT)
        for _ in range(900):
            try:
                with urllib.request.urlopen(self.url + "/health", timeout=2) as r:
                    if r.status == 200:
                        break
            except Exception:
                time.sleep(2)
        self.stats = Stats()

    def _post(self, path, body):
        req = urllib.request.Request(self.url + path, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=3600) as r:
            return json.loads(r.read())

    def count_tokens(self, text):
        return len(self._post("/tokenize", {"content": text})["tokens"])

    def chat(self, system, user, max_tokens, temperature=0.4, top_p=0.9, rep_penalty=1.1, rep_ctx=96,
             guard=None, label="", history=()):
        t0 = time.time()
        hist = []
        for u, a in history:
            hist += [{"role": "user", "content": u}, {"role": "assistant", "content": a}]
        out = self._post("/v1/chat/completions", {
            "messages": [{"role": "system", "content": system}] + hist + [{"role": "user", "content": user}],
            "max_tokens": max_tokens, "temperature": temperature, "top_p": top_p,
            "repeat_penalty": rep_penalty, "repeat_last_n": rep_ctx,
        })
        choice = out["choices"][0]
        usage = out.get("usage", {})
        self.stats.add(label=label, prompt_tokens=usage.get("prompt_tokens", 0),
                       gen_tokens=usage.get("completion_tokens", 0), seconds=time.time() - t0,
                       finish=choice.get("finish_reason"), prompt_tps=0, gen_tps=0)
        return choice["message"]["content"], choice.get("finish_reason") == "length"


def make_backend():
    want = os.environ.get("EVAL_BACKEND", "auto")
    if want in ("auto", "mlx"):
        try:
            import mlx.core as mx
            if mx.metal.is_available():
                return MLXBackend()
            print("Metal not available for MLX")
        except Exception as e:  # noqa
            print("MLX unavailable:", e)
        if want == "mlx":
            raise SystemExit("MLX requested but unavailable")
    return LlamaCppBackend()
