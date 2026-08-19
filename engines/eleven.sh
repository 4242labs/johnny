# shellcheck shell=bash
# engine: eleven — ElevenLabs cloud. Quality ceiling / benchmark. Needs ELEVEN_API_KEY.
engine_available() { [ -n "${ELEVEN_API_KEY:-}" ]; }
engine_speak() { # text lang voice
  # shellcheck disable=SC2034  # lang is part of the engine_speak signature; this
  # engine takes its language from ELEVEN_MODEL (multilingual), not from the arg
  local text="$1" lang="$2" voice="$3"
  voice="${voice:-$ELEVEN_VOICE_ID}"
  local out="${VOICE_OUT:-$VOICE_CACHE/eleven}.mp3"
  local body; body="$(python3 -c 'import json,sys; print(json.dumps({"text":sys.argv[1],"model_id":sys.argv[2]}))' "$text" "$ELEVEN_MODEL")"
  curl -sS -X POST "https://api.elevenlabs.io/v1/text-to-speech/$voice/stream?output_format=mp3_44100_128" \
    -H "xi-api-key: $ELEVEN_API_KEY" -H "Content-Type: application/json" \
    -d "$body" -o "$out" || return 1
  # guard: API errors return JSON/text, not audio
  if file "$out" | grep -qi 'json\|ascii\|text'; then echo "voice/eleven: $(cat "$out")" >&2; return 1; fi
  _voice_play _voice_playfile "$out"
}
