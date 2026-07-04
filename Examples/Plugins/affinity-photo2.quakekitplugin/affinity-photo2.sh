#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool_value() {
  case "${1:-}" in false|0|no|off) printf 'false' ;; *) printf 'true' ;; esac
}

persona="${QUAKEKIT_AFFINITY_PERSONA:-auto}"
document="${QUAKEKIT_AFFINITY_DOCUMENT:-}"
dry_run="$(bool_value "${QUAKEKIT_AFFINITY_DRY_RUN:-true}")"
frontmost=false
window_title=""

if command -v osascript >/dev/null 2>&1; then
  front_app="$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || true)"
  window_title="$(osascript -e 'tell application "System Events" to tell (first application process whose frontmost is true) to if exists window 1 then name of window 1 else ""' 2>/dev/null || true)"
  case "$front_app" in "Affinity Photo 2"*) frontmost=true ;; esac
fi

[ -n "$document" ] || document="${window_title:-Untitled Photo}"
if [ "$persona" = "auto" ]; then
  case "$window_title" in
    *Develop*) persona="develop" ;;
    *Liquify*) persona="liquify" ;;
    *Export*) persona="export" ;;
    *) persona="photo" ;;
  esac
fi

case "$persona" in
  develop)
    tools='[{"id":"exposure","title":"Exposure","keys":"Control+E"},{"id":"white-balance","title":"White Balance","keys":"W"},{"id":"lens","title":"Lens","keys":"Control+L"},{"id":"develop","title":"Develop","keys":"Control+Return"}]'
    ;;
  liquify)
    tools='[{"id":"push","title":"Push","keys":"P"},{"id":"twirl","title":"Twirl","keys":"T"},{"id":"freeze","title":"Freeze","keys":"F"},{"id":"apply","title":"Apply","keys":"Return"}]'
    ;;
  export)
    tools='[{"id":"export","title":"Export","keys":"Command+Option+Shift+S"},{"id":"slices","title":"Slices","keys":"S"},{"id":"preview","title":"Preview","keys":"Space"},{"id":"share","title":"Share","keys":"Command+Shift+E"}]'
    ;;
  *)
    persona="photo"
    tools='[{"id":"brush","title":"Brush","keys":"B"},{"id":"inpaint","title":"Inpaint","keys":"J"},{"id":"crop","title":"Crop","keys":"C"},{"id":"curves","title":"Curves","keys":"Command+M"},{"id":"levels","title":"Levels","keys":"Command+L"},{"id":"export","title":"Export","keys":"Command+Option+Shift+S"}]'
    ;;
esac

printf '{"ok":true,"adapter":"affinity-photo2.sh","frontmost":%s,"document":"%s","persona":"%s","dryRun":%s,"tools":%s,"rows":[{"title":"Document","value":"%s","detail":"frontmost %s"},{"title":"Persona","value":"%s","detail":"context action grid"},{"title":"Safety","value":"Dry Run %s","detail":"no synthetic input by default"}],"source":"affinity-photo2.sh"}\n' \
  "$frontmost" "$(json_escape "$document")" "$(json_escape "$persona")" "$dry_run" "$tools" "$(json_escape "$document")" "$frontmost" "$(json_escape "$persona")" "$dry_run"
