#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

bool_value() {
  case "${1:-}" in true|1|yes|on) printf 'true' ;; *) printf 'false' ;; esac
}

file="${QUAKEKIT_NOTES_FILE:-}"
show_clipboard="$(bool_value "${QUAKEKIT_SHOW_CLIPBOARD:-false}")"
notes='[{"title":"Release","detail":"Run validate-release.sh"},{"title":"Hardware","detail":"Check cold wake and touch"},{"title":"Docs","detail":"Capture screenshots before v1"}]'
count=3
clipboard="disabled"

if [ -n "$file" ] && [ -r "$file" ]; then
  rows=""
  count=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    title="$(printf '%s' "$line" | cut -c 1-28)"
    item='{"title":"'"$(json_escape "$title")"'","detail":"'"$(json_escape "$line")"'"}'
    if [ -n "$rows" ]; then rows="$rows,$item"; else rows="$item"; fi
    count=$((count + 1))
    [ "$count" -lt 6 ] || break
  done < "$file"
  notes="[$rows]"
fi

if [ "$show_clipboard" = true ] && command -v pbpaste >/dev/null 2>&1; then
  clipboard="$(pbpaste 2>/dev/null | tr '\n' ' ' | cut -c 1-80 || true)"
  [ -n "$clipboard" ] || clipboard="empty"
fi

printf '{"ok":true,"adapter":"clipboard-notes.sh","noteCount":%s,"clipboardEnabled":%s,"clipboardPreview":"%s","notes":%s,"actions":[{"id":"notes.pinClipboard","enabled":%s,"dryRun":true}],"rows":[{"title":"Notes","value":"%s","detail":"items loaded"},{"title":"Clipboard","value":"%s","detail":"privacy gated by setting"},{"title":"Source","value":"%s","detail":"scratchpad fixture"}],"source":"clipboard-notes.sh"}\n' \
  "$count" "$show_clipboard" "$(json_escape "$clipboard")" "$notes" "$show_clipboard" "$count" "$(json_escape "$clipboard")" "$( [ -n "$file" ] && printf file || printf fixture )"
