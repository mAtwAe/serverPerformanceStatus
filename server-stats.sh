#!/bin/sh
# server_health.sh — fast server health snapshot
# Usage:
#   ./server_health.sh                # one-time snapshot
#   ./server_health.sh --watch 5      # refresh every 5s
#   LOAD_THRESH=1.5 MEM_THRESH=90 DISK_THRESH=90 ./server_health.sh
# Exit codes: 0=OK, 1=warn (thresholds exceeded)

WATCH_INTERVAL=""
WARN=0

# Thresholds (override via env)
: "${LOAD_THRESH:=1.0}"    # per-core 1m load threshold
: "${MEM_THRESH:=90}"      # % memory used
: "${DISK_THRESH:=90}"     # % disk used on any mounted fs
: "${TOP_N:=5}"            # top processes count

while [ $# -gt 0 ]; do
  case "$1" in
    --watch) WATCH_INTERVAL="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

get_cores() {
  if command -v nproc >/dev/null 2>&1; then nproc
  else awk '/^processor/{c++}END{print c+0}' /proc/cpuinfo
  fi
}

get_loads() {
  # prints: L1 L5 L15
  awk '{print $1, $2, $3}' /proc/loadavg
}

mem_usage() {
  # prints: used_percent used_GB total_GB
  awk '
    /MemTotal:/ {t=$2}
    /MemAvailable:/ {a=$2}
    END{
      if (t>0) {
        u=t-a
        up= (u*100)/t
        printf "%.0f %.2f %.2f\n", up, u/1024/1024, t/1024/1024
      }
    }' /proc/meminfo
}

swap_usage() {
  awk '
    /SwapTotal:/ {t=$2}
    /SwapFree:/ {f=$2}
    END{
      if (t>0) {
        u=t-f
        up=(u*100)/t
        printf "%.0f %.2f %.2f\n", up, u/1024/1024, t/1024/1024
      } else { print "0 0.00 0.00" }
    }' /proc/meminfo
}

disk_usage() {
  # prints lines: PCT_USED MOUNT
  df -P -x tmpfs -x devtmpfs | awk 'NR>1 {print $5, $6}'
}

net_rates() {
  # 1s rx/tx KB/s (sum of all non-loopback)
  awk 'NR>2 && $1 !~ /lo:/ {gsub(":","",$1); rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev > /tmp/.net1.$$
  sleep 1
  awk 'NR>2 && $1 !~ /lo:/ {gsub(":","",$1); rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev > /tmp/.net2.$$
  set -- $(cat /tmp/.net1.$$); RX1=$1; TX1=$2
  set -- $(cat /tmp/.net2.$$); RX2=$1; TX2=$2
  rm -f /tmp/.net1.$$ /tmp/.net2.$$
  RXKB=$(( (RX2-RX1)/1024 ))
  TXKB=$(( (TX2-TX1)/1024 ))
  [ $RXKB -lt 0 ] && RXKB=0
  [ $TXKB -lt 0 ] && TXKB=0
  echo "$RXKB $TXKB"
}

top_procs() {
  # top by CPU and MEM (portable)
  echo "Top $TOP_N by CPU:"
  ps -eo pid,ppid,cmd,%cpu,%mem --no-headers | sort -k4 -nr | head -n "$TOP_N"
  echo
  echo "Top $TOP_N by MEM:"
  ps -eo pid,ppid,cmd,%cpu,%mem --no-headers | sort -k5 -nr | head -n "$TOP_N"
}

snapshot() {
  NOW="$(date '+%F %T')"
  UPTIME="$(uptime -p 2>/dev/null || true)"
  BOOT="$(uptime -s 2>/dev/null || who -b 2>/dev/null || true)"

  CORES=$(get_cores)
  set -- $(get_loads); L1=$1; L5=$2; L15=$3
  # per-core load (1m)
  LOAD_PER_CORE=$(awk -v l="$L1" -v c="$CORES" 'BEGIN{ if(c>0) printf "%.2f", l/c; else print "0.00"}')

  set -- $(mem_usage); MEM_PCT=$1; MEM_USED=$2; MEM_TOTAL=$3
  set -- $(swap_usage); SWAP_PCT=$1; SWAP_USED=$2; SWAP_TOTAL=$3
  set -- $(net_rates); RXKB=$1; TXKB=$2

  echo "=== $NOW ==="
  echo "Uptime: ${UPTIME:-N/A} | Boot: ${BOOT:-N/A}"
  echo "CPU: cores=$CORES | load(1,5,15)=$L1,$L5,$L15 | per-core(1m)=$LOAD_PER_CORE"
  echo "Memory: ${MEM_PCT}% used (${MEM_USED}G / ${MEM_TOTAL}G)"
  echo "Swap:   ${SWAP_PCT}% used (${SWAP_USED}G / ${SWAP_TOTAL}G)"
  echo "Net:    RX=${RXKB} KB/s | TX=${TXKB} KB/s"
  echo "Disk usage:"
  disk_usage | while read -r PCT MNT; do
    echo "  $MNT -> $PCT"
  done
  echo
  top_procs
  echo "---------------------------"

  # Threshold checks
  # Load threshold is per-core; compare LOAD_PER_CORE to LOAD_THRESH
  LC_EXCEEDED=$(awk -v a="$LOAD_PER_CORE" -v b="$LOAD_THRESH" 'BEGIN{print (a>b)?"1":"0"}')
  [ "$LC_EXCEEDED" -eq 1 ] && echo "WARN: per-core 1m load $LOAD_PER_CORE > $LOAD_THRESH" && WARN=1
  [ "$MEM_PCT" -gt "$MEM_THRESH" ] && echo "WARN: Memory ${MEM_PCT}% > ${MEM_THRESH}%" && WARN=1

  disk_usage | awk -v th="$DISK_THRESH" '{gsub(/%/,"",$1); if($1+0>th) printf "WARN: Disk %s%% > %d%% on %s\n",$1,th,$2}' && :
  if disk_usage | awk -v th="$DISK_THRESH" '{gsub(/%/,"",$1); if($1+0>th) exit 1}'; then :; else WARN=1; fi
}

if [ -n "$WATCH_INTERVAL" ]; then
  while :; do
    clear 2>/dev/null || printf "\033c"
    WARN=0
    snapshot
    # Do not exit on WARN in watch mode
    sleep "$WATCH_INTERVAL"
  done
else
  snapshot
  exit $WARN
fi
