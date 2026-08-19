#!/usr/bin/env bash
# Argument-resolution checks for `voice`. No audio: VOICE_SINK points at a dead
# port, so every utterance that gets far enough to speak is forwarded, fails,
# and is dropped — exactly the forward-or-drop path in config.sh.
#
#   ./tests/test-voice-args.sh
cd "$(dirname "$0")/.." || exit 1

export VOICE_SINK="http://127.0.0.1:1" VOICE_SINK_TIMEOUT=1
export VOICE_CACHE="${TMPDIR:-/tmp}/johnny-test-cache.$$"
trap 'rm -rf "$VOICE_CACHE"' EXIT

fails=0
check() {  # description expected_rc pattern-or-"" args...
  local desc="$1" want_rc="$2" pat="$3"; shift 3
  local out rc
  out="$(./voice "$@" 2>&1)"; rc=$?
  if [ "$rc" != "$want_rc" ]; then
    echo "FAIL  $desc — rc $rc, wanted $want_rc${out:+  (output: $out)}"; fails=$((fails + 1)); return
  fi
  if [ -n "$pat" ] && ! printf '%s' "$out" | grep -q "$pat"; then
    echo "FAIL  $desc — output did not match /$pat/  (output: $out)"; fails=$((fails + 1)); return
  fi
  echo "ok    $desc"
}

# The regression this file exists for: a typo'd voice name used to fall through
# to `[TEXT...]`, and the default voice read the name and the language out loud.
check "unknown name + lang is an error, not text" 1 "unknown voice 'Bogus'" Bogus en "x"
check "unknown name + lang, via 'on'"             1 "unknown voice"         on Bogus

# ...without breaking the paths that legitimately fall through to text.
check "known single-language voice"    0 "" Fenrir "tests are green"
check "known voice with its language"  0 "" Dora pt "os testes passaram"
check "bare text is still just text"   0 "" "no voice name here at all"
check "bare engine name"               0 "" say "engine called directly"

check "registry lists only kokoro" 0 "Sarah (en), kokoro" voices
if [ "$(./voice voices | wc -l | tr -d ' ')" = 5 ]; then
  echo "ok    registry has 5 voices"
else
  echo "FAIL  registry voice count"; fails=$((fails + 1))
fi

if [ "$fails" = 0 ]; then echo "all passed"; else echo "$fails failed"; fi
exit $((fails > 0))
