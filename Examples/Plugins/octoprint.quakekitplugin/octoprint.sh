#!/bin/sh
set -eu
cat >/dev/null
name="${QUAKEKIT_OCTOPRINT_NAME:-Voron}"
printf '{"status":"stub","rows":[{"title":"Printer","value":"%s","detail":"OctoPrint binding pending"},{"title":"Job","value":"Calibration Cube","detail":"42%% complete"},{"title":"Nozzle","value":"215 C","detail":"target 215 C"},{"title":"Bed","value":"60 C","detail":"target 60 C"}],"source":"octoprint.sh"}\n' "$name"
