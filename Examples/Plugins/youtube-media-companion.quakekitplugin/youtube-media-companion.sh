#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool_value() {
  case "${1:-}" in
    false|0|no|off) printf 'false' ;;
    *) printf 'true' ;;
  esac
}

seconds_value() {
  value="${1:-0}"
  case "$value" in
    ''|*[!0-9]*) value=0 ;;
  esac
  printf '%s' "$value"
}

context="${QUAKEKIT_YOUTUBE_CONTEXT:-watch}"
metadata_file="${QUAKEKIT_YOUTUBE_METADATA_FILE:-}"
dry_run="$(bool_value "${QUAKEKIT_YOUTUBE_DRY_RUN:-true}")"

case "$context" in
  playlist|live|shorts) ;;
  *) context="watch" ;;
esac

title="${QUAKEKIT_YOUTUBE_TITLE:-QuakeKit Plugin Architecture Walkthrough}"
channel="${QUAKEKIT_YOUTUBE_CHANNEL:-QuakeKit Labs}"
state="${QUAKEKIT_YOUTUBE_STATE:-paused}"
position="${QUAKEKIT_YOUTUBE_POSITION_SECONDS:-83}"
duration="${QUAKEKIT_YOUTUBE_DURATION_SECONDS:-614}"
url="${QUAKEKIT_YOUTUBE_URL:-https://www.youtube.com/watch?v=offline-safe}"

if [ -n "$metadata_file" ] && [ -r "$metadata_file" ]; then
  first_line="$(sed -n '1p' "$metadata_file")"
  old_ifs=$IFS
  IFS='|'
  set -- $first_line
  IFS=$old_ifs
  title="${1:-$title}"
  channel="${2:-$channel}"
  state="${3:-$state}"
  position="${4:-$position}"
  duration="${5:-$duration}"
  url="${6:-$url}"
fi

position="$(seconds_value "$position")"
duration="$(seconds_value "$duration")"
case "$state" in
  playing) playing=true ;;
  *) state="paused"; playing=false ;;
esac

progress_label="$(awk -v p="$position" -v d="$duration" 'BEGIN { printf "%d:%02d / %d:%02d", int(p / 60), p % 60, int(d / 60), d % 60 }')"

printf '{"ok":true,"adapter":"youtube-media-companion.sh","mode":"offline-safe","connected":false,"dryRun":%s,"context":"%s","playing":%s,"media":{"title":"%s","channel":"%s","url":"%s","progressSeconds":%s,"durationSeconds":%s},"actions":[{"id":"youtube.playPause","enabled":true,"dryRun":%s,"providerCommand":"mediaKeyPlayPause"},{"id":"youtube.skipBack","enabled":true,"dryRun":%s,"seconds":10},{"id":"youtube.skipForward","enabled":true,"dryRun":%s,"seconds":10},{"id":"youtube.openURL","enabled":true,"dryRun":%s,"url":"%s"}],"rows":[{"title":"Context","value":"%s","detail":"browser media companion"},{"title":"Video","value":"%s","detail":"%s"},{"title":"Channel","value":"%s","detail":"YouTube metadata fixture"},{"title":"State","value":"%s","detail":"%s"},{"title":"URL","value":"configured","detail":"%s"}],"source":"youtube-media-companion.sh"}\n' \
  "$dry_run" "$(json_escape "$context")" "$playing" "$(json_escape "$title")" "$(json_escape "$channel")" "$(json_escape "$url")" "$position" "$duration" \
  "$dry_run" "$dry_run" "$dry_run" "$dry_run" "$(json_escape "$url")" "$(json_escape "$context")" "$(json_escape "$title")" "$(json_escape "$channel")" "$(json_escape "$channel")" "$(json_escape "$state")" "$(json_escape "$progress_label")" "$(json_escape "$url")"
