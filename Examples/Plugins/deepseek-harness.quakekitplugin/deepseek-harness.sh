#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_DEEPSEEK_MODEL:-deepseek-chat}"
mode="${QUAKEKIT_DEEPSEEK_MODE:-assistant}"
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
case "$mode" in
  reasoning) workflow="Reasoning"; next="Route structured problem statement to DeepSeek API." ;;
  coding) workflow="Coding"; next="Attach file context and request implementation outline." ;;
  *) mode="assistant"; workflow="General assistant"; next="Send prompt through official DeepSeek API boundary." ;;
esac
connected=false
[ -n "${DEEPSEEK_API_KEY:-}" ] && connected=true
printf '{"ok":true,"adapter":"deepseek-harness.sh","mode":"offline-safe","provider":"DeepSeek","vendor":"DeepSeek","model":"%s","workflow":"%s","connected":%s,"credential":"%s","status":"%s","actions":[{"id":"deepseek.refresh","title":"Refresh Session","enabled":true,"dryRun":true},{"id":"deepseek.sendPrompt","title":"Send Prompt","enabled":%s,"dryRun":true,"boundary":"official DeepSeek API"},{"id":"deepseek.reason","title":"Reason Through","enabled":true,"dryRun":true}],"rows":[{"title":"Provider","value":"DeepSeek","detail":"official API boundary"},{"title":"Model","value":"%s","detail":"configured model alias"},{"title":"Workflow","value":"%s","detail":"%s"},{"title":"Credential","value":"%s","detail":"secret never displayed on panel"},{"title":"Next","value":"Ready","detail":"%s"}],"source":"deepseek-harness.sh"}\n' \
  "$(json_escape "$model")" "$(json_escape "$mode")" "$connected" "$( [ "$connected" = true ] && printf configured || printf missing )" "$( [ "$connected" = true ] && printf ready || printf needs_key )" "$connected" "$(json_escape "$model")" "$(json_escape "$workflow")" "$(json_escape "$mode")" "$( [ "$connected" = true ] && printf configured || printf missing )" "$(json_escape "$next")"
