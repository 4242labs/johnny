#!/usr/bin/env bash
# nina — install the remote-sink daemon as a persistent, OS-native service.
#   macOS -> LaunchAgent (launchd)      Linux/WSL -> systemd --user unit
# Native Windows: use sink-service.ps1 (Task Scheduler) instead.
#
# Usage: server/sink-service.sh [install|uninstall|restart|status]
# The bind IP + interpreter/paths are detected at install time and written into
# the machine-local service file (nothing host-specific is kept in the repo).
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SINK="$HERE/voice-sink.py"
LABEL="com.nina.sink"     # macOS
UNIT="nina-sink"                    # systemd
LOG="$HOME/.cache/nina/voice-sink.log"
action="${1:-install}"

_tailscale() {
  for c in tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale \
           "/mnt/c/Program Files/Tailscale/tailscale.exe"; do
    command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }
    [ -x "$c" ] && { echo "$c"; return; }
  done
}
_py()    { command -v python3 || command -v python; }
_voice() { command -v voice || echo "$HERE/../voice"; }

PY="$(_py)"; VOICE="$(_voice)"
BIND="${VOICE_SINK_BIND:-}"
[ -z "$BIND" ] && { TS="$(_tailscale)"; [ -n "${TS:-}" ] && BIND="$("$TS" ip -4 2>/dev/null | head -1)"; }
PATH_EXTRA="$(dirname "$VOICE"):$(dirname "$PY")"

if [ "$action" = install ] && [ -z "$BIND" ]; then
  echo "WARN: no Tailscale IP found; sink would bind 127.0.0.1 (not reachable remotely)." >&2
  echo "      set VOICE_SINK_BIND=<this host's tailnet IP> and re-run." >&2
fi
mkdir -p "$HOME/.cache/nina"

case "$(uname -s)" in
Darwin)
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"; U="gui/$(id -u)/$LABEL"
  case "$action" in
  install)
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$PY</string><string>$SINK</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>VOICE_SINK_BIND</key><string>$BIND</string>
    <key>PATH</key><string>$PATH_EXTRA:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>WorkingDirectory</key><string>$HERE</string>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF
    launchctl bootout "$U" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    launchctl kickstart -k "$U"
    echo "installed LaunchAgent -> bind $BIND" ;;
  uninstall) launchctl bootout "$U" 2>/dev/null || true; rm -f "$PLIST"; echo "removed" ;;
  restart)   launchctl kickstart -k "$U"; echo "restarted" ;;
  status)    launchctl print "$U" 2>/dev/null | grep -E "state =|pid =" || echo "not loaded" ;;
  esac ;;
Linux)
  DIR="$HOME/.config/systemd/user"; SVC="$DIR/$UNIT.service"
  case "$action" in
  install)
    mkdir -p "$DIR"
    cat > "$SVC" <<EOF
[Unit]
Description=nina remote-sink daemon
After=network-online.target
Wants=network-online.target

[Service]
Environment=VOICE_SINK_BIND=$BIND
Environment=PATH=$PATH_EXTRA:/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$HERE
ExecStart=$PY $SINK
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now "$UNIT"
    loginctl enable-linger "$USER" 2>/dev/null || true   # run at boot without an active login
    echo "installed systemd --user unit -> bind $BIND" ;;
  uninstall) systemctl --user disable --now "$UNIT" 2>/dev/null || true; rm -f "$SVC"; systemctl --user daemon-reload; echo "removed" ;;
  restart)   systemctl --user restart "$UNIT"; echo "restarted" ;;
  status)    systemctl --user --no-pager status "$UNIT" 2>/dev/null | head -6 || echo "not installed" ;;
  esac ;;
*) echo "unsupported OS $(uname -s) — on native Windows use server/sink-service.ps1" >&2; exit 1 ;;
esac
