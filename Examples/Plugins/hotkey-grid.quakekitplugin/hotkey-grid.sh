#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

profile="${QUAKEKIT_HOTKEY_GRID_PROFILE:-default}"
frontmost="${QUAKEKIT_FRONTMOST_APP:-}"
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

if [ -z "$frontmost" ] && command -v osascript >/dev/null 2>&1; then
  frontmost="$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || true)"
fi
[ -n "$frontmost" ] || frontmost="Unknown"

if [ "$profile" = "auto" ]; then
  case "$frontmost" in
    "Affinity Photo 2"*) profile="affinity_photo" ;;
    "Warp"*|"Terminus"*|"Terminal"*|"iTerm2") profile="terminal" ;;
    "Claude"*|"ChatGPT"*|"Codex"*|"Gemini"*|"Antigravity"*) profile="ai_workbench" ;;
    "Spotify"*) profile="spotify" ;;
    "Safari"|"Google Chrome"|"Arc"|"Microsoft Edge") profile="youtube" ;;
    *) profile="default" ;;
  esac
fi

case "$profile" in
  affinity_photo)
    hotkeys='[{"id":"brush","title":"Brush","keys":"B"},{"id":"inpaint","title":"Inpaint","keys":"J"},{"id":"crop","title":"Crop","keys":"C"},{"id":"curves","title":"Curves","keys":"Command+M"},{"id":"develop","title":"Develop","keys":"Control+Option+D"},{"id":"export","title":"Export","keys":"Command+Option+Shift+S"}]'
    ;;
  terminal)
    hotkeys='[{"id":"new-tab","title":"New Tab","keys":"Command+T"},{"id":"split","title":"Split","keys":"Command+D"},{"id":"clear","title":"Clear","keys":"Command+K"},{"id":"interrupt","title":"Interrupt","keys":"Control+C"},{"id":"rerun","title":"Rerun","keys":"Up, Return"},{"id":"copy-path","title":"Copy Path","keys":"Command+Option+C"}]'
    ;;
  ai_workbench)
    hotkeys='[{"id":"new-agent","title":"New Agent","keys":"Command+N"},{"id":"stop","title":"Stop","keys":"Escape"},{"id":"submit","title":"Submit","keys":"Command+Return"},{"id":"copy-result","title":"Copy Result","keys":"Command+Shift+C"},{"id":"toggle-plan","title":"Plan","keys":"Command+Option+P"},{"id":"open-log","title":"Logs","keys":"Command+L"}]'
    ;;
  youtube)
    hotkeys='[{"id":"play-pause","title":"Play","keys":"Space"},{"id":"mute","title":"Mute","keys":"M"},{"id":"captions","title":"Captions","keys":"C"},{"id":"rewind","title":"Back 10s","keys":"J"},{"id":"forward","title":"Forward 10s","keys":"L"},{"id":"fullscreen","title":"Fullscreen","keys":"F"}]'
    ;;
  spotify)
    hotkeys='[{"id":"play-pause","title":"Play","keys":"Media Play"},{"id":"previous","title":"Previous","keys":"Media Previous"},{"id":"next","title":"Next","keys":"Media Next"},{"id":"like","title":"Like","keys":"Command+L"},{"id":"search","title":"Search","keys":"Command+L"},{"id":"volume","title":"Volume","keys":"Media Volume"}]'
    ;;
  streaming)
    hotkeys='[{"id":"mute","title":"Mute","keys":"Command+Shift+M"},{"id":"clip","title":"Clip","keys":"Command+Shift+C"},{"id":"scene","title":"Scene","keys":"Command+Shift+S"},{"id":"blank","title":"Blank","keys":"Command+Shift+B"}]'
    ;;
  *)
    hotkeys='[{"id":"mute","title":"Mute","keys":"Command+Shift+M"},{"id":"clip","title":"Clip","keys":"Command+Shift+C"},{"id":"focus","title":"Focus","keys":"Command+Option+F"},{"id":"blank","title":"Blank Screen","keys":"Command+Shift+B"}]'
    ;;
esac

printf '{"ok":true,"adapter":"hotkey-grid.sh","ack":{"triggered":false,"reason":"safe stub"},"profile":"%s","frontmostApp":"%s","columns":%s,"dryRun":%s,"hotkeys":%s,"rows":[{"title":"Profile","value":"%s","detail":"frontmost %s"},{"title":"Dry Run","value":"%s","detail":"input synthesis is declared but disabled by default"},{"title":"Grid","value":"%s columns","detail":"context-aware actions"}]}\n' \
  "$(json_escape "$profile")" "$(json_escape "$frontmost")" "$columns" "$dry_run" "$hotkeys" "$(json_escape "$profile")" "$(json_escape "$frontmost")" "$dry_run" "$columns"
