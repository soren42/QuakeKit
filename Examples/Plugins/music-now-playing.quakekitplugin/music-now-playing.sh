#!/bin/sh
set -eu
cat >/dev/null
provider="${QUAKEKIT_MUSIC_PROVIDER:-spotify}"
printf '{"status":"stub","rows":[{"title":"Provider","value":"%s","detail":"OAuth bridge pending"},{"title":"Track","value":"Midnight City","detail":"M83"},{"title":"State","value":"Playing","detail":"3:14 / 4:03"},{"title":"Output","value":"Studio Speakers","detail":"volume 62%%"}],"source":"music-now-playing.sh"}\n' "$provider"
