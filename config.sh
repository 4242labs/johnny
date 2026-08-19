# johnny — config. Override any var via env before calling `voice`.
# VOICE_HOME is set by the `voice` script to its own dir (symlink-resolved); do not hardcode.

# Load machine-local secrets/overrides (gitignored). Put ELEVEN_API_KEY here.
[ -f "$VOICE_HOME/.env" ] && set -a && . "$VOICE_HOME/.env" && set +a

VOICE_CACHE="${VOICE_CACHE:-${TMPDIR:-/tmp}/johnny-cache}"   # audio scratch (never in-repo)
mkdir -p "$VOICE_CACHE" 2>/dev/null
# Per-session token so concurrent agents isolate their audio files + playback and
# never kill each other's afplay. Falls back to PID outside Claude Code.
VOICE_SESSION="${VOICE_SESSION:-${CLAUDE_CODE_SESSION_ID:-$$}}"
VOICE_OUT="$VOICE_CACHE/$VOICE_SESSION"   # engines append the extension (.wav/.mp3)

# Cross-platform file playback: afplay (macOS) | paplay/aplay (Linux, incl. WSLg).
# WSLg exposes a PulseAudio socket at /mnt/wslg/PulseServer — point paplay at it if unset.
[ -z "${PULSE_SERVER:-}" ] && [ -S /mnt/wslg/PulseServer ] && export PULSE_SERVER=/mnt/wslg/PulseServer
_voice_playfile() {  # file
  if command -v afplay >/dev/null 2>&1; then
    local err rc
    err="$(afplay "$1" 2>&1)"; rc=$?      # plain afplay first (works if it can reach the user's coreaudiod)
    if [ $rc -ne 0 ] && [ -n "${SSH_CONNECTION:-}" ] && command -v launchctl >/dev/null 2>&1; then
      _voice_log "playfile: plain afplay rc=$rc err='$err' -> trying launchctl asuser"
      err="$(launchctl asuser "$(id -u)" /usr/bin/afplay "$1" 2>&1)"; rc=$?
    fi
    _voice_log "playfile: afplay rc=$rc${err:+ err='$err'}"
    return $rc
  elif command -v paplay >/dev/null 2>&1; then paplay "$1"
  elif command -v aplay >/dev/null 2>&1; then aplay -q "$1"
  else echo "johnny: no audio player found (afplay/paplay/aplay)" >&2; return 1
  fi
}

# Serialize playback machine-wide so two agents speaking at once queue instead of
# overlapping (macOS has no flock; use an atomic mkdir mutex). Records that THIS
# session spoke (for the hybrid Stop-hook safety net). Engines call this, not afplay/paplay directly.
_voice_play() {  # cmd args...   (e.g. _voice_play _voice_playfile file.wav  |  _voice_play say -v X "text")
  local lock="${TMPDIR:-/tmp}/johnny.audiolock" i=0
  until mkdir "$lock" 2>/dev/null; do
    i=$((i+1)); [ "$i" -ge 300 ] && { rm -rf "$lock" 2>/dev/null; mkdir "$lock" 2>/dev/null; break; }  # steal stale lock after ~30s
    sleep 0.1
  done
  "$@"
  rmdir "$lock" 2>/dev/null
  : > "$VOICE_OUT.spoke" 2>/dev/null
}

VOICE_ENGINE="${VOICE_ENGINE:-say}"      # default engine: say | kokoro | eleven
VOICE_LANG="${VOICE_LANG:-en}"           # default language: en | pt
VOICE_MAXCHARS="${VOICE_MAXCHARS:-600}"  # truncate long text before speaking
VOICE_CHIME="${VOICE_CHIME:-$VOICE_HOME/assets/chime.wav}"  # gentle attention cue before each utterance ('' disables)
VOICE_CHIME_GAP="${VOICE_CHIME_GAP:-0}"                     # seconds between the chime and the speech (0 = none; chime already plays fully first)

