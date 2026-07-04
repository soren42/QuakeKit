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

url="${QUAKEKIT_HOME_ASSISTANT_URL:-http://homeassistant.local:8123}"
area="${QUAKEKIT_HOME_ASSISTANT_AREA:-Living Room}"
include_climate="${QUAKEKIT_HOME_ASSISTANT_INCLUDE_CLIMATE:-true}"
scene_profile="${QUAKEKIT_HOME_ASSISTANT_SCENE_PROFILE:-evening}"
favorite_scene="${QUAKEKIT_HOME_ASSISTANT_FAVORITE_SCENE:-scene.living_room_evening}"
security_mode="${QUAKEKIT_HOME_ASSISTANT_SECURITY_MODE:-home}"
dry_run="$(bool_value "${QUAKEKIT_HOME_ASSISTANT_DRY_RUN:-true}")"
case "$include_climate" in
  false|0|no) include_climate=false ;;
  *) include_climate=true ;;
esac
case "$scene_profile" in
  morning|workday|away) ;;
  *) scene_profile="evening" ;;
esac
case "$security_mode" in
  disarmed|away|night) ;;
  *) security_mode="home" ;;
esac

case "$area" in
  Kitchen)
    lights_on=2
    temp=71.8
    humidity=42
    primary_light="light.kitchen_island"
    media="media_player.kitchen_display"
    ;;
  Office)
    lights_on=1
    temp=70.9
    humidity=40
    primary_light="light.office_desk"
    media="media_player.office_speakers"
    ;;
  Garage)
    lights_on=0
    temp=66.1
    humidity=50
    primary_light="light.garage"
    media="cover.garage_door"
    ;;
  *)
    area="Living Room"
    lights_on=3
    temp=72.4
    humidity=45
    primary_light="light.living_room"
    media="media_player.speakers"
    ;;
esac

printf '{"ok":true,"adapter":"home-assistant.sh","mode":"offline-safe","ack":{"serviceCalled":false,"reason":"dry run fixture"},"baseURL":"%s","area":"%s","lightsOn":%s,"temperature":%s,"humidity":%s,"includeClimate":%s,"sceneProfile":"%s","favoriteScene":"%s","securityMode":"%s","dryRun":%s,"entities":[{"entity_id":"%s","name":"Primary Light","state":"on","domain":"light"},{"entity_id":"%s","name":"Room Media","state":"idle","domain":"media_player"},{"entity_id":"climate.main_floor","name":"Main Floor","state":"cool","domain":"climate"},{"entity_id":"alarm_control_panel.home","name":"Home Alarm","state":"armed_%s","domain":"alarm_control_panel"}],"scenes":[{"id":"scene.morning","title":"Morning","enabled":true},{"id":"scene.workday","title":"Workday Focus","enabled":true},{"id":"scene.evening","title":"Evening","enabled":true},{"id":"scene.away","title":"Away","enabled":true}],"actions":[{"id":"homeassistant.toggleEntity","enabled":true,"dryRun":%s,"service":"homeassistant.toggle","target":"%s"},{"id":"homeassistant.runScene","enabled":true,"dryRun":%s,"service":"scene.turn_on","target":"%s"},{"id":"homeassistant.setClimate","enabled":%s,"dryRun":%s,"service":"climate.set_temperature","target":"climate.main_floor"},{"id":"homeassistant.armSecurity","enabled":true,"dryRun":%s,"service":"alarm_control_panel.alarm_arm_%s","target":"alarm_control_panel.home"}],"rows":[{"title":"Area","value":"%s","detail":"%s lights on"},{"title":"Scene","value":"%s","detail":"favorite %s"},{"title":"Climate","value":"%s F","detail":"humidity %s%%"},{"title":"Security","value":"%s","detail":"service calls are planned locally"}],"source":"home-assistant.sh"}\n' \
  "$(json_escape "$url")" "$(json_escape "$area")" "$lights_on" "$temp" "$humidity" "$include_climate" "$(json_escape "$scene_profile")" "$(json_escape "$favorite_scene")" "$(json_escape "$security_mode")" "$dry_run" \
  "$(json_escape "$primary_light")" "$(json_escape "$media")" "$(json_escape "$security_mode")" "$dry_run" "$(json_escape "$primary_light")" "$dry_run" "$(json_escape "$favorite_scene")" "$include_climate" "$dry_run" "$dry_run" "$(json_escape "$security_mode")" \
  "$(json_escape "$area")" "$lights_on" "$(json_escape "$scene_profile")" "$(json_escape "$favorite_scene")" "$temp" "$humidity" "$(json_escape "$security_mode")"
