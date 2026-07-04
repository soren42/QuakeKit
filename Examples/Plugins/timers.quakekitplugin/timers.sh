#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

int_value() {
  value="${1:-0}"
  case "$value" in ''|*[!0-9]*) value=0 ;; esac
  printf '%s' "$value"
}

mode="${QUAKEKIT_TIMER_MODE:-pomodoro}"
duration="$(int_value "${QUAKEKIT_TIMER_DURATION_MINUTES:-25}")"
remaining="$(int_value "${QUAKEKIT_TIMER_REMAINING_SECONDS:-0}")"
[ "$duration" -gt 0 ] || duration=25
total=$((duration * 60))
[ "$remaining" -gt 0 ] || remaining="$total"
[ "$remaining" -le "$total" ] || remaining="$total"

case "$mode" in break|countdown|stopwatch) ;; *) mode="pomodoro" ;; esac
elapsed=$((total - remaining))
progress=0
[ "$total" -gt 0 ] && progress=$((elapsed * 100 / total))
label="$(awk -v r="$remaining" 'BEGIN { printf "%02d:%02d", int(r / 60), r % 60 }')"

printf '{"ok":true,"adapter":"timers.sh","mode":"%s","durationMinutes":%s,"remainingSeconds":%s,"progressPercent":%s,"label":"%s","actions":[{"id":"timer.start","enabled":true},{"id":"timer.pause","enabled":true},{"id":"timer.reset","enabled":true}],"rows":[{"title":"Mode","value":"%s","detail":"timer fixture"},{"title":"Remaining","value":"%s","detail":"%s%% elapsed"},{"title":"Duration","value":"%s min","detail":"knob-friendly control target"}],"source":"timers.sh"}\n' \
  "$(json_escape "$mode")" "$duration" "$remaining" "$progress" "$(json_escape "$label")" "$(json_escape "$mode")" "$(json_escape "$label")" "$progress" "$duration"
