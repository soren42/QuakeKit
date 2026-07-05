#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_OPENAI_MODEL:-gpt-4.1}"
mode="${QUAKEKIT_OPENAI_MODE:-assistant}"
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
case "$mode" in
  voice) workflow="Voice assistant"; next="Request microphone access, then stream transcript to official API." ;;
  meeting_summary) workflow="Meeting summary"; next="Record clip, transcribe, summarize action items." ;;
  coding) workflow="Coding copilot"; next="Attach workspace summary and ask for implementation plan." ;;
  *) mode="assistant"; workflow="General assistant"; next="Send focused prompt through official API boundary." ;;
esac
prompt="${QUAKEKIT_OPENAI_PROMPT_PREVIEW:-Summarize the current QuakeKit panel state and suggest the next useful action.}"
connected=false
[ -n "${OPENAI_API_KEY:-}" ] && connected=true
printf '{"ok":true,"adapter":"chatgpt-harness.sh","mode":"offline-safe","provider":"ChatGPT","vendor":"OpenAI","model":"%s","workflow":"%s","connected":%s,"credential":"%s","promptPreview":"%s","nextStep":"%s","status":"%s","actions":[{"id":"chatgpt.refresh","title":"Refresh Session","enabled":true,"dryRun":true},{"id":"chatgpt.sendPrompt","title":"Send Prompt","enabled":%s,"dryRun":true,"boundary":"official OpenAI API"},{"id":"chatgpt.startVoice","title":"Start Voice","enabled":true,"dryRun":true},{"id":"chatgpt.summarizeMeeting","title":"Summarize Meeting","enabled":true,"dryRun":true}],"rows":[{"title":"Provider","value":"ChatGPT","detail":"official OpenAI API boundary"},{"title":"Model","value":"%s","detail":"configured model alias"},{"title":"Workflow","value":"%s","detail":"%s"},{"title":"Credential","value":"%s","detail":"secret never displayed on panel"},{"title":"Next","value":"Ready","detail":"%s"}],"source":"chatgpt-harness.sh"}\n' \
  "$(json_escape "$model")" "$(json_escape "$mode")" "$connected" "$( [ "$connected" = true ] && printf configured || printf missing )" "$(json_escape "$prompt")" "$(json_escape "$next")" "$( [ "$connected" = true ] && printf ready || printf needs_key )" "$connected" "$(json_escape "$model")" "$(json_escape "$workflow")" "$(json_escape "$mode")" "$( [ "$connected" = true ] && printf configured || printf missing )" "$(json_escape "$next")"
