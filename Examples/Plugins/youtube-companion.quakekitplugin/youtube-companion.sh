#!/bin/sh
set -eu

request="$(cat)"
method="$(printf '%s' "$request" | sed -n 's/.*"method"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool_value() {
  case "${1:-}" in false|0|no|off) printf 'false' ;; *) printf 'true' ;; esac
}

browser="${QUAKEKIT_YOUTUBE_BROWSER:-auto}"
title="${QUAKEKIT_YOUTUBE_TITLE:-YouTube video}"
url="${QUAKEKIT_YOUTUBE_URL:-https://youtube.com/watch?v=example}"
dry_run="$(bool_value "${QUAKEKIT_YOUTUBE_DRY_RUN:-true}")"

detect_browser() {
  for candidate in "Google Chrome" "Arc" "Safari" "Microsoft Edge"; do
    osascript -e "if application \"$candidate\" is running then return \"$candidate\"" 2>/dev/null || true
  done | sed -n '1p'
}

if [ "$browser" = "auto" ] && command -v osascript >/dev/null 2>&1; then
  detected="$(detect_browser)"
  [ -n "$detected" ] && browser="$detected"
fi
[ "$browser" != "auto" ] || browser="fixture"

if command -v osascript >/dev/null 2>&1; then
  case "$browser" in
    Safari)
      detected_title="$(osascript -e 'tell application "Safari" to if exists front document then name of front document else ""' 2>/dev/null || true)"
      detected_url="$(osascript -e 'tell application "Safari" to if exists front document then URL of front document else ""' 2>/dev/null || true)"
      ;;
    "Google Chrome"|"Arc"|"Microsoft Edge")
      detected_title="$(osascript -e "tell application \"$browser\" to if exists active tab of front window then title of active tab of front window else \"\"" 2>/dev/null || true)"
      detected_url="$(osascript -e "tell application \"$browser\" to if exists active tab of front window then URL of active tab of front window else \"\"" 2>/dev/null || true)"
      ;;
    *) detected_title=""; detected_url="" ;;
  esac
  [ -n "$detected_title" ] && title="$detected_title"
  [ -n "$detected_url" ] && url="$detected_url"
fi

case "$method" in
  action.youtube.playPause) key="Space" ;;
  action.youtube.seekBack) key="J" ;;
  action.youtube.seekForward) key="L" ;;
  action.youtube.toggleCaptions) key="C" ;;
  *) key="Refresh" ;;
esac

case "$url" in *youtube.com*|*youtu.be*) is_youtube=true ;; *) is_youtube=false ;; esac

printf '{"ok":true,"adapter":"youtube-companion.sh","browser":"%s","isYouTube":%s,"dryRun":%s,"title":"%s","url":"%s","commandKey":"%s","actions":[{"id":"youtube.playPause","key":"Space","dryRun":%s},{"id":"youtube.seekBack","key":"J","dryRun":%s},{"id":"youtube.seekForward","key":"L","dryRun":%s},{"id":"youtube.toggleCaptions","key":"C","dryRun":%s}],"rows":[{"title":"Video","value":"%s","detail":"%s"},{"title":"Browser","value":"%s","detail":"YouTube tab %s"},{"title":"Control","value":"%s","detail":"keyboard plan, dry-run %s"}],"source":"youtube-companion.sh"}\n' \
  "$(json_escape "$browser")" "$is_youtube" "$dry_run" "$(json_escape "$title")" "$(json_escape "$url")" "$(json_escape "$key")" "$dry_run" "$dry_run" "$dry_run" "$dry_run" "$(json_escape "$title")" "$(json_escape "$url")" "$(json_escape "$browser")" "$is_youtube" "$(json_escape "$key")" "$dry_run"
