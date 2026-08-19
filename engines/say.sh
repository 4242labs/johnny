# shellcheck shell=bash
# engine: say — macOS built-in. Zero-dep, instant, local. Baseline.
engine_available() { command -v say >/dev/null; }
engine_speak() { # text lang voice
  local text="$1" lang="$2" voice="$3"
  if [ -z "$voice" ]; then
    case "$lang" in pt) voice="$SAY_VOICE_PT" ;; *) voice="$SAY_VOICE_EN" ;; esac
  fi
  _voice_play say -v "$voice" "$text"
}
