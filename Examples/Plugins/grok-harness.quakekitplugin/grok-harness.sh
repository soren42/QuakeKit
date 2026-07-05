#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_GROK_MODEL:-grok}"
mode="${QUAKEKIT_GROK_MODE:-assistant}"
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
case "$mode" in
  research) workflow="Research"; next="Route concise research brief to xAI API." ;;
  briefing) workflow="Briefing"; next="Generate short situation report for panel display." ;;
  *) mode="assistant"; workflow="General assistant"; next="Send prompt through xAI API boundary." ;;
esac
connected=false
[ -n "${XAI_API_KEY:-}" ] && connected=true
printf '{"ok":true,"adapter":"grok-harness.sh","mode":"offline-safe","provider":"Grok","vendor":"xAI","model":"%s","workflow":"%s","connected":%s,"credential":"%s","status":"%s","actions":[{"id":"grok.refresh","title":"Refresh Session","enabled":true,"dryRun":true},{"id":"grok.sendPrompt","title":"Send Prompt","enabled":%s,"dryRun":true,"boundary":"official xAI API"},{"id":"grok.brief","title":"Generate Brief","enabled":true,"dryRun":true}],"rows":[{"title":"Provider","value":"Grok","detail":"official xAI API boundary"},{"title":"Model","value":"%s","detail":"configured model alias"},{"title":"Workflow","value":"%s","detail":"%s"},{"title":"Credential","value":"%s","detail":"secret never displayed on panel"},{"title":"Next","value":"Ready","detail":"%s"}],"source":"grok-harness.sh"}\n' \
  "$(json_escape "$model")" "$(json_escape "$mode")" "$connected" "$( [ "$connected" = true ] && printf configured || printf missing )" "$( [ "$connected" = true ] && printf ready || printf needs_key )" "$connected" "$(json_escape "$model")" "$(json_escape "$workflow")" "$(json_escape "$mode")" "$( [ "$connected" = true ] && printf configured || printf missing )" "$(json_escape "$next")"
