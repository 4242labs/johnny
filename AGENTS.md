# johnny

A speech toolbox. Two CLIs, both tracked at the repository root:

- **`voice`** — text to speech. Pluggable engines, named voices, a per-session auto-speak hook, and
  **reverse-speak**: when you drive a machine over SSH, its speech plays on *your* machine instead
  of the remote box, with only the text crossing the wire.
- **`listen`** — speech to text. Local microphone into a Whisper transcript, with device selection,
  language, clipboard copy and speak-back. Capture needs microphone permission, so it must be run
  from a TCC-granted application; an ad-hoc-signed one is blocked silently by macOS.

**Named voices.** The name *is* the voice — engine, voice and language together. No aliases.
**Pluggable engines.** `say` (macOS), `kokoro` (local), `eleven` (ElevenLabs cloud); adding an
engine is dropping a file in `engines/`. **Multi-agent safe.** Per-session audio isolation plus a
machine-wide playback lock, so concurrent agents queue instead of talking over each other.

**Open source, dual-licensed** — AGPL-3.0, commercial on request (`LICENSING.md`) — and passively
maintained. The public `README.md` is the user documentation. The ElevenLabs engine needs a key in
`.env`, copied from `.env.example`; that key never enters version control.

## How work flows

Branch, work from a worktree, open a PR against `main`. The LGTM gate runs on every PR. The
`.claude/` CLU guards enforce worktree-only writes and refuse a self-merge, but only while a CLU
run is active. `main` is not branch-protected, so the gate is advisory.

## Crew

The roles this project is worked by, and what each one needs. **No personas live here** — an agent
arrives already knowing who it is, and reads this project to learn the project.

| Role | What this project needs from it |
|------|---------------------------------|
| Engineering | Both CLIs, the engine adapters, the session hook, the local Kokoro server |
| Code review | The playback lock and session isolation — concurrency is where this breaks |
| Security review | Only when the cloud engine's credential handling or the SSH sink changes |
| Content | The README is public OSS documentation, not internal notes |
| Sysadmin | Branch protection and the gate |

No architect or data role is in use.

**After any context loss, re-read your anchor under `~/.agent-anchors/johnny/`** (canon §17).

## Key files

- `README.md` — user documentation: install, voices, engines, reverse-speak
- `voice`, `listen` — the two CLIs
- `engines/` — one file per TTS engine (`say.sh`, `kokoro.sh`, `eleven.sh`); the extension point
- `hooks/` — the per-session auto-speak wiring
- `server/` — the local Kokoro TTS server (`kokoro_server.py`, `kokoro-monitor.sh`, `kstat`) and the reverse-speak sink (`voice-sink.py`, `voice-play`, `sink-service.sh`, `sink-service.ps1`)
- `commands/johnny.md` — the slash command
- `tests/` — the test suite
- `MEMO-CODEX-URGENT.md` — untracked. Its gate item is done; branch protection is still open
