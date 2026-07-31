#!/usr/bin/env python3
"""johnny Kokoro TTS server — holds pipelines in RAM, serves WAV over HTTP (LAN-only)."""
import io, json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import numpy as np
import soundfile as sf
from kokoro import KPipeline

LANGMAP = {"en": "a", "pt": "p", "a": "a", "p": "p", "it": "i", "es": "e", "fr": "f", "i": "i", "e": "e", "f": "f"}
# Kokoro voice ids encode language+region in their first letter (a=American en,
# b=British en, p=Brazilian pt, ...). Prefer that over the caller's lang so e.g.
# a British voice (bm_lewis) is phonemized British, not American.
VOICE_PREFIX_LANG = {"a": "a", "b": "b", "p": "p", "i": "i", "e": "e", "f": "f"}
PIPELINES = {}


def get_pipeline(lang_code):
    if lang_code not in PIPELINES:
        PIPELINES[lang_code] = KPipeline(lang_code=lang_code)
    return PIPELINES[lang_code]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/speak":
            self.send_error(404)
            return
        try:
            n = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(n) or b"{}")
            text = (body.get("text") or "").strip()
            voice = body.get("voice") or "af_sarah"
            lang = VOICE_PREFIX_LANG.get(voice[:1]) or LANGMAP.get(body.get("lang", "a"), "a")
            if not text:
                self.send_error(400, "empty text")
                return
            pipe = get_pipeline(lang)
            chunks = [audio for _, _, audio in pipe(text, voice=voice)]
            if not chunks:
                self.send_error(500, "no audio produced")
                return
            audio = np.concatenate(chunks) if len(chunks) > 1 else chunks[0]
            buf = io.BytesIO()
            sf.write(buf, audio, 24000, format="WAV")
            data = buf.getvalue()
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except BrokenPipeError:
            pass
        except Exception as e:
            try:
                self.send_error(500, str(e))
            except Exception:
                pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8123
    # warm both languages so the first real request is fast
    for lc in ("a", "b", "p"):
        try:
            get_pipeline(lc)
            print(f"warmed pipeline lang_code={lc}", flush=True)
        except Exception as e:
            print(f"warm failed lang_code={lc}: {e}", file=sys.stderr, flush=True)
    srv = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"johnny kokoro server listening on :{port}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
