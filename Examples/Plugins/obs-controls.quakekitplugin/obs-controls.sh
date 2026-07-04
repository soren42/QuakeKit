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
scene_preset="${QUAKEKIT_OBS_SCENE_PRESET:-stream_deck}"
mic_source="${QUAKEKIT_OBS_MIC_SOURCE:-Mic/Aux}"
dry_run="$(bool_value "${QUAKEKIT_OBS_DRY_RUN:-true}")"
case "$scene_preset" in
  podcast|screen_share|recording) ;;
  *) scene_preset="stream_deck" ;;
esac

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

case "$scene_preset" in
  podcast)
    scene_buttons='{"title":"Host Cam","scene":"Host Cam","icon":"person.crop.square"},{"title":"Guest","scene":"Guest Split","icon":"person.2.fill"},{"title":"Break","scene":"Intermission","icon":"pause.circle.fill"},{"title":"Outro","scene":"Thanks","icon":"rectangle.portrait.and.arrow.right"}'
    ;;
  screen_share)
    scene_buttons='{"title":"Desktop","scene":"Desktop","icon":"display"},{"title":"Code","scene":"Code Review","icon":"chevron.left.forwardslash.chevron.right"},{"title":"Camera","scene":"Camera Check","icon":"video.fill"},{"title":"BRB","scene":"Be Right Back","icon":"pause.circle.fill"}'
    ;;
  recording)
    scene_buttons='{"title":"Capture","scene":"Capture","icon":"record.circle"},{"title":"Camera","scene":"Camera Check","icon":"video.fill"},{"title":"Slate","scene":"Slate","icon":"text.rectangle"},{"title":"End Card","scene":"End Card","icon":"flag.checkered"}'
    ;;
  *)
    scene_buttons='{"title":"Start","scene":"Starting Soon","icon":"play.rectangle.fill"},{"title":"Live","scene":"Main Camera","icon":"dot.radiowaves.left.and.right"},{"title":"Screen","scene":"Screen Share","icon":"display"},{"title":"Break","scene":"Be Right Back","icon":"pause.circle.fill"}'
    ;;
esac

if [ "$recording" = true ]; then
  recording_label="Recording"
else
  recording_label="Stopped"
fi

printf '{"ok":true,"adapter":"obs-controls.sh","mode":"offline-safe","connected":false,"dryRun":%s,"websocketURL":"%s","profile":"%s","sceneCollection":"%s","scenePreset":"%s","micSource":"%s","micMuted":false,"currentScene":"%s","streaming":%s,"recording":%s,"droppedFrames":0,"previewScene":"Camera Check","programScene":"%s","buttons":[%s],"actions":[{"id":"obs.toggleStream","enabled":true,"dryRun":%s,"requestType":"ToggleStream"},{"id":"obs.toggleRecord","enabled":true,"dryRun":%s,"requestType":"ToggleRecord"},{"id":"obs.toggleMute","enabled":true,"dryRun":%s,"requestType":"ToggleInputMute","sourceName":"%s"},{"id":"obs.marker","enabled":true,"dryRun":%s,"requestType":"CreateRecordChapter","label":"QuakeKit marker"},{"id":"obs.setScene","enabled":true,"dryRun":%s,"requestType":"SetCurrentProgramScene","sceneName":"%s"}],"rows":[{"title":"Endpoint","value":"%s","detail":"local OBS websocket target"},{"title":"Profile","value":"%s","detail":"scene collection %s"},{"title":"Program","value":"%s","detail":"preview Camera Check"},{"title":"Deck","value":"%s","detail":"4 planned scene buttons"},{"title":"Mic","value":"live","detail":"source %s"},{"title":"Recording","value":"%s","detail":"offline status from profile"}],"source":"obs-controls.sh"}\n' \
  "$dry_run" "$(json_escape "$url")" "$(json_escape "$profile")" "$(json_escape "$scene_collection")" "$(json_escape "$scene_preset")" "$(json_escape "$mic_source")" "$(json_escape "$current_scene")" "$streaming" "$recording" "$(json_escape "$current_scene")" "$scene_buttons" \
  "$dry_run" "$dry_run" "$dry_run" "$(json_escape "$mic_source")" "$dry_run" "$dry_run" "$(json_escape "$default_scene")" \
  "$(json_escape "$url")" "$(json_escape "$profile")" "$(json_escape "$scene_collection")" "$(json_escape "$current_scene")" "$(json_escape "$scene_preset")" "$(json_escape "$mic_source")" "$(json_escape "$recording_label")"
