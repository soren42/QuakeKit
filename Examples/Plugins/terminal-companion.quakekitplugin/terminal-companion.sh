#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool_value() {
  case "${1:-}" in false|0|no|off) printf 'false' ;; *) printf 'true' ;; esac
}

app="${QUAKEKIT_TERMINAL_APP:-auto}"
project="${QUAKEKIT_TERMINAL_PROJECT:-${PWD:-}}"
status="${QUAKEKIT_TERMINAL_LAST_STATUS:-0}"
dry_run="$(bool_value "${QUAKEKIT_TERMINAL_DRY_RUN:-true}")"
window_title="${QUAKEKIT_TERMINAL_WINDOW_TITLE:-}"

case "$status" in ''|*[!0-9]*) status=0 ;; esac

if [ "$app" = "auto" ] && command -v osascript >/dev/null 2>&1; then
  detected="$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || true)"
  title="$(osascript -e 'tell application "System Events" to tell (first application process whose frontmost is true) to if exists window 1 then name of window 1 else ""' 2>/dev/null || true)"
  case "$detected" in "Warp"*|"Terminus"*|"Terminal"|"iTerm2") app="$detected" ;; *) app="Terminal" ;; esac
  [ -n "$title" ] && window_title="$title"
fi
[ "$app" != "auto" ] || app="Terminal"

case "$app" in
  "Warp"*) profile="warp_ai"; split_key="Command+D"; ai_key="Command+I" ;;
  "Terminus Beta"*) profile="terminus_beta"; split_key="Command+Shift+D"; ai_key="Command+Option+I" ;;
  "Terminus"*) profile="terminus"; split_key="Command+Shift+D"; ai_key="Command+Option+I" ;;
  "iTerm2") profile="iterm2"; split_key="Command+D"; ai_key="Command+Option+A" ;;
  *) profile="terminal"; split_key="Command+D"; ai_key="-" ;;
esac

actions='[{"id":"terminal.newTab","title":"New Tab","keys":"Command+T"},{"id":"terminal.splitPane","title":"Split Pane","keys":"'"$split_key"'"},{"id":"terminal.interrupt","title":"Interrupt","keys":"Control+C"},{"id":"terminal.clear","title":"Clear","keys":"Command+K"},{"id":"terminal.ai","title":"AI Prompt","keys":"'"$ai_key"'"}]'

printf '{"ok":true,"adapter":"terminal-companion.sh","app":"%s","profile":"%s","project":"%s","windowTitle":"%s","lastStatus":%s,"dryRun":%s,"actions":%s,"rows":[{"title":"Terminal","value":"%s","detail":"%s"},{"title":"Project","value":"%s","detail":"last status %s"},{"title":"Actions","value":"%s","detail":"dry-run %s"}],"source":"terminal-companion.sh"}\n' \
  "$(json_escape "$app")" "$(json_escape "$profile")" "$(json_escape "$project")" "$(json_escape "$window_title")" "$status" "$dry_run" "$actions" "$(json_escape "$app")" "$(json_escape "$window_title")" "$(json_escape "$project")" "$status" "$(json_escape "$profile")" "$dry_run"
