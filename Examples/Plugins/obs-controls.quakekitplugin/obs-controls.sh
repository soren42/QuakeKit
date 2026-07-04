#!/bin/sh
set -eu
cat >/dev/null
url="${QUAKEKIT_OBS_WEBSOCKET_URL:-ws://127.0.0.1:4455}"
profile="${QUAKEKIT_OBS_PROFILE:-stream}"
printf '{"status":"stub","rows":[{"title":"Endpoint","value":"%s","detail":"OBS WebSocket target"},{"title":"Profile","value":"%s","detail":"scene controls ready"},{"title":"Stream","value":"Offline","detail":"toggle action stub"},{"title":"Recording","value":"Stopped","detail":"toggle action stub"}],"source":"obs-controls.sh"}\n' "$url" "$profile"
