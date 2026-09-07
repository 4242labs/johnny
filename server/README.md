# Persistent Kokoro server

Holds the Kokoro pipelines in RAM so synthesis is fast, instead of reloading the
model on every call (spawning python fresh). Run it on any always-on box on the
LAN (Linux or macOS); point clients at it with `KOKORO_SERVER=http://<host>:8123`
(set in the gitignored `.env`).

## Install (Ubuntu/Debian example)

```sh
sudo apt-get install -y espeak-ng            # pt-BR/en phonemization
python3 -m venv ~/.cache/nina/venv
~/.cache/nina/venv/bin/pip install --upgrade pip
~/.cache/nina/venv/bin/pip install torch --index-url https://download.pytorch.org/whl/cpu
~/.cache/nina/venv/bin/pip install kokoro soundfile
mkdir -p ~/.cache/nina && cp kokoro_server.py ~/.cache/nina/
```

## Run as a systemd user service (survives logout/reboot)

`~/.config/systemd/user/kokoro.service`:

```ini
[Unit]
Description=nina Kokoro TTS server
After=network.target

[Service]
ExecStart=%h/.cache/nina/venv/bin/python %h/.cache/nina/kokoro_server.py 8123
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

```sh
sudo loginctl enable-linger "$USER"          # run without an active login
systemctl --user daemon-reload
systemctl --user enable --now kokoro.service
```

## API

- `GET  /health` → `ok`
- `POST /speak`  JSON `{"text": "...", "voice": "am_fenrir", "lang": "a"}`
  → `audio/wav` (24 kHz). `lang` accepts `a`/`en` (English) or `p`/`pt` (pt-BR).

```sh
curl -s -X POST http://<host>:8123/speak \
  -H 'Content-Type: application/json' \
  -d '{"text":"hello","voice":"am_fenrir","lang":"a"}' -o out.wav
```

Bind is `0.0.0.0:8123`, no auth — intended for a trusted LAN only. Do not expose
it to the public internet without a reverse proxy + auth.

## Monitoring (resource impact / conflict watch)

`kokoro-monitor.sh` samples the server's own memory + CPU (from systemd cgroup
accounting) alongside host load, free memory, swap, and the kernel memory-pressure
(PSI), one CSV row/minute. It flags conflict signals — high load, low free memory,
sustained memory pressure, or the server ballooning — into a warning log.

Install on the server (run via a systemd user timer):

```sh
cp kokoro-monitor.sh ~/.cache/nina/
# ~/.config/systemd/user/kokoro-monitor.service  (Type=oneshot, ExecStart=%h/.cache/nina/kokoro-monitor.sh sample)
# ~/.config/systemd/user/kokoro-monitor.timer    (OnUnitActiveSec=60, Persistent=true)
systemctl --user enable --now kokoro-monitor.timer
```

- `kokoro-monitor.sh report` — latest sample, peaks, top non-kokoro memory users, warnings.
- Logs: `~/.cache/nina/monitor.csv`, `monitor.warn.log` (auto-rotated).

From a client, `kstat` snapshots it over SSH (host derived from `KOKORO_SERVER`):

```sh
kstat        # -> runs kokoro-monitor.sh report on the server
```
