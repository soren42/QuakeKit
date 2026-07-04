#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool_value() {
  case "${1:-}" in
    false|0|no|off) printf 'false' ;;
    *) printf 'true' ;;
  esac
}

guild="${QUAKEKIT_DISCORD_GUILD_ID:-example-guild}"
channel="${QUAKEKIT_DISCORD_STATUS_CHANNEL:-stream-room}"
presence="${QUAKEKIT_DISCORD_PRESENCE_MODE:-available}"
activity="${QUAKEKIT_DISCORD_ACTIVITY_TEMPLATE:-streaming}"
stream_title="${QUAKEKIT_DISCORD_STREAM_TITLE:-Working session}"
go_live_url="${QUAKEKIT_DISCORD_GO_LIVE_URL:-}"
mention_role="${QUAKEKIT_DISCORD_MENTION_ROLE:-@stream}"
dry_run="$(bool_value "${QUAKEKIT_DISCORD_DRY_RUN:-true}")"

case "$presence" in
  idle|do_not_disturb) ;;
  *) presence="available" ;;
esac
case "$activity" in
  coding)
    activity_title="Coding session"
    activity_detail="Workspace companion online"
    ;;
  meeting)
    activity_title="Meeting mode"
    activity_detail="Notifications muted"
    ;;
  offline)
    activity_title="Offline"
    activity_detail="No Discord calls will be made"
    ;;
  *)
    activity="streaming"
    activity_title="Streaming setup"
    activity_detail="OBS scenes and voice room ready"
    ;;
esac

if [ -n "${DISCORD_WEBHOOK_URL:-}" ]; then
  webhook_configured=true
else
  webhook_configured=false
fi

if [ -n "$go_live_url" ]; then
  announcement_detail="$mention_role $stream_title - $go_live_url"
else
  announcement_detail="$mention_role $stream_title"
fi

printf '{"ok":true,"adapter":"discord-companion.sh","mode":"offline-safe","connected":false,"dryRun":%s,"webhookConfigured":%s,"ack":{"posted":false,"presenceUpdated":false,"reason":"safe stub"},"guild":"%s","channel":"%s","presence":"%s","streamTitle":"%s","goLiveURL":"%s","mentionRole":"%s","activity":{"template":"%s","title":"%s","detail":"%s"},"onlineMembers":42,"voiceMembers":7,"mentions":1,"streamChecklist":[{"title":"Voice room","state":"ready"},{"title":"Announcement","state":"planned"},{"title":"Presence","state":"planned"}],"actions":[{"id":"discord.postStatus","enabled":true,"dryRun":%s,"target":"#%s"},{"id":"discord.setPresence","enabled":true,"dryRun":%s,"state":"%s"},{"id":"discord.openVoice","enabled":true,"dryRun":%s,"channel":"%s"},{"id":"discord.announceStream","enabled":true,"dryRun":%s,"target":"#%s","preview":"%s"},{"id":"discord.clearMentions","enabled":true,"dryRun":%s,"count":1}],"recentActivity":[{"user":"alex","event":"joined voice","ageMinutes":3},{"user":"sam","event":"posted status","ageMinutes":8},{"user":"riley","event":"mentioned project channel","ageMinutes":12}],"rows":[{"title":"Guild","value":"%s","detail":"channel #%s"},{"title":"Presence","value":"%s","detail":"%s"},{"title":"Stream","value":"%s","detail":"%s"},{"title":"Voice","value":"7 members","detail":"open voice action dry-run ready"},{"title":"Webhook","value":"%s","detail":"postStatus stays local unless configured"}],"source":"discord-companion.sh"}\n' \
  "$dry_run" "$webhook_configured" "$(json_escape "$guild")" "$(json_escape "$channel")" "$(json_escape "$presence")" "$(json_escape "$stream_title")" "$(json_escape "$go_live_url")" "$(json_escape "$mention_role")" "$(json_escape "$activity")" "$(json_escape "$activity_title")" "$(json_escape "$activity_detail")" \
  "$dry_run" "$(json_escape "$channel")" "$dry_run" "$(json_escape "$presence")" "$dry_run" "$(json_escape "$channel")" "$dry_run" "$(json_escape "$channel")" "$(json_escape "$announcement_detail")" "$dry_run" \
  "$(json_escape "$guild")" "$(json_escape "$channel")" "$(json_escape "$presence")" "$(json_escape "$activity_detail")" "$(json_escape "$stream_title")" "$(json_escape "$announcement_detail")" "$webhook_configured"
