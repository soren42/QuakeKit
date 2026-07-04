#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_CLAUDE_MODEL:-claude-sonnet}"
mode="${QUAKEKIT_CLAUDE_MODE:-assistant}"
printf '{"status":"stub","rows":[{"title":"Provider","value":"Claude","detail":"Anthropic API boundary"},{"title":"Model","value":"%s","detail":"user-configured alias"},{"title":"Mode","value":"%s","detail":"no UI scraping or automation"},{"title":"Ready","value":"Yes","detail":"connect API key to enable"}],"source":"claude-harness.sh"}\n' "$model" "$mode"
