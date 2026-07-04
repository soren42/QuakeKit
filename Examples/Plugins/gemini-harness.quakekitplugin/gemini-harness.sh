#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_GEMINI_MODEL:-gemini-pro}"
mode="${QUAKEKIT_GEMINI_MODE:-assistant}"
printf '{"status":"stub","rows":[{"title":"Provider","value":"Gemini","detail":"Google API boundary"},{"title":"Model","value":"%s","detail":"user-configured alias"},{"title":"Mode","value":"%s","detail":"official API only"},{"title":"Ready","value":"Yes","detail":"connect API key to enable"}],"source":"gemini-harness.sh"}\n' "$model" "$mode"
