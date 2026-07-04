#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_DEEPSEEK_MODEL:-deepseek-chat}"
mode="${QUAKEKIT_DEEPSEEK_MODE:-assistant}"
printf '{"status":"stub","rows":[{"title":"Provider","value":"DeepSeek","detail":"DeepSeek API boundary"},{"title":"Model","value":"%s","detail":"user-configured alias"},{"title":"Mode","value":"%s","detail":"official API only"},{"title":"Ready","value":"Yes","detail":"connect API key to enable"}],"source":"deepseek-harness.sh"}\n' "$model" "$mode"
