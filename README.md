# johnny

[![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Maintenance](https://img.shields.io/badge/maintenance-passively--maintained-yellowgreen.svg)](CONTRIBUTING.md)

A small **speech toolbox** — one CLI (`voice`) that any agent or script can call to
speak, with pluggable TTS engines, named voices, a per-session auto-speak hook, and
**reverse-speak**: when you drive a machine over SSH, its speech plays on *your*
machine instead of the remote box.

- **Named voices** — `voice Fenrir "build is green"`. The name *is* the voice
  (engine · voice · language); no aliases to remember.
- **Pluggable engines** — `say` (macOS built-in), `kokoro` (local, Apache-2.0),
  `eleven` (ElevenLabs cloud). Adding an engine is dropping a file in `engines/`.
- **Reverse-speak over SSH** — speech follows you to wherever you're sitting, with
  only the *text* crossing the wire (the far end synthesizes locally).
- **Attention chime** — a gentle cue plays before each utterance.
- **Multi-agent safe** — per-session audio isolation + a machine-wide playback lock,
  so concurrent agents queue instead of talking over each other.

## Install

```sh
git clone https://github.com/<you>/johnny.git
ln -sf "$PWD/johnny/voice" ~/.local/bin/voice     # ~/.local/bin must be on PATH
```

`voice` resolves its own directory (even through the symlink), so it works from any
repo or session. For the ElevenLabs engine, copy `.env.example` to `.env` and add a key.

## Usage

```sh
voice voices                       # list the available voices: "Name (langs), engine"
voice Fenrir "tests are green"     # single-language voice — just speak
voice Dora "a migração terminou"   # any registered name works the same way
voice say "quick and robotic"      # call an engine directly
echo "piped text works too" | voice
voice list                         # engines + availability
voice bench "compare the engines"  # play through every available engine
```

A voice whose name maps to one language needs no language argument. Register a voice
against several languages and it will tell you which it offers if you don't pick one.

### Voices

Defined in `config.sh` (`voice_registry`) — edit it to add your own. Each row is
`Name | engine | engine-voice-id | languages`. Example set shipped:

| Voice | Language(s) | Engine |
|-------|-------------|--------|
| Sarah / Dora / Fenrir / Alfred / Alex | en / pt / en / en-GB / pt | kokoro |

No ElevenLabs voice ships by default — the engine is there, so add your own row with
a key from your account.

## Slash command (Claude Code)

Copy `commands/johnny.md` to `~/.claude/commands/johnny.md`. Then:

- `/johnny` — lists the voices and waits for you to pick.
- `/johnny <Name>` — turns on per-session voice; the agent speaks a short spoken
  gist before each reply (text still carries structure — code, tables, paths).
- `/johnny off` — stops.

## Reverse-speak — play where you sit

By default `voice` plays on the machine it runs on. If that machine is one you're
**driving over SSH**, `voice` instead plays on the machine you connected *from* — it
reads `SSH_CONNECTION`, sends only the text, and the far end synthesizes + plays it.

Setup (on the machine you sit at — the playback target):

1. Enable SSH (so the remote box can reach back).
2. Add the remote box's **dedicated** public key to `~/.ssh/authorized_keys`, pinned to
   the speak command so it can do nothing else:

   ```
   command="/path/to/johnny/server/voice-play",restrict ssh-ed25519 AAAA... johnny-reverse
   ```

3. On the remote box, create that key passphrase-less (`~/.ssh/id_johnny`) so it can
   sign non-interactively, and set `VOICE_SPEAK_USER` in `.env` if your login there
   differs from your login on the playback machine.

Then any `voice` call from an SSH session on the remote box plays on your machine.
Multiplexed SSH (ControlMaster) keeps it fast; if the channel is down the utterance is
dropped rather than played on the unattended box. `VOICE_SPEAK_TARGET=<host>` overrides
the auto-target.

> HTTP alternative: set `VOICE_SINK=http://<host>:8124` and run `server/voice-sink.py`
> on the target (see `server/sink-service.sh` to install it as a service). Reverse-SSH
> is preferred — no daemon, no open port.

## Auto-speak (Stop hook)

Make the active agent speak every reply. Symlink the hook and register it:

```sh
ln -sf "$PWD/johnny/hooks/voice-speak.sh" ~/.local/bin/voice-speak
```

```json
{ "hooks": {
  "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "~/johnny/hooks/turn-mark.sh" } ] } ],
  "Stop":             [ { "hooks": [ { "type": "command", "command": "~/johnny/hooks/voice-speak.sh" } ] } ]
} }
```

It speaks the reply only if the agent didn't already speak this turn (never doubles),
and no-ops for sessions where voice isn't active.

> Want a **sound** instead of speech when an agent needs you — a beep on hand-back,
> gated on idle? That's a separate tool: [**hey**](https://github.com/4242labs/hey).

## Config

`config.sh` holds the defaults; override any of them via env or a gitignored `.env`:

| Var | Purpose |
|-----|---------|
| `VOICE_ENGINE` / `VOICE_LANG` | default engine / language |
| `VOICE_CHIME` / `VOICE_CHIME_GAP` | attention cue file / pause before speech (`''` disables the chime) |
| `KOKORO_SERVER` | URL of a persistent Kokoro server (see `server/`), else local fallback |
| `ELEVEN_API_KEY` / `ELEVEN_VOICE_ID` | ElevenLabs credentials / voice |
| `VOICE_SPEAK_TARGET` / `VOICE_SPEAK_USER` / `VOICE_SPEAK_KEY` | reverse-speak target / login / key |
| `VOICE_SINK` | HTTP sink URL (alternative to reverse-SSH) |

Never commit a real `ELEVEN_API_KEY` — keep it in the gitignored `.env`.

## Engines

| Engine | Setup | Notes |
|--------|-------|-------|
| `say` | none (macOS built-in) | instant, robotic, local — baseline |
| `kokoro` | `pip install kokoro soundfile` (Python 3.12) | natural, local, en + pt-BR; optional persistent server in `server/` |
| `eleven` | `ELEVEN_API_KEY` in `.env` | best quality, cloud, paid |

## License

Open source — [AGPL-3.0](LICENSE). Commercial — contact ahoy@42labs.io.

---
If it earned its keep, [coffee is appreciated](https://buymeacoffee.com/42piratas). ☕
