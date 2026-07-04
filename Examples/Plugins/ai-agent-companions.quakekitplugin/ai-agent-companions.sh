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

agent="${QUAKEKIT_AI_AGENT:-codex}"
workflow="${QUAKEKIT_AI_WORKFLOW:-handoff}"
context_file="${QUAKEKIT_AI_CONTEXT_FILE:-}"
dry_run="$(bool_value "${QUAKEKIT_AI_DRY_RUN:-true}")"

case "$agent" in
  claude) label="Claude"; boundary="Anthropic API or local app handoff"; launch="claude://" ;;
  claude_code) label="Claude Code"; boundary="local CLI companion"; launch="claude-code://" ;;
  chatgpt) label="ChatGPT"; boundary="OpenAI API or app handoff"; launch="chatgpt://" ;;
  gemini) label="Gemini"; boundary="Google API or local companion"; launch="gemini://" ;;
  antigravity) label="Antigravity"; boundary="local IDE companion"; launch="antigravity://" ;;
  *) agent="codex"; label="Codex"; boundary="local Codex companion"; launch="codex://" ;;
esac
case "$workflow" in
  review|implementation|research) ;;
  *) workflow="handoff" ;;
esac

task="${QUAKEKIT_AI_TASK:-Inspect workspace context and prepare a concise next step.}"
branch="${QUAKEKIT_AI_BRANCH:-main}"
status="${QUAKEKIT_AI_STATUS:-ready}"
next_step="${QUAKEKIT_AI_NEXT_STEP:-Open companion with current workspace context.}"

if [ -n "$context_file" ] && [ -r "$context_file" ]; then
  first_line="$(sed -n '1p' "$context_file")"
  old_ifs=$IFS
  IFS='|'
  set -- $first_line
  IFS=$old_ifs
  task="${1:-$task}"
  branch="${2:-$branch}"
  status="${3:-$status}"
  next_step="${4:-$next_step}"
fi

printf '{"ok":true,"adapter":"ai-agent-companions.sh","mode":"offline-safe","agent":"%s","label":"%s","workflow":"%s","dryRun":%s,"context":{"task":"%s","branch":"%s","status":"%s","nextStep":"%s"},"actions":[{"id":"agent.openCompanion","enabled":true,"dryRun":%s,"launch":"%s"},{"id":"agent.sendPrompt","enabled":true,"dryRun":%s,"boundary":"%s","prompt":"%s"}],"rows":[{"title":"Agent","value":"%s","detail":"%s"},{"title":"Workflow","value":"%s","detail":"deterministic companion preset"},{"title":"Task","value":"ready","detail":"%s"},{"title":"Next","value":"planned","detail":"%s"}],"source":"ai-agent-companions.sh"}\n' \
  "$(json_escape "$agent")" "$(json_escape "$label")" "$(json_escape "$workflow")" "$dry_run" "$(json_escape "$task")" "$(json_escape "$branch")" "$(json_escape "$status")" "$(json_escape "$next_step")" \
  "$dry_run" "$(json_escape "$launch")" "$dry_run" "$(json_escape "$boundary")" "$(json_escape "$task")" "$(json_escape "$label")" "$(json_escape "$boundary")" "$(json_escape "$workflow")" "$(json_escape "$task")" "$(json_escape "$next_step")"
