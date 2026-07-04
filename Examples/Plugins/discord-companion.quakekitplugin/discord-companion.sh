#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

guild="${QUAKEKIT_DISCORD_GUILD_ID:-example-guild}"
channel="${QUAKEKIT_DISCORD_STATUS_CHANNEL:-stream-room}"
presence="${QUAKEKIT_DISCORD_PRESENCE_MODE:-available}"

case "$presence" in
  idle|do_not_disturb) ;;
  *) presence="available" ;;
esac

printf '{"ok":true,"adapter":"discord-companion.sh","ack":{"posted":false,"reason":"safe stub"},"guild":"%s","channel":"%s","presence":"%s","onlineMembers":42,"voiceMembers":7,"recentActivity":[{"user":"alex","event":"joined voice"},{"user":"sam","event":"posted status"}]}\n' \
  "$(json_escape "$guild")" "$(json_escape "$channel")" "$(json_escape "$presence")"
