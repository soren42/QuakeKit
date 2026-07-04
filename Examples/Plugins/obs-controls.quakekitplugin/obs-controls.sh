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

url="${QUAKEKIT_OBS_WEBSOCKET_URL:-ws://127.0.0.1:4455}"
profile="${QUAKEKIT_OBS_PROFILE:-stream}"
scene_collection="${QUAKEKIT_OBS_SCENE_COLLECTION:-Default}"
default_scene="${QUAKEKIT_OBS_DEFAULT_SCENE:-Starting Soon}"
dry_run="$(bool_value "${QUAKEKIT_OBS_DRY_RUN:-true}")"

case "$profile" in
  record)
    current_scene="Capture"
    streaming=false
    recording=true
    ;;
  studio)
    current_scene="Program"
    streaming=false
    recording=false
    ;;
  *)
    profile="stream"
    current_scene="$default_scene"
    streaming=false
    recording=false
    ;;
esac

if [ "$recording" = true ]; then
  recording_label="Recording"
else
  recording_label="Stopped"
fi

printf '{"ok":true,"adapter":"obs-controls.sh","mode":"offline-safe","connected":false,"dryRun":%s,"websocketURL":"%s","profile":"%s","sceneCollection":"%s","currentScene":"%s","streaming":%s,"recording":%s,"droppedFrames":0,"previewScene":"Camera Check","programScene":"%s","actions":[{"id":"obs.toggleStream","enabled":true,"dryRun":%s,"requestType":"ToggleStream"},{"id":"obs.toggleRecord","enabled":true,"dryRun":%s,"requestType":"ToggleRecord"},{"id":"obs.setScene","enabled":true,"dryRun":%s,"requestType":"SetCurrentProgramScene","sceneName":"%s"}],"rows":[{"title":"Endpoint","value":"%s","detail":"local OBS websocket target"},{"title":"Profile","value":"%s","detail":"scene collection %s"},{"title":"Program","value":"%s","detail":"preview Camera Check"},{"title":"Stream","value":"Offline","detail":"toggle emits request plan in dry run"},{"title":"Recording","value":"%s","detail":"offline status from profile"}],"source":"obs-controls.sh"}\n' \
  "$dry_run" "$(json_escape "$url")" "$(json_escape "$profile")" "$(json_escape "$scene_collection")" "$(json_escape "$current_scene")" "$streaming" "$recording" "$(json_escape "$current_scene")" \
  "$dry_run" "$dry_run" "$dry_run" "$(json_escape "$default_scene")" "$(json_escape "$url")" "$(json_escape "$profile")" "$(json_escape "$scene_collection")" "$(json_escape "$current_scene")" "$(json_escape "$recording_label")"
