#!/usr/bin/env python3
"""nina — remote playback sink.

Runs on the machine where the operator sits. Agents on other boxes
POST their spoken line here and it plays *here* instead of on the
calling box. The wire protocol is plain HTTP so any OS can forward (curl / curl.exe
/ PowerShell). Playback itself is delegated to the local `voice` entrypoint, so this
daemon is OS-agnostic: whatever `voice` does to make sound on this OS, we reuse it.

Safety (matches the tailnet-trust posture of the Kokoro server):
  - binds to the Tailscale IP only by default, never 0.0.0.0 — no LAN exposure.
  - `text` is passed to `voice` as a distinct argv element, never shell-interpolated.
  - optional shared secret (VOICE_SINK_SECRET): if set, requests must send it in the
    `X-Voice-Secret` header — defense-in-depth if untrusted devices join the tailnet.

Env:
  VOICE_SINK_BIND     host/IP to bind (default: `tailscale ip -4`, else 127.0.0.1)
  VOICE_SINK_PORT     port (default 8124)
  VOICE_SINK_CMD      local voice entrypoint (default: `voice` on PATH, else ./voice)
  VOICE_SINK_SECRET   optional shared secret required in X-Voice-Secret
  VOICE_SINK_PLAY_TIMEOUT  seconds to allow a single utterance (default 60)
"""
import os
import shutil
import subprocess
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get("VOICE_SINK_PORT", "8124"))
SECRET = os.environ.get("VOICE_SINK_SECRET", "")
PLAY_TIMEOUT = int(os.environ.get("VOICE_SINK_PLAY_TIMEOUT", "60"))
MAXCHARS = int(os.environ.get("VOICE_MAXCHARS", "600"))


def tailscale_ip():
    # OS-agnostic: PATH first, then the per-OS install locations (macOS bundles the
    # CLI inside the app; Windows installs under Program Files).
    candidates = [shutil.which("tailscale"),
                  "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
                  r"C:\Program Files\Tailscale\tailscale.exe",
                  r"C:\Program Files (x86)\Tailscale IPN\tailscale.exe"]
    for exe in candidates:
        if not exe or not os.path.exists(exe):
            continue
        try:
            out = subprocess.run([exe, "ip", "-4"], capture_output=True, text=True, timeout=5)
            ip = out.stdout.strip().splitlines()[0].strip() if out.stdout.strip() else ""
            if ip:
                return ip
        except Exception:
            continue
    return None


def resolve_bind():
    b = os.environ.get("VOICE_SINK_BIND", "").strip()
    if b:
        return b
    return tailscale_ip() or "127.0.0.1"  # safe default; never 0.0.0.0


def resolve_voice_cmd():
    c = os.environ.get("VOICE_SINK_CMD", "").strip()
    if c:
        return c
    found = shutil.which("voice")
    if found:
        return found
    local = os.path.join(os.path.dirname(HERE), "voice")  # sibling of server/
    return local


BIND = resolve_bind()
VOICE_CMD = resolve_voice_cmd()


def play(engine, voice, lang, text):
    """Delegate to the local voice CLI. VOICE_SINK is stripped so it plays locally
    (never re-forwards). Returns (ok, detail)."""
    text = (text or "")[:MAXCHARS]
    if not text.strip():
        return False, "empty text"
    argv = [VOICE_CMD]
    if engine:
        argv.append(engine)
    if lang:
        argv += ["--lang", lang]
    if voice:
        argv += ["--voice", voice]
    argv.append(text)  # text is its own argv element — no shell, no injection
    env = dict(os.environ)
    env.pop("VOICE_SINK", None)  # prevent forward loops
    try:
        r = subprocess.run(argv, env=env, capture_output=True, text=True,
                            timeout=PLAY_TIMEOUT)
        if r.returncode == 0:
            return True, "ok"
        return False, (r.stderr or r.stdout or f"rc={r.returncode}").strip()[:300]
    except subprocess.TimeoutExpired:
        return False, "play timeout"
    except FileNotFoundError:
        return False, f"voice cmd not found: {VOICE_CMD}"


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = (body + "\n").encode("utf-8", "replace")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/") in ("/health", ""):
            self._send(200, "ok")
        else:
            self._send(404, "not found")

    def do_POST(self):
        if self.path.rstrip("/") != "/speak":
            return self._send(404, "not found")
        if SECRET and self.headers.get("X-Voice-Secret", "") != SECRET:
            return self._send(403, "forbidden")
        try:
            n = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            n = 0
        raw = self.rfile.read(n).decode("utf-8", "replace") if n else ""
        form = urllib.parse.parse_qs(raw, keep_blank_values=True)
        get = lambda k: (form.get(k, [""])[0])
        ok, detail = play(get("engine"), get("voice"), get("lang"), get("text"))
        self._send(200 if ok else 500, detail)

    def log_message(self, fmt, *args):  # concise one-line log to stderr
        sys.stderr.write("voice-sink %s - %s\n" % (self.address_string(), fmt % args))


def main():
    srv = ThreadingHTTPServer((BIND, PORT), Handler)
    sys.stderr.write(
        f"voice-sink listening on http://{BIND}:{PORT}  (voice={VOICE_CMD}, "
        f"secret={'on' if SECRET else 'off'})\n")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
