# johnny

A speech toolbox: one CLI (`voice`) that any agent or script can call to speak. Pluggable TTS
engines, named voices, a per-session auto-speak hook, and **reverse-speak** — when you drive a
machine over SSH, its speech plays on *your* machine instead of the remote box, with only the text
crossing the wire.

- **Named voices.** The name *is* the voice — engine, voice and language together. No aliases.
- **Pluggable engines.** `say` (macOS), `kokoro` (local), `eleven` (ElevenLabs cloud). Adding an
  engine is dropping a file in `engines/`.
- **Multi-agent safe.** Per-session audio isolation plus a machine-wide playback lock, so
  concurrent agents queue instead of talking over each other.

**Open source, AGPL-3.0, passively maintained.** The public `README.md` is the user documentation.
The ElevenLabs engine needs a key in `.env`, copied from `.env.example` — that key never enters
version control.

## Crew

The roles this project is worked by, and what each one needs. **No personas live here** — an agent
arrives already knowing who it is, and reads this project to learn the project.

| Role | What this project needs from it |
|------|---------------------------------|
| Engineering | The `voice` CLI, the engine adapters, the session hook |
| Code review | The playback lock and session isolation — concurrency is where this breaks |
| Security review | Only when the cloud engine's credential handling changes |
| Content | The README is public OSS documentation, not internal notes |
| Sysadmin | Branch protection and the LGTM gate |

No architect or data role is in use.

**After any context loss, re-read your anchor under `~/.agent-anchors/johnny/`** (canon §17).

## Key files

- `README.md` — user documentation: install, voices, engines, reverse-speak
- `voice` — the CLI
- `engines/` — one file per TTS engine; the extension point
- `hooks/` — the per-session auto-speak wiring
- `server/` — the reverse-speak listener
- `tests/` — the test suite
- `MEMO-CODEX-URGENT.md` — untracked and open: LGTM gate and branch protection
