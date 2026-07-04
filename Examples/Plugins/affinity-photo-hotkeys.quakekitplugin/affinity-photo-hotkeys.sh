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

persona="${QUAKEKIT_AFFINITY_PERSONA:-photo}"
columns="${QUAKEKIT_AFFINITY_COLUMNS:-4}"
dry_run="$(bool_value "${QUAKEKIT_AFFINITY_DRY_RUN:-true}")"
case "$persona" in
  liquify|develop|tone_mapping|export) ;;
  *) persona="photo" ;;
esac
case "$columns" in
  ''|*[!0-9]*) columns=4 ;;
esac
if [ "$columns" -lt 2 ]; then columns=2; fi
if [ "$columns" -gt 6 ]; then columns=6; fi

case "$persona" in
  develop)
    hotkeys='{"id":"white_balance","title":"White Balance","keys":"W","group":"Develop"},{"id":"crop","title":"Crop","keys":"C","group":"Develop"},{"id":"before_after","title":"Before/After","keys":"Command+Y","group":"Preview"},{"id":"develop_commit","title":"Develop","keys":"Return","group":"Apply"}'
    ;;
  liquify)
    hotkeys='{"id":"push_forward","title":"Push Forward","keys":"P","group":"Liquify"},{"id":"twirl","title":"Twirl","keys":"T","group":"Liquify"},{"id":"freeze","title":"Freeze","keys":"F","group":"Mask"},{"id":"apply","title":"Apply","keys":"Return","group":"Apply"}'
    ;;
  tone_mapping)
    hotkeys='{"id":"tone_map","title":"Tone Map","keys":"Command+Option+T","group":"Tone"},{"id":"histogram","title":"Histogram","keys":"Command+Option+H","group":"Panels"},{"id":"split_view","title":"Split View","keys":"Command+Y","group":"Preview"},{"id":"apply","title":"Apply","keys":"Return","group":"Apply"}'
    ;;
  export)
    hotkeys='{"id":"export","title":"Export","keys":"Command+Option+Shift+S","group":"File"},{"id":"save","title":"Save","keys":"Command+S","group":"File"},{"id":"copy_flattened","title":"Copy Flattened","keys":"Command+Shift+C","group":"Clipboard"},{"id":"close","title":"Close","keys":"Command+W","group":"File"}'
    ;;
  *)
    hotkeys='{"id":"move","title":"Move Tool","keys":"V","group":"Tools"},{"id":"paint_brush","title":"Paint Brush","keys":"B","group":"Tools"},{"id":"inpainting","title":"Inpainting Brush","keys":"J","group":"Retouch"},{"id":"toggle_ui","title":"Toggle UI","keys":"Tab","group":"View"},{"id":"zoom_fit","title":"Zoom to Fit","keys":"Command+0","group":"View"},{"id":"export","title":"Export","keys":"Command+Option+Shift+S","group":"File"}'
    ;;
esac

printf '{"ok":true,"adapter":"affinity-photo-hotkeys.sh","mode":"offline-safe","application":"Affinity Photo 2","persona":"%s","columns":%s,"dryRun":%s,"ack":{"triggered":false,"reason":"safe stub"},"hotkeys":[%s],"actions":[{"id":"affinity.triggerHotkey","enabled":true,"dryRun":%s,"targetApplication":"Affinity Photo 2"},{"id":"affinity.switchPersona","enabled":true,"dryRun":%s,"persona":"%s"}],"rows":[{"title":"Application","value":"Affinity Photo 2","detail":"context-aware hotkey grid"},{"title":"Persona","value":"%s","detail":"offline deterministic profile"},{"title":"Columns","value":"%s","detail":"host rendering preference"},{"title":"Input","value":"dry run","detail":"no synthesized input unless host opts in"}],"source":"affinity-photo-hotkeys.sh"}\n' \
  "$(json_escape "$persona")" "$columns" "$dry_run" "$hotkeys" "$dry_run" "$dry_run" "$(json_escape "$persona")" "$(json_escape "$persona")" "$columns"
