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

app="${QUAKEKIT_TERMINAL_APP:-warp_ai}"
workspace="${QUAKEKIT_TERMINAL_WORKSPACE:-~/Code}"
session_file="${QUAKEKIT_TERMINAL_SESSION_FILE:-}"
dry_run="$(bool_value "${QUAKEKIT_TERMINAL_DRY_RUN:-true}")"

case "$app" in
  terminus) app_label="Terminus"; launch_hint="terminus://open" ;;
  terminus_beta) app_label="Terminus Beta"; launch_hint="terminus-beta://open" ;;
  *) app="warp_ai"; app_label="Warp AI"; launch_hint="warp://action/new_tab" ;;
esac

tab="${QUAKEKIT_TERMINAL_TAB:-QuakeKit}"
cwd="${QUAKEKIT_TERMINAL_CWD:-$workspace}"
command="${QUAKEKIT_TERMINAL_COMMAND:-git status --short}"
status="${QUAKEKIT_TERMINAL_STATUS:-idle}"

if [ -n "$session_file" ] && [ -r "$session_file" ]; then
  first_line="$(sed -n '1p' "$session_file")"
  old_ifs=$IFS
  IFS='|'
  set -- $first_line
  IFS=$old_ifs
  tab="${1:-$tab}"
  cwd="${2:-$cwd}"
  command="${3:-$command}"
  status="${4:-$status}"
fi

printf '{"ok":true,"adapter":"terminal-companions.sh","mode":"offline-safe","app":"%s","appLabel":"%s","workspace":"%s","session":{"tab":"%s","cwd":"%s","command":"%s","status":"%s"},"dryRun":%s,"actions":[{"id":"terminal.openWorkspace","enabled":true,"dryRun":%s,"url":"%s","workspace":"%s"},{"id":"terminal.runCommand","enabled":true,"dryRun":%s,"command":"%s"}],"rows":[{"title":"App","value":"%s","detail":"terminal companion fixture"},{"title":"Workspace","value":"%s","detail":"read-only context by default"},{"title":"Tab","value":"%s","detail":"%s"},{"title":"Command","value":"planned","detail":"%s"}],"source":"terminal-companions.sh"}\n' \
  "$(json_escape "$app")" "$(json_escape "$app_label")" "$(json_escape "$workspace")" "$(json_escape "$tab")" "$(json_escape "$cwd")" "$(json_escape "$command")" "$(json_escape "$status")" "$dry_run" \
  "$dry_run" "$(json_escape "$launch_hint")" "$(json_escape "$workspace")" "$dry_run" "$(json_escape "$command")" "$(json_escape "$app_label")" "$(json_escape "$workspace")" "$(json_escape "$tab")" "$(json_escape "$status")" "$(json_escape "$command")"
