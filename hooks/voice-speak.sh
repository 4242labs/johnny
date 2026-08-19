#!/usr/bin/env bash
# Claude Code Stop hook — HYBRID auto-speak safety net.
# Speaks the turn's reply via johnny ONLY when:
#   (a) johnny is active for this session  ($VOICE_OUT.alias exists, set by `voice on`), and
#   (b) the model did NOT already speak this turn  (.spoke not newer than .turn).
# So if the agent remembered to speak first, this no-ops; if it forgot, this covers it.
# Enable: add to ~/.claude/settings.json under hooks.Stop (see CONTEXT "Auto-speak").
src="${BASH_SOURCE[0]:-$0}"
while [ -h "$src" ]; do d="$(cd -P "$(dirname "$src")" && pwd)"; src="$(readlink "$src")"; [ "${src#/}" = "$src" ] && src="$d/$src"; done
HOOK_DIR="$(cd -P "$(dirname "$src")" && pwd)"
VOICE_HOME="$(cd "$HOOK_DIR/.." && pwd)"

payload="$(cat)"
sid="$(printf '%s' "$payload" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)"
[ -z "$sid" ] && sid="${CLAUDE_CODE_SESSION_ID:-}"
[ -z "$sid" ] && exit 0

export VOICE_HOME VOICE_SESSION="$sid"
# shellcheck disable=SC1091
. "$VOICE_HOME/config.sh"            # defines VOICE_OUT for THIS session

[ -f "$VOICE_OUT.alias" ] || exit 0  # voice not active for this session
# model already spoke this turn? (.spoke newer than the turn marker) -> nothing to do
[ -f "$VOICE_OUT.spoke" ] && [ "$VOICE_OUT.spoke" -nt "$VOICE_OUT.turn" ] && exit 0

al="$(cat "$VOICE_OUT.alias" 2>/dev/null)"; [ -z "$al" ] && exit 0
text="$(printf '%s' "$payload" | python3 "$HOOK_DIR/extract.py" 2>/dev/null)"
[ -z "${text// /}" ] && exit 0

# fire-and-forget so we never block Claude's turn.
# $al is "<Name> [lang]" — leave it UNQUOTED so it splits into name + optional lang args.
# shellcheck disable=SC2086
printf '%s' "$text" | "$VOICE_HOME/voice" $al >/dev/null 2>&1 &
exit 0
