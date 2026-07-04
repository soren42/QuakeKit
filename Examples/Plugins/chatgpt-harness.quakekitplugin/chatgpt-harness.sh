#!/bin/sh
set -eu
cat >/dev/null
model="${QUAKEKIT_OPENAI_MODEL:-gpt-4.1}"
mode="${QUAKEKIT_OPENAI_MODE:-assistant}"
printf '{"status":"stub","rows":[{"title":"Provider","value":"ChatGPT","detail":"OpenAI API boundary"},{"title":"Model","value":"%s","detail":"official API only"},{"title":"Mode","value":"%s","detail":"voice/meeting ready"},{"title":"Ready","value":"Yes","detail":"connect API key to enable"}],"source":"chatgpt-harness.sh"}\n' "$model" "$mode"
