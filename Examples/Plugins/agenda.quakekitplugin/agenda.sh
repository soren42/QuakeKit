#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

file="${QUAKEKIT_AGENDA_FILE:-}"
calendar="${QUAKEKIT_AGENDA_CALENDAR:-Today}"
lookahead="${QUAKEKIT_AGENDA_LOOKAHEAD_HOURS:-12}"
case "$lookahead" in ''|*[!0-9]*) lookahead=12 ;; esac

events='[{"time":"09:00","title":"Planning","location":"Desk","status":"confirmed"},{"time":"11:30","title":"Project Review","location":"Video","status":"tentative"},{"time":"15:00","title":"Focus Block","location":"Office","status":"busy"}]'
next_title="Planning"
count=3

if [ -n "$file" ] && [ -r "$file" ]; then
  rows=""
  count=0
  next_title=""
  while IFS='|' read -r time title location status; do
    [ -n "${time:-}${title:-}" ] || continue
    [ -n "$title" ] || title="Untitled"
    [ -n "$location" ] || location="-"
    [ -n "$status" ] || status="confirmed"
    [ -n "$next_title" ] || next_title="$title"
    item='{"time":"'"$(json_escape "$time")"'","title":"'"$(json_escape "$title")"'","location":"'"$(json_escape "$location")"'","status":"'"$(json_escape "$status")"'"}'
    if [ -n "$rows" ]; then rows="$rows,$item"; else rows="$item"; fi
    count=$((count + 1))
  done < "$file"
  events="[$rows]"
fi
[ -n "$next_title" ] || next_title="No Events"

printf '{"ok":true,"adapter":"agenda.sh","calendar":"%s","lookaheadHours":%s,"eventCount":%s,"nextTitle":"%s","events":%s,"rows":[{"title":"Calendar","value":"%s","detail":"%s hour horizon"},{"title":"Next","value":"%s","detail":"%s events loaded"},{"title":"Source","value":"%s","detail":"offline-safe agenda fixture"}],"source":"agenda.sh"}\n' \
  "$(json_escape "$calendar")" "$lookahead" "$count" "$(json_escape "$next_title")" "$events" "$(json_escape "$calendar")" "$lookahead" "$(json_escape "$next_title")" "$count" "$( [ -n "$file" ] && printf file || printf fixture )"
