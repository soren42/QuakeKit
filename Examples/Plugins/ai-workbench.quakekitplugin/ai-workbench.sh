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

bool_value() {
  case "${1:-}" in
    false|0|no|off) printf 'false' ;;
    *) printf 'true' ;;
  esac
}

provider="${QUAKEKIT_AI_PROVIDER:-Codex}"
project="${QUAKEKIT_AI_PROJECT_PATH:-${PWD:-Unknown Project}}"
agents="$(int_value "${QUAKEKIT_AI_AGENT_COUNT:-0}")"
used="$(int_value "${QUAKEKIT_AI_TOKENS_USED:-0}")"
remaining="$(int_value "${QUAKEKIT_AI_TOKENS_REMAINING:-0}")"
queue="$(int_value "${QUAKEKIT_AI_QUEUE_DEPTH:-0}")"
health="${QUAKEKIT_AI_HEALTH_MODE:-normal}"
limit="${QUAKEKIT_AI_WORK_LIMIT:-session}"
status_file="${QUAKEKIT_AI_STATUS_FILE:-}"
dry_run="$(bool_value "${QUAKEKIT_AI_DRY_RUN:-true}")"

if [ -n "$status_file" ] && [ -r "$status_file" ]; then
  old_ifs=$IFS
  IFS='|'
  set -- $(sed -n '1p' "$status_file")
  IFS=$old_ifs
  provider="${1:-$provider}"; project="${2:-$project}"; agents="$(int_value "${3:-$agents}")"; used="$(int_value "${4:-$used}")"; remaining="$(int_value "${5:-$remaining}")"; limit="${6:-$limit}"; queue="$(int_value "${7:-$queue}")"; health="${8:-$health}"
fi

case "$health" in
  focus|limited|blocked) ;;
  *) health="normal" ;;
esac

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

case "$health" in
  focus) recommendation="Keep current agent set; defer new starts." ;;
  limited) recommendation="Reduce queue or raise work limit before launching more agents." ;;
  blocked) recommendation="Review blocked task before continuing." ;;
  *) recommendation="Workbench is ready for another task." ;;
esac

printf '{"ok":true,"adapter":"ai-workbench.sh","mode":"offline-safe","dryRun":%s,"provider":"%s","project":"%s","projectName":"%s","agents":%s,"tokensUsed":%s,"tokensRemaining":%s,"usagePercent":%s,"workLimit":"%s","queueDepth":%s,"healthMode":"%s","recommendation":"%s","companions":[{"id":"claude","title":"Claude"},{"id":"claude-code","title":"Claude Code"},{"id":"chatgpt","title":"ChatGPT"},{"id":"codex","title":"Codex"},{"id":"gemini","title":"Gemini"},{"id":"antigravity","title":"Antigravity"}],"actions":[{"id":"ai.refresh","enabled":true,"dryRun":%s},{"id":"ai.pauseAgents","enabled":true,"dryRun":%s,"targetAgents":%s},{"id":"ai.copySummary","enabled":true,"dryRun":%s},{"id":"ai.openProject","enabled":true,"dryRun":%s,"path":"%s"},{"id":"ai.setFocusMode","enabled":true,"dryRun":%s,"healthMode":"focus"}],"tasks":[{"title":"Review active agents","state":"ready","count":%s},{"title":"Drain queue","state":"planned","count":%s},{"title":"Check work limit","state":"%s","count":1}],"rows":[{"title":"Project","value":"%s","detail":"%s"},{"title":"Agents","value":"%s","detail":"provider %s"},{"title":"Tokens","value":"%s%% used","detail":"%s used / %s remaining"},{"title":"Queue","value":"%s","detail":"%s"},{"title":"Limit","value":"%s","detail":"status file or env supplied"}],"source":"ai-workbench.sh"}\n' \
  "$dry_run" "$(json_escape "$provider")" "$(json_escape "$project")" "$(json_escape "$project_name")" "$agents" "$used" "$remaining" "$pct" "$(json_escape "$limit")" "$queue" "$(json_escape "$health")" "$(json_escape "$recommendation")" \
  "$dry_run" "$dry_run" "$agents" "$dry_run" "$dry_run" "$(json_escape "$project")" "$dry_run" "$agents" "$queue" "$(json_escape "$health")" "$(json_escape "$project_name")" "$(json_escape "$project")" "$agents" "$(json_escape "$provider")" "$pct" "$used" "$remaining" "$queue" "$(json_escape "$recommendation")" "$(json_escape "$limit")"
