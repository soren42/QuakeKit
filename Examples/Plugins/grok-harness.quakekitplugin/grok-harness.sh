#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_GROK_MODEL:-grok}"
mode="${QUAKEKIT_GROK_MODE:-assistant}"
printf '{"status":"stub","rows":[{"title":"Provider","value":"Grok","detail":"xAI API boundary"},{"title":"Model","value":"%s","detail":"user-configured alias"},{"title":"Mode","value":"%s","detail":"no consumer UI automation"},{"title":"Ready","value":"Yes","detail":"connect API key to enable"}],"source":"grok-harness.sh"}\n' "$model" "$mode"
