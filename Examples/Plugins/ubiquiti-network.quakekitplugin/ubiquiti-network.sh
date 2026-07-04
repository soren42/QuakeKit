#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

url="${QUAKEKIT_UNIFI_CONTROLLER_URL:-https://unifi.local}"
site="${QUAKEKIT_UNIFI_SITE:-default}"
filter="${QUAKEKIT_UNIFI_CLIENT_FILTER:-all}"
case "$filter" in
  wired|wireless) ;;
  *) filter="all" ;;
esac

printf '{"ok":true,"adapter":"ubiquiti-network.sh","ack":{"commandSent":false,"reason":"safe stub"},"controllerURL":"%s","site":"%s","clientFilter":"%s","wanStatus":"online","uptimePercent":99.98,"clients":28,"wiredClients":11,"wirelessClients":17,"devices":[{"name":"UDM Pro","state":"online"},{"name":"U6 Pro","state":"online"},{"name":"Switch 24","state":"online"}]}\n' \
  "$(json_escape "$url")" "$(json_escape "$site")" "$(json_escape "$filter")"
