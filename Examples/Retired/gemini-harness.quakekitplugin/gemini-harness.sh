#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_GEMINI_MODEL:-gemini-pro}"
mode="${QUAKEKIT_GEMINI_MODE:-assistant}"
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
case "$mode" in
  meeting_summary) workflow="Meeting summary"; next="Summarize transcript and extract follow-ups." ;;
  research) workflow="Research"; next="Prepare grounded research prompt for Google API." ;;
  *) mode="assistant"; workflow="General assistant"; next="Send prompt through Gemini API boundary." ;;
esac
connected=false
[ -n "${GEMINI_API_KEY:-}" ] && connected=true
printf '{"ok":true,"adapter":"gemini-harness.sh","mode":"offline-safe","provider":"Gemini","vendor":"Google","model":"%s","workflow":"%s","connected":%s,"credential":"%s","status":"%s","actions":[{"id":"gemini.refresh","title":"Refresh Session","enabled":true,"dryRun":true},{"id":"gemini.sendPrompt","title":"Send Prompt","enabled":%s,"dryRun":true,"boundary":"official Google API"},{"id":"gemini.researchBrief","title":"Research Brief","enabled":true,"dryRun":true}],"rows":[{"title":"Provider","value":"Gemini","detail":"official Google API boundary"},{"title":"Model","value":"%s","detail":"configured model alias"},{"title":"Workflow","value":"%s","detail":"%s"},{"title":"Credential","value":"%s","detail":"secret never displayed on panel"},{"title":"Next","value":"Ready","detail":"%s"}],"source":"gemini-harness.sh"}\n' \
  "$(json_escape "$model")" "$(json_escape "$mode")" "$connected" "$( [ "$connected" = true ] && printf configured || printf missing )" "$( [ "$connected" = true ] && printf ready || printf needs_key )" "$connected" "$(json_escape "$model")" "$(json_escape "$workflow")" "$(json_escape "$mode")" "$( [ "$connected" = true ] && printf configured || printf missing )" "$(json_escape "$next")"
