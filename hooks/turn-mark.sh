#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook — stamp the start of a turn for johnny'
# hybrid Stop hook, and re-assert the spoken-reply contract while voice is on
# (stdout from this event is added to the model's context). Only fires for
# sessions where voice is active (an .alias file exists); no-ops for everything
# else. Pair with voice-speak.sh.
sid=""
payload="$(cat 2>/dev/null)"
[ -n "$payload" ] && sid="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)"
[ -z "$sid" ] && sid="${CLAUDE_CODE_SESSION_ID:-}"
[ -z "$sid" ] && exit 0
CACHE="${VOICE_CACHE:-${TMPDIR:-/tmp}/johnny-cache}"
[ -f "$CACHE/$sid.alias" ] || exit 0   # voice not active for this session
: > "$CACHE/$sid.turn" 2>/dev/null

# The slash command sets this contract once, at activation; a long session
# drifts off it. Restating it every turn is what actually keeps replies short.
al="$(cat "$CACHE/$sid.alias" 2>/dev/null)"
[ -n "$al" ] && printf '%s\n' \
  "johnny is on. Speak first: voice $al \"<1-3 sentences carrying the answer>\". Then write only what has to be READ - code, commands, paths, numbers, tables, links. No prose restating what you just said aloud. If the whole answer is speakable, the written part can be a single line or nothing."

exit 0
