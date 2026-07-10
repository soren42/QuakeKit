#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPO_DIR"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [ ! -d "$DEVELOPER_DIR" ]; then
  echo "Xcode developer directory was not found: $DEVELOPER_DIR" >&2
  echo "Install Xcode or set DEVELOPER_DIR before launching QuakeKit." >&2
  exit 1
fi

"$REPO_DIR/scripts/build-app-bundle.sh" >/dev/null
exec /usr/bin/open -n "$REPO_DIR/.build/QuakeKit.app" --args "$@"
