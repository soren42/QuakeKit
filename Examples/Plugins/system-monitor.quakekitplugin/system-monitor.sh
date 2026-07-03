#!/bin/sh
set -eu

cat >/dev/null

load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || printf '0')"
cores="$(sysctl -n hw.ncpu 2>/dev/null || printf '1')"
pages_free="$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_active="$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_inactive="$(vm_stat 2>/dev/null | awk '/Pages inactive/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_wired="$(vm_stat 2>/dev/null | awk '/Pages wired down/ {gsub("\\.","",$4); print $4; exit}' || printf '0')"
disk_percent="$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5; exit}' || printf '0')"
battery_percent="$(pmset -g batt 2>/dev/null | awk -F'[%;]' '/InternalBattery/ {gsub(/^ +/,"",$2); print $2; exit}' || printf '0')"
battery_state="$(pmset -g batt 2>/dev/null | awk -F"'" '/InternalBattery/ {print $2; exit}' || printf 'unknown')"
boot_epoch="$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9][0-9]*\),.*/\1/p' || printf '0')"
now_epoch="$(date +%s 2>/dev/null || printf '0')"
if [ "${boot_epoch:-0}" -gt 0 ] && [ "${now_epoch:-0}" -gt "$boot_epoch" ]; then
  uptime_seconds=$((now_epoch - boot_epoch))
else
  uptime_seconds=0
fi

used_pages=$((pages_active + pages_inactive + pages_wired))
total_pages=$((used_pages + pages_free))
if [ "$total_pages" -gt 0 ]; then
  memory_percent=$((used_pages * 100 / total_pages))
else
  memory_percent=0
fi

cpu_percent="$(awk -v load="$load" -v cores="$cores" 'BEGIN { if (cores < 1) cores = 1; value = (load / cores) * 100; if (value > 100) value = 100; printf "%.1f", value }')"

printf '{"cpu":%s,"memory":%s,"disk":%s,"battery":%s,"batteryState":"%s","loadAverage":"%s","cores":%s,"uptimeSeconds":%s,"source":"system-monitor.sh"}\n' \
  "$cpu_percent" "$memory_percent" "${disk_percent:-0}" "${battery_percent:-0}" "${battery_state:-unknown}" "$load" "$cores" "${uptime_seconds:-0}"
