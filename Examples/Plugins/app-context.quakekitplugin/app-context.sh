#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

mode="${QUAKEKIT_CONTEXT_PROFILE_MODE:-auto}"
app="${QUAKEKIT_CONTEXT_MANUAL_APP:-}"
title="${QUAKEKIT_CONTEXT_WINDOW_TITLE:-}"

if [ "$mode" = "auto" ] && command -v osascript >/dev/null 2>&1; then
  detected_app="$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || true)"
  detected_title="$(osascript -e 'tell application "System Events" to tell (first application process whose frontmost is true) to if exists window 1 then name of window 1 else ""' 2>/dev/null || true)"
  [ -n "$detected_app" ] && app="$detected_app"
  [ -n "$detected_title" ] && title="$detected_title"
fi

[ -n "$app" ] || app="Unknown"
[ -n "$title" ] || title="-"

case "$app" in
  "Affinity Photo 2"*) profile="affinity_photo"; family="creative" ;;
  "Warp"*) profile="warp_terminal"; family="terminal" ;;
  "Terminus"*) profile="terminus"; family="terminal" ;;
  "Claude"*|"ChatGPT"*|"Codex"*|"Gemini"*|"Antigravity"*) profile="ai_workbench"; family="ai" ;;
  "Spotify"*) profile="spotify"; family="media" ;;
  "Safari"|"Google Chrome"|"Arc"|"Microsoft Edge") profile="browser"; family="browser" ;;
  *) profile="default"; family="general" ;;
esac

printf '{"ok":true,"adapter":"app-context.sh","mode":"%s","appName":"%s","windowTitle":"%s","profile":"%s","family":"%s","rows":[{"title":"Frontmost","value":"%s","detail":"%s"},{"title":"Profile","value":"%s","detail":"%s companion routing"},{"title":"Source","value":"%s","detail":"manual fallback remains available"}],"source":"app-context.sh"}\n' \
  "$(json_escape "$mode")" "$(json_escape "$app")" "$(json_escape "$title")" "$(json_escape "$profile")" "$(json_escape "$family")" "$(json_escape "$app")" "$(json_escape "$title")" "$(json_escape "$profile")" "$(json_escape "$family")" "$(json_escape "$mode")"
