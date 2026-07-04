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

number_value() {
  value="${1:-0}"
  case "$value" in
    ''|*[!0-9]*) value=0 ;;
  esac
  printf '%s' "$value"
}

track_file="${QUAKEKIT_SPOTIFY_TRACK_FILE:-}"
dry_run="$(bool_value "${QUAKEKIT_SPOTIFY_DRY_RUN:-true}")"

title="${QUAKEKIT_SPOTIFY_TITLE:-Midnight City}"
artist="${QUAKEKIT_SPOTIFY_ARTIST:-M83}"
album="${QUAKEKIT_SPOTIFY_ALBUM:-Hurry Up We Are Dreaming}"
state="${QUAKEKIT_SPOTIFY_STATE:-playing}"
position="${QUAKEKIT_SPOTIFY_POSITION_SECONDS:-194}"
duration="${QUAKEKIT_SPOTIFY_DURATION_SECONDS:-243}"
device="${QUAKEKIT_SPOTIFY_DEVICE:-Studio Speakers}"
volume="${QUAKEKIT_SPOTIFY_VOLUME:-62}"

if [ -n "$track_file" ] && [ -r "$track_file" ]; then
  first_line="$(sed -n '1p' "$track_file")"
  old_ifs=$IFS
  IFS='|'
  set -- $first_line
  IFS=$old_ifs
  title="${1:-$title}"
  artist="${2:-$artist}"
  album="${3:-$album}"
  state="${4:-$state}"
  position="${5:-$position}"
  duration="${6:-$duration}"
  device="${7:-$device}"
  volume="${8:-$volume}"
fi

position="$(number_value "$position")"
duration="$(number_value "$duration")"
volume="$(number_value "$volume")"
if [ "$volume" -gt 100 ]; then volume=100; fi
case "$state" in
  paused|stopped) playing=false ;;
  *) state="playing"; playing=true ;;
esac

progress_label="$(awk -v p="$position" -v d="$duration" 'BEGIN { printf "%d:%02d / %d:%02d", int(p / 60), p % 60, int(d / 60), d % 60 }')"

printf '{"ok":true,"adapter":"spotify-current-track.sh","mode":"offline-safe","connected":false,"dryRun":%s,"provider":"spotify","playing":%s,"track":{"title":"%s","artist":"%s","album":"%s","progressSeconds":%s,"durationSeconds":%s},"device":{"name":"%s","volume":%s},"actions":[{"id":"spotify.playPause","enabled":true,"dryRun":%s,"endpoint":"PUT /v1/me/player/play|pause"},{"id":"spotify.next","enabled":true,"dryRun":%s,"endpoint":"POST /v1/me/player/next"},{"id":"spotify.previous","enabled":true,"dryRun":%s,"endpoint":"POST /v1/me/player/previous"},{"id":"spotify.setVolume","enabled":true,"dryRun":%s,"endpoint":"PUT /v1/me/player/volume","volume":%s}],"rows":[{"title":"Track","value":"%s","detail":"%s"},{"title":"Album","value":"%s","detail":"Spotify current playback"},{"title":"State","value":"%s","detail":"%s"},{"title":"Output","value":"%s","detail":"volume %s%%"},{"title":"API","value":"offline-safe","detail":"set SPOTIFY_ACCESS_TOKEN for future live bridge"}],"source":"spotify-current-track.sh"}\n' \
  "$dry_run" "$playing" "$(json_escape "$title")" "$(json_escape "$artist")" "$(json_escape "$album")" "$position" "$duration" "$(json_escape "$device")" "$volume" \
  "$dry_run" "$dry_run" "$dry_run" "$dry_run" "$volume" "$(json_escape "$title")" "$(json_escape "$artist")" "$(json_escape "$album")" "$(json_escape "$state")" "$(json_escape "$progress_label")" "$(json_escape "$device")" "$volume"
