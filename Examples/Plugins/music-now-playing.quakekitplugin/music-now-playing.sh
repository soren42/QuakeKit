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

provider="${QUAKEKIT_MUSIC_PROVIDER:-spotify}"
device="${QUAKEKIT_MUSIC_DEVICE:-Studio Speakers}"
now_file="${QUAKEKIT_MUSIC_NOW_PLAYING_FILE:-}"
dry_run="$(bool_value "${QUAKEKIT_MUSIC_DRY_RUN:-true}")"
volume="$(seconds_value "${QUAKEKIT_MUSIC_VOLUME:-62}")"

case "$provider" in
  apple_music|youtube_music|tidal|suno|local) ;;
  *) provider="spotify" ;;
esac

title="${QUAKEKIT_MUSIC_TITLE:-Midnight City}"
artist="${QUAKEKIT_MUSIC_ARTIST:-M83}"
album="${QUAKEKIT_MUSIC_ALBUM:-Hurry Up We Are Dreaming}"
state="${QUAKEKIT_MUSIC_STATE:-playing}"
position="${QUAKEKIT_MUSIC_POSITION_SECONDS:-194}"
duration="${QUAKEKIT_MUSIC_DURATION_SECONDS:-243}"

if [ -n "$now_file" ] && [ -r "$now_file" ]; then
  first_line="$(sed -n '1p' "$now_file")"
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
fi

position="$(seconds_value "$position")"
duration="$(seconds_value "$duration")"
case "$state" in
  paused|stopped) playing=false ;;
  *) state="playing"; playing=true ;;
esac

progress_label="$(awk -v p="$position" -v d="$duration" 'BEGIN { printf "%d:%02d / %d:%02d", int(p / 60), p % 60, int(d / 60), d % 60 }')"
printf '{"ok":true,"adapter":"music-now-playing.sh","mode":"offline-safe","connected":false,"dryRun":%s,"provider":"%s","playing":%s,"track":{"title":"%s","artist":"%s","album":"%s","progressSeconds":%s,"durationSeconds":%s},"device":{"name":"%s","volume":%s},"actions":[{"id":"music.playPause","enabled":true,"dryRun":%s,"providerCommand":"playPause"},{"id":"music.next","enabled":true,"dryRun":%s,"providerCommand":"next"},{"id":"music.previous","enabled":true,"dryRun":%s,"providerCommand":"previous"}],"rows":[{"title":"Provider","value":"%s","detail":"offline-safe provider adapter"},{"title":"Track","value":"%s","detail":"%s"},{"title":"Album","value":"%s","detail":"%s"},{"title":"State","value":"%s","detail":"%s"},{"title":"Output","value":"%s","detail":"volume %s%%"}],"source":"music-now-playing.sh"}\n' \
  "$dry_run" "$(json_escape "$provider")" "$playing" "$(json_escape "$title")" "$(json_escape "$artist")" "$(json_escape "$album")" "$position" "$duration" "$(json_escape "$device")" "$volume" \
  "$dry_run" "$dry_run" "$dry_run" "$(json_escape "$provider")" "$(json_escape "$title")" "$(json_escape "$artist")" "$(json_escape "$album")" "$(json_escape "$provider")" "$(json_escape "$state")" "$(json_escape "$progress_label")" "$(json_escape "$device")" "$volume"
