#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

int_value() {
  value="${1:-0}"
  case "$value" in ''|*[!0-9]*) value=0 ;; esac
  printf '%s' "$value"
}

provider="${QUAKEKIT_AI_PROVIDER:-Codex}"
project="${QUAKEKIT_AI_PROJECT_PATH:-${PWD:-Unknown Project}}"
agents="$(int_value "${QUAKEKIT_AI_AGENT_COUNT:-0}")"
used="$(int_value "${QUAKEKIT_AI_TOKENS_USED:-0}")"
remaining="$(int_value "${QUAKEKIT_AI_TOKENS_REMAINING:-0}")"
limit="${QUAKEKIT_AI_WORK_LIMIT:-session}"
status_file="${QUAKEKIT_AI_STATUS_FILE:-}"

if [ -n "$status_file" ] && [ -r "$status_file" ]; then
  old_ifs=$IFS
  IFS='|'
  set -- $(sed -n '1p' "$status_file")
  IFS=$old_ifs
  provider="${1:-$provider}"; project="${2:-$project}"; agents="$(int_value "${3:-$agents}")"; used="$(int_value "${4:-$used}")"; remaining="$(int_value "${5:-$remaining}")"; limit="${6:-$limit}"
fi

if [ "$agents" -eq 0 ]; then
  detected="$(ps ax -o comm= 2>/dev/null | grep -E 'Codex|Claude|ChatGPT|Gemini|Antigravity|cursor|Cursor' | wc -l | tr -d ' ')"
  agents="$(int_value "$detected")"
fi
[ "$agents" -gt 0 ] || agents=1

if command -v basename >/dev/null 2>&1; then
  project_name="$(basename "$project")"
else
  project_name="$project"
fi

total=$((used + remaining))
if [ "$total" -gt 0 ]; then
  pct=$((used * 100 / total))
else
  pct=0
fi

printf '{"ok":true,"adapter":"ai-workbench.sh","provider":"%s","project":"%s","projectName":"%s","agents":%s,"tokensUsed":%s,"tokensRemaining":%s,"usagePercent":%s,"workLimit":"%s","companions":[{"id":"claude","title":"Claude"},{"id":"claude-code","title":"Claude Code"},{"id":"chatgpt","title":"ChatGPT"},{"id":"codex","title":"Codex"},{"id":"gemini","title":"Gemini"},{"id":"antigravity","title":"Antigravity"}],"rows":[{"title":"Project","value":"%s","detail":"%s"},{"title":"Agents","value":"%s","detail":"provider %s"},{"title":"Tokens","value":"%s%% used","detail":"%s used / %s remaining"},{"title":"Limit","value":"%s","detail":"status file or env supplied"}],"source":"ai-workbench.sh"}\n' \
  "$(json_escape "$provider")" "$(json_escape "$project")" "$(json_escape "$project_name")" "$agents" "$used" "$remaining" "$pct" "$(json_escape "$limit")" "$(json_escape "$project_name")" "$(json_escape "$project")" "$agents" "$(json_escape "$provider")" "$pct" "$used" "$remaining" "$(json_escape "$limit")"
