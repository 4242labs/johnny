#!/usr/bin/env python3
"""Read a Claude Code Stop-hook (or Hermes post_llm_call) JSON event on stdin, return the last assistant
message as plain speakable text (markdown/code/URLs stripped)."""
import sys, json, re, os

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

last = (data.get("extra") or {}).get("assistant_response")  # Hermes post_llm_call
tp = data.get("transcript_path")
if not last and (not tp or not os.path.exists(tp)):
    sys.exit(0)

with open(tp) if not last else open(os.devnull) as f:
    for line in f:
        try:
            o = json.loads(line)
        except Exception:
            continue
        if o.get("type") == "assistant":
            content = o.get("message", {}).get("content", [])
            txt = "".join(
                p.get("text", "")
                for p in content
                if isinstance(p, dict) and p.get("type") == "text"
            )
            if txt.strip():
                last = txt

if not last:
    sys.exit(0)

t = last
t = re.sub(r"```.*?```", " ", t, flags=re.S)   # fenced code
t = re.sub(r"`[^`]*`", " ", t)                 # inline code
t = re.sub(r"^\s*\|.*$", " ", t, flags=re.M)   # table rows
t = re.sub(r"https?://\S+", " ", t)            # urls
t = re.sub(r"[*_#>`\[\]()]", " ", t)           # md punctuation
t = re.sub(r"\s+", " ", t).strip()
print(t[:600])
