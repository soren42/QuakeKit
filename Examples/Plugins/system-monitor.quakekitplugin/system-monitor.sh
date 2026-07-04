#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

volume_scope="${QUAKEKIT_SYSTEM_VOLUME_SCOPE:-local}"
show_battery="${QUAKEKIT_SYSTEM_SHOW_BATTERY:-auto}"
process_rows="${QUAKEKIT_SYSTEM_PROCESS_ROWS:-6}"
memory_mode="${QUAKEKIT_SYSTEM_MEMORY_MODE:-used}"
case "$process_rows" in
  ''|*[!0-9]*) process_rows=6 ;;
esac
if [ "$process_rows" -lt 3 ]; then process_rows=3; fi
if [ "$process_rows" -gt 8 ]; then process_rows=8; fi

top_snapshot="$(top -l 1 -n 0 2>/dev/null || true)"
load_line="$(printf '%s\n' "$top_snapshot" | awk -F': ' '/^Load Avg:/ {print $2; exit}')"
load_one="$(printf '%s' "$load_line" | awk -F', ' '{gsub(/^ +| +$/,"",$1); print $1}')"
load_five="$(printf '%s' "$load_line" | awk -F', ' '{gsub(/^ +| +$/,"",$2); print $2}')"
load_fifteen="$(printf '%s' "$load_line" | awk -F', ' '{gsub(/^ +| +$/,"",$3); print $3}')"
load="${load_five:-0}"
cores="$(sysctl -n hw.ncpu 2>/dev/null || printf '1')"
pages_free="$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_active="$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_inactive="$(vm_stat 2>/dev/null | awk '/Pages inactive/ {gsub("\\.","",$3); print $3; exit}' || printf '0')"
pages_wired="$(vm_stat 2>/dev/null | awk '/Pages wired down/ {gsub("\\.","",$4); print $4; exit}' || printf '0')"
disk_command="df -Pk"
if [ "$volume_scope" = "local" ]; then
  disk_command="df -lPk"
fi
disk_info="$($disk_command / 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $2 "," $3 "," $4 "," $5; exit}')"
disk_total_kb="$(printf '%s' "$disk_info" | awk -F, '{print $1 + 0}')"
disk_used_kb="$(printf '%s' "$disk_info" | awk -F, '{print $2 + 0}')"
disk_available_kb="$(printf '%s' "$disk_info" | awk -F, '{print $3 + 0}')"
disk_percent="$(printf '%s' "$disk_info" | awk -F, '{print $4 + 0}')"
battery_report="$(pmset -g batt 2>/dev/null || true)"
if printf '%s\n' "$battery_report" | grep -q 'InternalBattery'; then
  has_battery=true
  battery_percent="$(printf '%s\n' "$battery_report" | awk -F'[%;]' '/InternalBattery/ {gsub(/^ +/,"",$2); print $2; exit}')"
  battery_state="$(printf '%s\n' "$battery_report" | awk -F"'" '/InternalBattery/ {print $2; exit}')"
else
  has_battery=false
  battery_percent=0
  battery_state="none"
fi
if [ "$show_battery" = "never" ]; then
  has_battery=false
fi
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
if [ "$memory_mode" = "free" ]; then
  memory_percent=$((100 - memory_percent))
fi

cpu_line="$(printf '%s\n' "$top_snapshot" | awk '/^CPU usage:/ {print; exit}')"
cpu_user="$(printf '%s\n' "$cpu_line" | sed -n 's/.*CPU usage: \([0-9.]*\)% user.*/\1/p')"
cpu_system="$(printf '%s\n' "$cpu_line" | sed -n 's/.*user, \([0-9.]*\)% sys.*/\1/p')"
cpu_idle="$(printf '%s\n' "$cpu_line" | sed -n 's/.*sys, \([0-9.]*\)% idle.*/\1/p')"
cpu_percent="$(awk -v idle="${cpu_idle:-0}" 'BEGIN { value = 100 - idle; if (value < 0) value = 0; if (value > 100) value = 100; printf "%.1f", value }')"
load_one_percent="$(awk -v load="${load_one:-0}" -v cores="$cores" 'BEGIN { if (cores < 1) cores = 1; value = (load / cores) * 100; if (value > 100) value = 100; printf "%.1f", value }')"
load_five_percent="$(awk -v load="${load_five:-0}" -v cores="$cores" 'BEGIN { if (cores < 1) cores = 1; value = (load / cores) * 100; if (value > 100) value = 100; printf "%.1f", value }')"
load_fifteen_percent="$(awk -v load="${load_fifteen:-0}" -v cores="$cores" 'BEGIN { if (cores < 1) cores = 1; value = (load / cores) * 100; if (value > 100) value = 100; printf "%.1f", value }')"

