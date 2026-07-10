#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_CLAUDE_MODEL:-claude-sonnet}"
mode="${QUAKEKIT_CLAUDE_MODE:-assistant}"
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
case "$mode" in
  code_review) workflow="Code review"; next="Package git diff and request findings-first review." ;;
  meeting_summary) workflow="Meeting summary"; next="Summarize transcript into decisions, actions, and risks." ;;
  *) mode="assistant"; workflow="General assistant"; next="Send prompt through Anthropic API boundary." ;;
esac
prompt="${QUAKEKIT_CLAUDE_PROMPT_PREVIEW:-Review the current QuakeKit UI handoff and identify interface risks.}"
connected=false
[ -n "${ANTHROPIC_API_KEY:-}" ] && connected=true
printf '{"ok":true,"adapter":"claude-harness.sh","mode":"offline-safe","provider":"Claude","vendor":"Anthropic","model":"%s","workflow":"%s","connected":%s,"credential":"%s","promptPreview":"%s","nextStep":"%s","status":"%s","actions":[{"id":"claude.refresh","title":"Refresh Session","enabled":true,"dryRun":true},{"id":"claude.sendPrompt","title":"Send Prompt","enabled":%s,"dryRun":true,"boundary":"official Anthropic API"},{"id":"claude.reviewDiff","title":"Review Diff","enabled":true,"dryRun":true},{"id":"claude.extractActions","title":"Extract Actions","enabled":true,"dryRun":true}],"rows":[{"title":"Provider","value":"Claude","detail":"Anthropic API only, no consumer UI scraping"},{"title":"Model","value":"%s","detail":"configured model family"},{"title":"Workflow","value":"%s","detail":"%s"},{"title":"Credential","value":"%s","detail":"secret never displayed on panel"},{"title":"Next","value":"Ready","detail":"%s"}],"source":"claude-harness.sh"}\n' \
  "$(json_escape "$model")" "$(json_escape "$mode")" "$connected" "$( [ "$connected" = true ] && printf configured || printf missing )" "$(json_escape "$prompt")" "$(json_escape "$next")" "$( [ "$connected" = true ] && printf ready || printf needs_key )" "$connected" "$(json_escape "$model")" "$(json_escape "$workflow")" "$(json_escape "$mode")" "$( [ "$connected" = true ] && printf configured || printf missing )" "$(json_escape "$next")"
