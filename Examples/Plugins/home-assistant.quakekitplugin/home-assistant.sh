#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

url="${QUAKEKIT_HOME_ASSISTANT_URL:-http://homeassistant.local:8123}"
area="${QUAKEKIT_HOME_ASSISTANT_AREA:-Living Room}"
include_climate="${QUAKEKIT_HOME_ASSISTANT_INCLUDE_CLIMATE:-true}"
case "$include_climate" in
  false|0|no) include_climate=false ;;
  *) include_climate=true ;;
esac

printf '{"ok":true,"adapter":"home-assistant.sh","ack":{"serviceCalled":false,"reason":"safe stub"},"baseURL":"%s","area":"%s","lightsOn":3,"temperature":72.4,"humidity":45,"includeClimate":%s,"entities":[{"entity_id":"light.living_room","state":"on"},{"entity_id":"media_player.speakers","state":"idle"},{"entity_id":"climate.main_floor","state":"cool"}]}\n' \
  "$(json_escape "$url")" "$(json_escape "$area")" "$include_climate"
