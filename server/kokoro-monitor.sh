#!/usr/bin/env bash
# johnny — Kokoro resource monitor for the host it runs on.
#   sample : append one CSV row (kokoro mem/cpu + system load/mem/swap/pressure). Run by a timer.
#   report : print latest sample, peaks, and any pressure warnings.
# Logs under ~/.cache/johnny/. Self-contained; no deps beyond coreutils + systemd.
set -u
DIR="$HOME/.cache/johnny"
CSV="$DIR/monitor.csv"
STATE="$DIR/monitor.state"
WARN="$DIR/monitor.warn.log"
UNIT="kokoro.service"
mkdir -p "$DIR"

NPROC="$(nproc)"
# thresholds (conflict signals)
MEM_AVAIL_MIN_MB=1500     # warn if free memory drops below this
LOAD1_MAX="$NPROC"        # warn if 1-min load exceeds core count
PSI_MEM_MAX=10            # warn if memory-pressure some/avg60 exceeds this
KOKORO_MEM_MAX_MB=8000    # warn if kokoro itself balloons past this

now() { date +%s; }
prop() { systemctl --user show "$UNIT" -p "$1" --value 2>/dev/null; }

sample() {
  local ts mem_b cpu_ns kmem_mb kcpu_pct
  ts="$(now)"
  mem_b="$(prop MemoryCurrent)";  { [ -z "$mem_b" ] || [ "$mem_b" = "[not set]" ]; } && mem_b=0
  cpu_ns="$(prop CPUUsageNSec)";  [ -z "$cpu_ns" ] && cpu_ns=0
  kmem_mb=$(( mem_b / 1048576 ))

  # kokoro CPU% (per-core: 100 = one full core) from CPUUsageNSec delta over the interval
  kcpu_pct=0
  if [ -f "$STATE" ]; then
    read -r p_ns p_ts < "$STATE"
    local d_ns=$(( cpu_ns - p_ns )) d_t=$(( ts - p_ts ))
    [ "$d_t" -gt 0 ] && [ "$d_ns" -ge 0 ] && kcpu_pct=$(( d_ns / 10000000 / d_t ))   # ns->%core
  fi
  printf '%s %s\n' "$cpu_ns" "$ts" > "$STATE"

  # system: load1, mem used%, mem avail MB, swap used MB, mem PSI some avg60
  local load1 mem_avail mem_total mem_used_pct swap_used psi
  load1="$(awk '{print $1}' /proc/loadavg)"
  mem_total=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
  mem_avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
  mem_used_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))
  swap_used=$(awk '/SwapTotal/{t=$2}/SwapFree/{f=$2}END{print int((t-f)/1024)}' /proc/meminfo)
  psi=$(awk -F'[ =]' '/^some/{print $5}' /proc/pressure/memory 2>/dev/null); [ -z "$psi" ] && psi=0

  [ -f "$CSV" ] || echo "ts,kokoro_mem_mb,kokoro_cpu_pct_core,load1,mem_used_pct,mem_avail_mb,swap_used_mb,mem_psi_some60" > "$CSV"
  echo "$ts,$kmem_mb,$kcpu_pct,$load1,$mem_used_pct,$mem_avail,$swap_used,$psi" >> "$CSV"

  # conflict warnings
  local msg=""
  awk "BEGIN{exit !($load1 > $LOAD1_MAX)}" && msg="$msg load1=$load1>${LOAD1_MAX}"
  [ "$mem_avail" -lt "$MEM_AVAIL_MIN_MB" ] && msg="$msg mem_avail=${mem_avail}MB<${MEM_AVAIL_MIN_MB}"
  awk "BEGIN{exit !($psi > $PSI_MEM_MAX)}" && msg="$msg mem_psi60=$psi>${PSI_MEM_MAX}"
  [ "$kmem_mb" -gt "$KOKORO_MEM_MAX_MB" ] && msg="$msg kokoro_mem=${kmem_mb}MB>${KOKORO_MEM_MAX_MB}"
  [ -n "$msg" ] && echo "$(date '+%F %T')$msg" >> "$WARN"

  # rotate (~2MB) keeping header + recent
  if [ "$(wc -c < "$CSV")" -gt 2000000 ]; then
    { head -1 "$CSV"; tail -2000 "$CSV"; } > "$CSV.tmp" && mv "$CSV.tmp" "$CSV"
  fi
}

report() {
  [ -f "$CSV" ] || { echo "no samples yet ($CSV)"; return; }
  local n; n=$(( $(wc -l < "$CSV") - 1 ))
  echo "== Kokoro on $(hostname) — $n samples =="
  echo "-- latest --"
  { head -1 "$CSV"; tail -1 "$CSV"; } | column -s, -t
  echo "-- peaks (whole log) --"
  awk -F, 'NR>1{if($2>km)km=$2; if($4>ld)ld=$4; if($7>sw)sw=$7; if($8>ps)ps=$8}
    END{printf "kokoro_mem_max=%dMB  load1_max=%s  swap_used_max=%dMB  mem_psi60_max=%s\n",km,ld,sw,ps}' "$CSV"
  echo "-- current top non-kokoro memory users --"
  local kpid; kpid="$(prop MainPID)"
  ps -eo pid,rss,comm --sort=-rss | awk -v k="$kpid" 'NR>1 && $1!=k {printf "  %6.0fMB  %s\n",$2/1024,$3; if(++c>=5)exit}'
  if [ -s "$WARN" ]; then echo "-- pressure warnings (last 5) --"; tail -5 "$WARN"; else echo "-- no pressure warnings --"; fi
}

case "${1:-report}" in
  sample) sample ;;
  report) report ;;
  *) echo "usage: $0 {sample|report}" >&2; exit 2 ;;
esac