# --- remote sink: play where the operator sits, not on the calling box ----------
# When VOICE_SINK is set (e.g. http://<operator-tailnet-ip>:8124) `voice` forwards the
# spoken line to that host's voice-sink daemon instead of playing locally — so an
# an agent on a remote box speaks on the operator's machine. Transport is plain HTTP (curl on any
# OS); text is a urlencoded form field, never shell-interpolated. Unreachable or
# slow sink → falls through to local playback (degraded, never silent).
VOICE_SINK="${VOICE_SINK:-}"
VOICE_SINK_TIMEOUT="${VOICE_SINK_TIMEOUT:-5}"
_voice_forward() {  # engine voice lang text  -> 0 if the sink accepted it
  [ -n "$VOICE_SINK" ] || return 1
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS --max-time "$VOICE_SINK_TIMEOUT" \
    --data-urlencode "engine=${1:-}" \
    --data-urlencode "voice=${2:-}" \
    --data-urlencode "lang=${3:-}" \
    --data-urlencode "text=${4:-}" \
    "${VOICE_SINK%/}/speak" >/dev/null 2>&1
}

# --- reverse-speak: play on the operator's machine when driving this box remotely
# If this shell is an inbound SSH session (SSH_CONNECTION set), the operator is
# elsewhere — send only the TEXT to their machine and let its johnny synthesize +
# play (with the "hey" preamble). Transport is a multiplexed SSH forced-command
# call; ControlMaster keeps it ~instant after the first. Returns non-zero on any
# failure (or when we're local) so the caller falls back to local playback.
VOICE_SPEAK_TARGET="${VOICE_SPEAK_TARGET:-}"                    # explicit host/IP (@machine); empty = auto from SSH origin
VOICE_SPEAK_USER="${VOICE_SPEAK_USER:-${USER:-$(id -un)}}"      # login on the operator's machine (override in .env if it differs)
VOICE_SPEAK_KEY="${VOICE_SPEAK_KEY:-$HOME/.ssh/id_johnny}"      # dedicated passphraseless key (forced to voice-play on the far end)
# Diagnostic log (opt-in): `touch ~/.cache/johnny/debug.on` to enable.
_voice_log() {  # message...
  [ -f "$HOME/.cache/johnny/debug.on" ] || return 0
  mkdir -p "$HOME/.cache/johnny" 2>/dev/null
  printf '%s [pid %s] %s\n' "$(date '+%H:%M:%S')" "$$" "$*" >> "$HOME/.cache/johnny/johnny.log" 2>/dev/null
}
# Shared ssh opts for the reverse channel: dedicated key only, multiplexed, fail-fast.
_voice_ssh_opts=(-i "$VOICE_SPEAK_KEY" -o IdentitiesOnly=yes
  -o ControlMaster=auto -o ControlPath="$HOME/.ssh/cm/%r@%h:%p" -o ControlPersist=4h
  -o ConnectTimeout=2 -o ServerAliveInterval=15 -o ServerAliveCountMax=2
  -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
_voice_reverse() {  # name lang text  -> 0 if the operator's machine accepted it
  [ -n "${VOICE_LOCAL:-}" ] && { _voice_log "reverse: skip (VOICE_LOCAL set)"; return 1; }  # we ARE the destination
  local host="$VOICE_SPEAK_TARGET"
  [ -z "$host" ] && [ -n "${SSH_CONNECTION:-}" ] && host="${SSH_CONNECTION%% *}"
  _voice_log "reverse: SSH_CONNECTION='${SSH_CONNECTION:-<unset>}' target='${VOICE_SPEAK_TARGET:-}' host='$host' user='$VOICE_SPEAK_USER' key='$VOICE_SPEAK_KEY'(exists=$([ -f "$VOICE_SPEAK_KEY" ] && echo y || echo n)) name='${1:-}'"
  [ -n "$host" ] || { _voice_log "reverse: no host -> fall to LOCAL"; return 1; }
  [ -n "${1:-}" ] || { _voice_log "reverse: no voice name -> return 1"; return 1; }
  command -v ssh >/dev/null 2>&1 || { _voice_log "reverse: no ssh binary"; return 1; }
  [ -f "$VOICE_SPEAK_KEY" ] || { _voice_log "reverse: key missing -> return 1"; return 1; }
  mkdir -p "$HOME/.ssh/cm" 2>/dev/null
  local err; err="$(printf '%s %s\n%s' "$1" "$2" "$3" | ssh "${_voice_ssh_opts[@]}" "${VOICE_SPEAK_USER}@${host}" johnny-speak 2>&1)"
  local rc=$?
  _voice_log "reverse: ssh to ${VOICE_SPEAK_USER}@${host} rc=$rc${err:+ err='$err'}"
  return $rc
}

# --- say (built-in macOS, zero-dep baseline) ---
SAY_VOICE_EN="${SAY_VOICE_EN:-Samantha}"
SAY_VOICE_PT="${SAY_VOICE_PT:-Luciana}"

# --- kokoro (local, Apache-2.0, multilingual) ---
# kokoro's deps (spacy/thinc) need a py3.12 venv; auto-detect the conventional one.
_kv="$HOME/.cache/johnny/venv/bin/python"
KOKORO_PYTHON="${KOKORO_PYTHON:-$([ -x "$_kv" ] && echo "$_kv" || echo python3)}"
KOKORO_VOICE_EN="${KOKORO_VOICE_EN:-af_heart}"
KOKORO_VOICE_PT="${KOKORO_VOICE_PT:-pf_dora}"
# Optional persistent Kokoro server (model held in RAM → sub-second vs ~23s local
# reload). Set its base URL — e.g. in .env — to use it; empty or unreachable falls
# back to local python automatically. Server script: server/kokoro_server.py.
KOKORO_SERVER="${KOKORO_SERVER:-}"
KOKORO_SERVER_TIMEOUT="${KOKORO_SERVER_TIMEOUT:-30}"

# --- elevenlabs (cloud quality ceiling; needs key) ---
ELEVEN_API_KEY="${ELEVEN_API_KEY:-}"     # set in env (do NOT commit a real key)
ELEVEN_VOICE_ID="${ELEVEN_VOICE_ID:-21m00Tcm4TlvDq8ikWAM}"  # "Rachel"
ELEVEN_MODEL="${ELEVEN_MODEL:-eleven_multilingual_v2}"

# --- voice registry: real voice name -> engine · id · language(s) --------------
# One row per voice: "Name|engine|engine-voice-id|langs" (langs space-separated,
# first = default). Names match case-insensitively. No aliases — the name IS the
# voice. Kokoro voices are single-language; the two eleven voices (Matilda,
# Charlie) each serve both pt and en, so they require a language.
voice_registry() {
  cat <<'EOF'
Sarah|kokoro|af_sarah|en
Dora|kokoro|pf_dora|pt
Fenrir|kokoro|am_fenrir|en
Alfred|kokoro|bm_lewis|en
Alex|kokoro|pm_alex|pt
EOF
}

# Human-readable menu, one per line: "Name (lang, lang), engine".
voice_menu() {
  local name engine id langs
  while IFS='|' read -r name engine id langs; do
    [ -n "$name" ] || continue
    printf '%s (%s), %s\n' "$name" "$(printf '%s' "$langs" | sed 's/ /, /g')" "$engine"
  done < <(voice_registry)
}

# Canonical spelling of a name as in the registry (case-insensitive in). rc1 unknown.
voice_canon() {  # name
  local want name rest
  want="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  while IFS='|' read -r name rest; do
    [ -n "$name" ] || continue
    [ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" = "$want" ] && { printf '%s' "$name"; return 0; }
  done < <(voice_registry)
  return 1
}

# Resolve "name [lang]" -> "engine|id|lang" on stdout (rc0).
#   rc1: unknown name.  rc2: name needs a language -> prints "NEEDLANG <langs>".
voice_lookup() {  # name [lang]
  local want lang name engine id langs l
  want="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  lang="${2:-}"
  while IFS='|' read -r name engine id langs; do
    [ -n "$name" ] || continue
    [ "$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')" = "$want" ] || continue
    if [ -n "$lang" ]; then
      for l in $langs; do [ "$l" = "$lang" ] && { printf '%s|%s|%s\n' "$engine" "$id" "$l"; return 0; }; done
      printf 'NEEDLANG %s\n' "$langs"; return 2
    fi
    set -- $langs
    [ $# -eq 1 ] && { printf '%s|%s|%s\n' "$engine" "$id" "$1"; return 0; }
    printf 'NEEDLANG %s\n' "$langs"; return 2
  done < <(voice_registry)
  return 1
}
