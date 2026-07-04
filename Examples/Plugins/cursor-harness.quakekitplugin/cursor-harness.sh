#!/bin/sh
set -eu
cat >/dev/null
workspace="${QUAKEKIT_CURSOR_WORKSPACE:-~/Code}"
mode="${QUAKEKIT_CURSOR_MODE:-status}"
printf '{"status":"stub","rows":[{"title":"Provider","value":"Cursor","detail":"local companion boundary"},{"title":"Workspace","value":"%s","detail":"read-only status by default"},{"title":"Mode","value":"%s","detail":"no editor UI scraping"},{"title":"Ready","value":"Yes","detail":"future CLI/deeplink integration"}],"source":"cursor-harness.sh"}\n' "$workspace" "$mode"
