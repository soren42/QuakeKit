#!/bin/sh
set -eu

cat >/dev/null

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

provider="${QUAKEKIT_CAMERA_PROVIDER:-unifi}"
file="${QUAKEKIT_CAMERA_FILE:-}"
mode="${QUAKEKIT_CAMERA_ARM_MODE:-home}"
case "$provider" in ring|eufy|fixture) ;; *) provider="unifi" ;; esac
case "$mode" in away|disarmed) ;; *) mode="home" ;; esac

cameras='[{"name":"Front Door","state":"online","motion":true},{"name":"Driveway","state":"online","motion":false},{"name":"Back Yard","state":"online","motion":false}]'
count=3
motion=1

if [ -n "$file" ] && [ -r "$file" ]; then
  rows=""
  count=0
  motion=0
  while IFS='|' read -r name state moving; do
    [ -n "${name:-}" ] || continue
    [ -n "$state" ] || state="online"
    case "$moving" in true|1|yes|motion) moving=true; motion=$((motion + 1)) ;; *) moving=false ;; esac
    item='{"name":"'"$(json_escape "$name")"'","state":"'"$(json_escape "$state")"'","motion":'"$moving"'}'
    if [ -n "$rows" ]; then rows="$rows,$item"; else rows="$item"; fi
    count=$((count + 1))
  done < "$file"
  cameras="[$rows]"
fi

printf '{"ok":true,"adapter":"security-cameras.sh","provider":"%s","armMode":"%s","cameraCount":%s,"motionCount":%s,"cameras":%s,"actions":[{"id":"camera.armHome","enabled":true,"dryRun":true},{"id":"camera.armAway","enabled":true,"dryRun":true},{"id":"camera.openLive","enabled":true,"dryRun":true}],"rows":[{"title":"Provider","value":"%s","detail":"offline-safe camera bridge"},{"title":"Mode","value":"%s","detail":"security arm state"},{"title":"Cameras","value":"%s","detail":"%s with motion"},{"title":"Live View","value":"planned","detail":"provider-specific bridge pending"}],"source":"security-cameras.sh"}\n' \
  "$(json_escape "$provider")" "$(json_escape "$mode")" "$count" "$motion" "$cameras" "$(json_escape "$provider")" "$(json_escape "$mode")" "$count" "$motion"
