#!/bin/sh
set -eu
cat >/dev/null
workspace="${QUAKEKIT_CURSOR_WORKSPACE:-~/Code}"
mode="${QUAKEKIT_CURSOR_MODE:-status}"
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
expanded_workspace="$(eval printf '%s' "$workspace" 2>/dev/null || printf '%s' "$workspace")"
project="$(basename "$expanded_workspace" 2>/dev/null || printf '%s' "$workspace")"
case "$mode" in
  tasks) workflow="Task queue"; next="Show pending TODOs and recent command status." ;;
  handoff) workflow="Handoff"; next="Prepare concise context packet for another agent." ;;
  *) mode="status"; workflow="Workspace status"; next="Display project, branch, and safe launch action." ;;
esac
branch="-"
if command -v git >/dev/null 2>&1 && [ -d "$expanded_workspace/.git" ]; then
  branch="$(git -C "$expanded_workspace" branch --show-current 2>/dev/null || printf '-')"
fi
running=false
pgrep -if "Cursor" >/dev/null 2>&1 && running=true
printf '{"ok":true,"adapter":"cursor-harness.sh","mode":"offline-safe","provider":"Cursor","workspace":"%s","project":"%s","branch":"%s","workflow":"%s","running":%s,"status":"ready","actions":[{"id":"cursor.refresh","title":"Refresh Workspace","enabled":true,"dryRun":true},{"id":"cursor.openWorkspace","title":"Open Workspace","enabled":true,"dryRun":true,"path":"%s"},{"id":"cursor.copyHandoff","title":"Copy Handoff","enabled":true,"dryRun":true}],"rows":[{"title":"Provider","value":"Cursor","detail":"local companion boundary"},{"title":"Workspace","value":"%s","detail":"%s"},{"title":"Branch","value":"%s","detail":"read-only git context"},{"title":"Workflow","value":"%s","detail":"%s"},{"title":"Next","value":"Ready","detail":"%s"}],"source":"cursor-harness.sh"}\n' \
  "$(json_escape "$expanded_workspace")" "$(json_escape "$project")" "$(json_escape "$branch")" "$(json_escape "$mode")" "$running" "$(json_escape "$expanded_workspace")" "$(json_escape "$project")" "$(json_escape "$expanded_workspace")" "$(json_escape "$branch")" "$(json_escape "$workflow")" "$(json_escape "$mode")" "$(json_escape "$next")"
