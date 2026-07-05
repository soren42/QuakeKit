#!/bin/sh
set -eu

request="$(cat)"
method="$(printf '%s' "$request" | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
capture="${QUAKEKIT_MEETING_CAPTURE_MODE:-audio_file}"
audio_file="${QUAKEKIT_MEETING_AUDIO_FILE:-}"
backend="${QUAKEKIT_MEETING_TRANSCRIBE_BACKEND:-whisper_cli}"
format="${QUAKEKIT_MEETING_SUMMARY_FORMAT:-action_items}"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

state="ready"
detail="Configure an audio file or future live recorder."
transcript="No transcript loaded."
meeting_title="${QUAKEKIT_MEETING_TITLE:-QuakeKit Design Review}"
participants="${QUAKEKIT_MEETING_PARTICIPANTS:-Jason,Codex,Design Review}"
duration="${QUAKEKIT_MEETING_DURATION_MINUTES:-30}"
if [ -n "$audio_file" ] && [ -f "$audio_file" ] && command -v whisper >/dev/null 2>&1; then
  out_dir="$(mktemp -d -t quakekit-meeting)"
  if whisper "$audio_file" --model tiny --output_format txt --output_dir "$out_dir" >/dev/null 2>&1; then
    transcript_file="$(find "$out_dir" -name '*.txt' -type f | head -n 1)"
    if [ -n "$transcript_file" ] && [ -f "$transcript_file" ]; then
      transcript="$(sed -n '1,10p' "$transcript_file" | tr '\n' ' ')"
      state="transcribed"
      detail="local whisper"
    fi
  fi
  rm -rf "$out_dir"
fi

case "$method" in
  action.meeting.record) state="recording stub"; detail="host recorder not enabled yet" ;;
  action.meeting.transcribe) : ;;
  action.meeting.summarize) state="summary ready"; detail="$format" ;;
  action.meeting.export) state="export stub"; detail="filesystem permission declared" ;;
esac

printf '{"ok":true,"adapter":"meeting-notes.sh","mode":"offline-safe","status":"%s","meetingTitle":"%s","participants":"%s","durationMinutes":%s,"captureMode":"%s","backend":"%s","summaryFormat":"%s","transcriptPreview":"%s","summaryBullets":["Panel settings need visual hierarchy","Plugin payloads should provide rows and actions","Claude Design handoff should stay UI-only"],"actionItems":[{"owner":"Codex","task":"Keep adapters deterministic","state":"done"},{"owner":"Claude Design","task":"Redesign main menu and panel shell","state":"handoff"}],"decisions":["Use official API boundaries for LLM harnesses","Keep package install/remove in primary settings window"],"exportFormats":["markdown","json","text"],"actions":[{"id":"meeting.record","enabled":true,"dryRun":true},{"id":"meeting.transcribe","enabled":true,"dryRun":true},{"id":"meeting.summarize","enabled":true,"dryRun":true},{"id":"meeting.export","enabled":true,"dryRun":true}],"rows":[{"title":"Meeting","value":"%s","detail":"%s min · %s"},{"title":"Capture","value":"%s","detail":"%s"},{"title":"Backend","value":"%s","detail":"local/API backend boundary"},{"title":"Summary","value":"%s","detail":"%s"},{"title":"Transcript","value":"Ready","detail":"%s"}],"source":"meeting-notes.sh"}\n' \
  "$(json_escape "$state")" "$(json_escape "$meeting_title")" "$(json_escape "$participants")" "$duration" "$(json_escape "$capture")" "$(json_escape "$backend")" "$(json_escape "$format")" "$(json_escape "$transcript")" \
  "$(json_escape "$meeting_title")" "$duration" "$(json_escape "$participants")" "$(json_escape "$capture")" "$(json_escape "$detail")" "$(json_escape "$backend")" "$(json_escape "$format")" "$(json_escape "$state")" "$(json_escape "$transcript")"
