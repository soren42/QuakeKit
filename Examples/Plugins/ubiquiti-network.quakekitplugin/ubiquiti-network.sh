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

url="${QUAKEKIT_UNIFI_CONTROLLER_URL:-https://unifi.local}"
site="${QUAKEKIT_UNIFI_SITE:-default}"
filter="${QUAKEKIT_UNIFI_CLIENT_FILTER:-all}"
security_mode="${QUAKEKIT_UNIFI_SECURITY_MODE:-home}"
camera_group="${QUAKEKIT_UNIFI_CAMERA_GROUP:-perimeter}"
dry_run="$(bool_value "${QUAKEKIT_UNIFI_DRY_RUN:-true}")"
case "$filter" in
  wired|wireless) ;;
  *) filter="all" ;;
esac
case "$security_mode" in
  away|night|privacy) ;;
  *) security_mode="home" ;;
esac
case "$camera_group" in
  interior|all) ;;
  *) camera_group="perimeter" ;;
esac

case "$filter" in
  wired) highlighted=11 ;;
  wireless) highlighted=17 ;;
  *) highlighted=28 ;;
esac

if [ "$security_mode" = "privacy" ]; then
  recording=false
  camera_alerts=0
else
  recording=true
  camera_alerts=2
fi

printf '{"ok":true,"adapter":"ubiquiti-network.sh","mode":"offline-safe","ack":{"commandSent":false,"reason":"safe stub"},"controllerURL":"%s","site":"%s","clientFilter":"%s","highlightedClients":%s,"securityMode":"%s","cameraGroup":"%s","dryRun":%s,"wanStatus":"online","uptimePercent":99.98,"clients":28,"wiredClients":11,"wirelessClients":17,"cameraAlerts":%s,"protectRecording":%s,"devices":[{"id":"udm-pro","name":"UDM Pro","type":"gateway","state":"online"},{"id":"u6-pro","name":"U6 Pro","type":"accessPoint","state":"online"},{"id":"switch-24","name":"Switch 24","type":"switch","state":"online"}],"cameras":[{"id":"driveway","name":"Driveway","state":"online","recording":%s,"lastMotionMinutes":4},{"id":"front-door","name":"Front Door","state":"online","recording":%s,"lastMotionMinutes":18},{"id":"studio","name":"Studio","state":"online","recording":%s,"lastMotionMinutes":0}],"actions":[{"id":"unifi.restartAccessPoint","enabled":true,"dryRun":%s,"endpoint":"/proxy/network/api/s/%s/cmd/devmgr","target":"u6-pro"},{"id":"unifi.blockClient","enabled":true,"dryRun":%s,"endpoint":"/proxy/network/api/s/%s/cmd/stamgr","target":"example-client"},{"id":"unifi.setProtectMode","enabled":true,"dryRun":%s,"mode":"%s"},{"id":"unifi.openCamera","enabled":true,"dryRun":%s,"camera":"driveway"}],"rows":[{"title":"WAN","value":"online","detail":"99.98%% uptime"},{"title":"Clients","value":"%s","detail":"filter %s"},{"title":"Protect","value":"%s","detail":"%s alerts in %s"},{"title":"Devices","value":"3 online","detail":"gateway, AP, switch"}],"source":"ubiquiti-network.sh"}\n' \
  "$(json_escape "$url")" "$(json_escape "$site")" "$(json_escape "$filter")" "$highlighted" "$(json_escape "$security_mode")" "$(json_escape "$camera_group")" "$dry_run" "$camera_alerts" "$recording" "$recording" "$recording" "$recording" \
  "$dry_run" "$(json_escape "$site")" "$dry_run" "$(json_escape "$site")" "$dry_run" "$(json_escape "$security_mode")" "$dry_run" "$highlighted" "$(json_escape "$filter")" "$(json_escape "$security_mode")" "$camera_alerts" "$(json_escape "$camera_group")"
