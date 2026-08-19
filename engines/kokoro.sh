# shellcheck shell=bash
# engine: kokoro — local, Apache-2.0, multilingual (en + pt-BR)
# Install: python3.12 -m venv ~/.cache/johnny/venv && that venv: pip install kokoro soundfile
# (system python3 may be too new for spacy/thinc wheels; KOKORO_PYTHON points at the venv.)
# If KOKORO_SERVER is set, a persistent server does synthesis (sub-second) and the
# local python is only a fallback. See server/kokoro_server.py.
engine_available() {
  [ -n "$KOKORO_SERVER" ] && curl -fsS -m2 "$KOKORO_SERVER/health" >/dev/null 2>&1 && return 0
  "${KOKORO_PYTHON:-python3}" -c "import kokoro, soundfile" 2>/dev/null
}
_kokoro_json() { python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1"; }
engine_speak() { # text lang voice
  local text="$1" lang="$2" voice="$3"
  if [ -z "$voice" ]; then
    case "$lang" in pt) voice="$KOKORO_VOICE_PT" ;; *) voice="$KOKORO_VOICE_EN" ;; esac
  fi
  local code; case "$lang" in pt) code=p ;; *) code=a ;; esac   # p=pt-BR, a=American English
  local out="${VOICE_OUT:-$VOICE_CACHE/kokoro}.wav"

  # Prefer the persistent server (model in RAM, sub-second); fall back to local python.
  if [ -n "$KOKORO_SERVER" ]; then
    local body
    body="$(printf '{"text":%s,"voice":%s,"lang":%s}' \
      "$(_kokoro_json "$text")" "$(_kokoro_json "$voice")" "$(_kokoro_json "$code")")"
    if curl -fsS -m"${KOKORO_SERVER_TIMEOUT:-30}" -X POST "$KOKORO_SERVER/speak" \
        -H 'Content-Type: application/json' --data "$body" -o "$out" 2>/dev/null; then
      _voice_play _voice_playfile "$out"; return 0
    fi
    echo "johnny: kokoro server $KOKORO_SERVER unreachable — falling back to local" >&2
  fi

  "${KOKORO_PYTHON:-python3}" - "$text" "$voice" "$code" "$out" <<'PY' || return 1
import sys, numpy as np, soundfile as sf
from kokoro import KPipeline
text, voice, code, out = sys.argv[1:5]
pipe = KPipeline(lang_code=code)
audio = np.concatenate([a for _, _, a in pipe(text, voice=voice)])
sf.write(out, audio, 24000)
PY
  _voice_play _voice_playfile "$out"
}
