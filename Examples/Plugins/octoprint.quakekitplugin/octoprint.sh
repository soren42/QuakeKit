#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool_value() {
  case "${1:-}" in
    false|0|no|off) printf 'false' ;;
    *) printf 'true' ;;
  esac
}

clamp_percent() {
  value="${1:-42}"
  case "$value" in
    ''|*[!0-9]*) value=42 ;;
  esac
  if [ "$value" -gt 100 ]; then value=100; fi
  printf '%s' "$value"
}

url="${QUAKEKIT_OCTOPRINT_URL:-http://octopi.local}"
name="${QUAKEKIT_OCTOPRINT_NAME:-Voron}"
job="${QUAKEKIT_OCTOPRINT_JOB:-Calibration Cube}"
material="${QUAKEKIT_OCTOPRINT_MATERIAL:-PLA}"
progress="$(clamp_percent "${QUAKEKIT_OCTOPRINT_PROGRESS:-42}")"
dry_run="$(bool_value "${QUAKEKIT_OCTOPRINT_DRY_RUN:-true}")"

case "$material" in
  PETG) nozzle_target=240; bed_target=75 ;;
  ABS) nozzle_target=245; bed_target=100 ;;
  TPU) nozzle_target=225; bed_target=50 ;;
  *) material="PLA"; nozzle_target=215; bed_target=60 ;;
esac

eta_minutes=$(( (100 - progress) * 2 ))
printf '{"ok":true,"adapter":"octoprint.sh","mode":"offline-safe","connected":false,"dryRun":%s,"printer":"%s","printerURL":"%s","state":"printing","job":{"file":"%s.gcode","display":"%s","progress":%s,"etaMinutes":%s,"material":"%s"},"temperatures":{"tool0":{"actual":%s,"target":%s},"bed":{"actual":%s,"target":%s}},"actions":[{"id":"octoprint.pause","enabled":true,"dryRun":%s,"api":"POST /api/job","command":"pause"},{"id":"octoprint.resume","enabled":true,"dryRun":%s,"api":"POST /api/job","command":"resume"},{"id":"octoprint.setTemperature","enabled":true,"dryRun":%s,"api":"POST /api/printer/tool","target":%s}],"rows":[{"title":"Printer","value":"%s","detail":"offline-safe OctoPrint adapter"},{"title":"Job","value":"%s","detail":"%s%% complete, ETA %s min"},{"title":"Nozzle","value":"%s C","detail":"target %s C"},{"title":"Bed","value":"%s C","detail":"target %s C"},{"title":"Material","value":"%s","detail":"profile controls deterministic temperatures"}],"source":"octoprint.sh"}\n' \
  "$dry_run" "$(json_escape "$name")" "$(json_escape "$url")" "$(json_escape "$job")" "$(json_escape "$job")" "$progress" "$eta_minutes" "$(json_escape "$material")" \
  "$nozzle_target" "$nozzle_target" "$bed_target" "$bed_target" \
  "$dry_run" "$dry_run" "$dry_run" "$nozzle_target" "$(json_escape "$name")" "$(json_escape "$job")" "$progress" "$eta_minutes" "$nozzle_target" "$nozzle_target" "$bed_target" "$bed_target" "$(json_escape "$material")"
