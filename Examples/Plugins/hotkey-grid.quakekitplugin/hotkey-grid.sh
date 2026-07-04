#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

profile="${QUAKEKIT_HOTKEY_GRID_PROFILE:-default}"
columns="${QUAKEKIT_HOTKEY_GRID_COLUMNS:-4}"
dry_run="${QUAKEKIT_HOTKEY_GRID_DRY_RUN:-true}"
case "$columns" in
  ''|*[!0-9]*) columns=4 ;;
esac
if [ "$columns" -lt 2 ]; then columns=2; fi
if [ "$columns" -gt 6 ]; then columns=6; fi
case "$dry_run" in
  false|0|no) dry_run=false ;;
  *) dry_run=true ;;
esac

printf '{"ok":true,"adapter":"hotkey-grid.sh","ack":{"triggered":false,"reason":"safe stub"},"profile":"%s","columns":%s,"dryRun":%s,"hotkeys":[{"id":"mute","title":"Mute","keys":"Command+Shift+M"},{"id":"clip","title":"Clip","keys":"Command+Shift+C"},{"id":"focus","title":"Focus","keys":"Command+Option+F"},{"id":"blank","title":"Blank Screen","keys":"Command+Shift+B"}]}\n' \
  "$(json_escape "$profile")" "$columns" "$dry_run"
