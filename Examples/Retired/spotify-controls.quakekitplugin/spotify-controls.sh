#!/bin/sh
set -eu

request="$(cat)"
method="$(printf '%s' "$request" | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool_value() {
  case "${1:-}" in false|0|no|off) printf 'false' ;; *) printf 'true' ;; esac
}

source="${QUAKEKIT_SPOTIFY_SOURCE:-auto}"
file="${QUAKEKIT_SPOTIFY_METADATA_FILE:-}"
dry_run="$(bool_value "${QUAKEKIT_SPOTIFY_DRY_RUN:-true}")"
title="${QUAKEKIT_SPOTIFY_TITLE:-Midnight City}"
artist="${QUAKEKIT_SPOTIFY_ARTIST:-M83}"
album="${QUAKEKIT_SPOTIFY_ALBUM:-Hurry Up We Are Dreaming}"
state="${QUAKEKIT_SPOTIFY_STATE:-playing}"
position="${QUAKEKIT_SPOTIFY_POSITION_SECONDS:-194}"
duration="${QUAKEKIT_SPOTIFY_DURATION_SECONDS:-243}"

if { [ "$source" = "auto" ] || [ "$source" = "spotify_app" ]; } && command -v osascript >/dev/null 2>&1; then
  app_state="$(osascript -e 'if application "Spotify" is running then tell application "Spotify" to player state as string' 2>/dev/null || true)"
  app_title="$(osascript -e 'if application "Spotify" is running then tell application "Spotify" to name of current track' 2>/dev/null || true)"
  app_artist="$(osascript -e 'if application "Spotify" is running then tell application "Spotify" to artist of current track' 2>/dev/null || true)"
  app_album="$(osascript -e 'if application "Spotify" is running then tell application "Spotify" to album of current track' 2>/dev/null || true)"
  [ -n "$app_state" ] && state="$app_state" && source="spotify_app"
  [ -n "$app_title" ] && title="$app_title"
  [ -n "$app_artist" ] && artist="$app_artist"
  [ -n "$app_album" ] && album="$app_album"
fi

if [ -n "$file" ] && [ -r "$file" ]; then
  old_ifs=$IFS
  IFS='|'
  set -- $(sed -n '1p' "$file")
  IFS=$old_ifs
  title="${1:-$title}"; artist="${2:-$artist}"; album="${3:-$album}"; state="${4:-$state}"; position="${5:-$position}"; duration="${6:-$duration}"
  source="local_file"
fi

case "$state" in paused|stopped) playing=false ;; *) state="playing"; playing=true ;; esac

command_plan="refresh"
case "$method" in
  action.spotify.playPause) command_plan="playpause" ;;
  action.spotify.next) command_plan="next track" ;;
  action.spotify.previous) command_plan="previous track" ;;
esac

if [ "$dry_run" = false ] && [ "$command_plan" != "refresh" ] && command -v osascript >/dev/null 2>&1; then
  osascript -e "tell application \"Spotify\" to $command_plan" >/dev/null 2>&1 || true
fi

printf '{"ok":true,"adapter":"spotify-controls.sh","source":"%s","dryRun":%s,"connected":%s,"commandPlan":"%s","playing":%s,"track":{"title":"%s","artist":"%s","album":"%s","progressSeconds":%s,"durationSeconds":%s},"actions":[{"id":"spotify.playPause","enabled":true,"dryRun":%s},{"id":"spotify.next","enabled":true,"dryRun":%s},{"id":"spotify.previous","enabled":true,"dryRun":%s}],"rows":[{"title":"Track","value":"%s","detail":"%s"},{"title":"Album","value":"%s","detail":"%s"},{"title":"State","value":"%s","detail":"%ss / %ss"},{"title":"Controls","value":"%s","detail":"dry-run %s"}],"sourcePlugin":"spotify-controls.sh"}\n' \
  "$(json_escape "$source")" "$dry_run" "$playing" "$(json_escape "$command_plan")" "$playing" "$(json_escape "$title")" "$(json_escape "$artist")" "$(json_escape "$album")" "$position" "$duration" "$dry_run" "$dry_run" "$dry_run" \
  "$(json_escape "$title")" "$(json_escape "$artist")" "$(json_escape "$album")" "$(json_escape "$source")" "$(json_escape "$state")" "$position" "$duration" "$(json_escape "$command_plan")" "$dry_run"
