---
description: " "
argument-hint: "Sarah·en | Dora·pt | Fenrir·en | Alfred·en-GB | Alex·pt | off"
allowed-tools: Bash(voice:*), Bash(voice on:*), Bash(voice off), Bash(voice voices)
---
Activate **johnny** for THIS session only — the agent speaks its replies aloud **on this machine** (johnny plays where the agent runs). Output only; input is unchanged (keep using your usual dictation tool). Do NOT listen/capture audio.

Requested: `$ARGUMENTS`

## If `$ARGUMENTS` is empty
Do NOT pick a voice. Show the user the list below and ask which they want — nothing else.

| Voice | Language |
|-------|----------|
| Sarah  | en |
| Dora   | pt |
| Fenrir | en |
| Alfred | en (British) |
| Alex   | pt |

Call format: `/johnny <Name>`.

## If `$ARGUMENTS` is `off` / `stop`
Run `voice off`, confirm once. Nothing else.

## Otherwise — a name, optionally a language
1. Run `voice on <Name> [lang]`.
   - If it replies that the voice **needs a language**, tell the user the languages available for that name and stop — do NOT guess a language.
2. On success, greet in character: just the voice's name + a brief question, in the chosen language. NO meta/status (never say "voice on", "activated", or name the engine/voice/language). Speak it via `voice <Name> [lang] "<greeting>"` and also write it.
   - en → «Hi! Fenrir here. What are we working on?»
   - pt → «Olá! Aqui é a Dora. O que temos pra hoje?»

## For the REST of this session, every reply, in order
1. **Speak FIRST** — before writing any text: `voice <Name> [lang] "<spoken answer>"` — 1–3 sentences carrying the substance (the answer, the "so what", the decision). Never speak code, tables, numbers, paths, or long lists.
2. **Then write minimal text** — key points/tables/numbers/code/commands/paths only. Terse; no prose recap of what you just said aloud.

Reply language follows the chosen voice's language. Mid-session: `/johnny <other>` switches; `/johnny off` stops.

## Notes
- Names resolve to engine·voice·language in johnny’s `config.sh` (`voice_registry`). **No aliases** — the name is the voice.
- **Safety net:** a Stop hook auto-speaks the reply only if you forgot to this turn (it never double-speaks).
- Concurrent agents are safe: per-session audio isolation + a machine-wide lock.
