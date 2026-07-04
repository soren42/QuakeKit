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

printf '{"status":"%s","rows":[{"title":"Capture","value":"%s","detail":"%s"},{"title":"Backend","value":"%s","detail":"local/API backend boundary"},{"title":"Summary","value":"%s","detail":"%s"},{"title":"Transcript","value":"Ready","detail":"%s"}],"source":"meeting-notes.sh"}\n' \
  "$(json_escape "$state")" "$(json_escape "$capture")" "$(json_escape "$detail")" "$(json_escape "$backend")" "$(json_escape "$format")" "$(json_escape "$state")" "$(json_escape "$transcript")"
