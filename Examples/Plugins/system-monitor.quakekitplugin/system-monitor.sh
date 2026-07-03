#!/bin/sh
set -eu

cat >/dev/null

load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || printf '0')"
pages_free="$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_active="$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_inactive="$(vm_stat 2>/dev/null | awk '/Pages inactive/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_wired="$(vm_stat 2>/dev/null | awk '/Pages wired down/ {gsub("\\.","",$4); print $4; exit}' || printf '0')"

used_pages=$((pages_active + pages_inactive + pages_wired))
total_pages=$((used_pages + pages_free))
if [ "$total_pages" -gt 0 ]; then
  memory_percent=$((used_pages * 100 / total_pages))
else
  memory_percent=0
fi

printf '{"cpu":%s,"memory":%s,"loadAverage":"%s","source":"system-monitor.sh"}\n' \
  "$load" "$memory_percent" "$load"