process_total="$(printf '%s\n' "$top_snapshot" | awk '/^Processes:/ {print $2 + 0; exit}')"
process_running="$(printf '%s\n' "$top_snapshot" | awk '/^Processes:/ {gsub(",","",$4); print $4 + 0; exit}')"
thread_count="$(printf '%s\n' "$top_snapshot" | awk '/^Processes:/ {for (i=1; i<=NF; i++) if ($i == "threads") {print $(i-1) + 0; exit}}')"
network_in_gb="$(printf '%s\n' "$top_snapshot" | awk '/^Networks:/ {for (i=1; i<=NF; i++) if ($i == "in,") {value=$(i-1); sub(".*/","",value); gsub(/[^0-9.]/,"",value); print value; exit}}')"
network_out_gb="$(printf '%s\n' "$top_snapshot" | awk '/^Networks:/ {for (i=1; i<=NF; i++) if ($i == "out.") {value=$(i-1); sub(".*/","",value); gsub(/[^0-9.]/,"",value); print value; exit}}')"
disk_read_gb="$(printf '%s\n' "$top_snapshot" | awk '/^Disks:/ {for (i=1; i<=NF; i++) if ($i == "read,") {value=$(i-1); sub(".*/","",value); gsub(/[^0-9.]/,"",value); print value; exit}}')"
disk_written_gb="$(printf '%s\n' "$top_snapshot" | awk '/^Disks:/ {for (i=1; i<=NF; i++) if ($i == "written.") {value=$(i-1); sub(".*/","",value); gsub(/[^0-9.]/,"",value); print value; exit}}')"

top_processes="$(
  ps -axo pid=,pcpu=,pmem=,command= -r 2>/dev/null |
    awk -v limit="$process_rows" 'NR <= limit {
      pid=$1
      cpu=$2
      mem=$3
      name=$0
      sub(/^ *[0-9]+ +[0-9.]+ +[0-9.]+ +/, "", name)
      gsub(/\\/,"\\\\",name)
      gsub(/"/,"\\\"",name)
      printf "%s{\"pid\":%s,\"name\":\"%s\",\"cpu\":%s,\"memory\":%s}", sep, pid, name, cpu, mem
      sep=","
    }'
)"

volumes="$(
  $disk_command 2>/dev/null |
    awk -v scope="$volume_scope" 'NR > 1 && count < 4 {
      if (scope != "all" && $6 != "/" && $6 !~ "^/Volumes/") next
      gsub("%","",$5)
      name=$6
      sub("^/Volumes/","",name)
      if (name == "/") name="Root"
      gsub(/\\/,"\\\\",name)
      gsub(/"/,"\\\"",name)
      printf "%s{\"name\":\"%s\",\"usedPercent\":%s,\"usedGB\":%.1f,\"totalGB\":%.1f}", sep, name, $5 + 0, $3 / 1048576, $2 / 1048576
      sep=","
      count++
    }'
)"

printf '{"cpu":%s,"cpuUser":%s,"cpuSystem":%s,"cpuIdle":%s,"memory":%s,"memoryMode":"%s","disk":%s,"diskTotalGB":%.1f,"diskUsedGB":%.1f,"diskAvailableGB":%.1f,"hasBattery":%s,"battery":%s,"batteryState":"%s","loadAverage":"%s","loadHistory":[%s,%s,%s,%s],"cores":%s,"processes":%s,"runningProcesses":%s,"threads":%s,"networkInGB":%s,"networkOutGB":%s,"diskReadGB":%s,"diskWrittenGB":%s,"uptimeSeconds":%s,"volumes":[%s],"topProcesses":[%s],"source":"system-monitor.sh"}\n' \
  "$cpu_percent" "${cpu_user:-0}" "${cpu_system:-0}" "${cpu_idle:-0}" "$memory_percent" "$(json_escape "$memory_mode")" "${disk_percent:-0}" \
  "$(awk -v kb="${disk_total_kb:-0}" 'BEGIN { printf "%.1f", kb / 1048576 }')" \
  "$(awk -v kb="${disk_used_kb:-0}" 'BEGIN { printf "%.1f", kb / 1048576 }')" \
  "$(awk -v kb="${disk_available_kb:-0}" 'BEGIN { printf "%.1f", kb / 1048576 }')" \
  "$has_battery" "${battery_percent:-0}" "$(json_escape "${battery_state:-unknown}")" "${load:-0}" \
  "${cpu_percent:-0}" "${load_one_percent:-0}" "${load_five_percent:-0}" "${load_fifteen_percent:-0}" \
  "$cores" "${process_total:-0}" "${process_running:-0}" "${thread_count:-0}" \
  "${network_in_gb:-0}" "${network_out_gb:-0}" "${disk_read_gb:-0}" "${disk_written_gb:-0}" "${uptime_seconds:-0}" "$volumes" "$top_processes"
