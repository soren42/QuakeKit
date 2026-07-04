#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPO_DIR"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [ ! -d "$DEVELOPER_DIR" ]; then
  echo "Xcode developer directory was not found: $DEVELOPER_DIR" >&2
  echo "Install Xcode or set DEVELOPER_DIR before validating QuakeKit." >&2
  exit 1
fi

echo "== swift build"
swift build

echo "== swift test"
swift test

echo "== quake-test"
swift run quake-test

echo "== plugin manifests"
for f in Examples/Plugins/*.json Examples/Plugins/*.quakekitplugin/manifest.json; do
  swift run quake-probe --validate-plugin "$f" >/dev/null || {
    echo "plugin invalid: $f" >&2
    exit 1
  }
done

echo "== theme manifests"
for f in Examples/Themes/*.quakekittheme/theme.json; do
  swift run quake-probe --validate-theme "$f" >/dev/null || {
    echo "theme invalid: $f" >&2
    exit 1
  }
done

echo "== adapter JSON"
for f in Examples/Plugins/*/*.sh Examples/Plugins/ai-agent.quakekitplugin/ai-agent-adapter Examples/Plugins/sports.quakekitplugin/sports-scores; do
  printf '{}\n' | "$f" | python3 -m json.tool >/dev/null || {
    echo "adapter emitted invalid JSON: $f" >&2
    exit 1
  }
done
if command -v php >/dev/null 2>&1; then
  printf '{}\n' | php Examples/Plugins/markets.quakekitplugin/markets.php | python3 -m json.tool >/dev/null
else
  echo "skip php adapter JSON check: php unavailable"
fi

echo "== app bundle"
./scripts/build-app-bundle.sh >/tmp/quakekit-bundle-path.txt
test -x .build/QuakeKit.app/Contents/MacOS/QuakeKit
test -d .build/QuakeKit.app/Contents/Resources/Examples/Plugins
test -d .build/QuakeKit.app/QuakeKit_QuakePanelHost.bundle
plutil -lint .build/QuakeKit.app/Contents/Info.plist >/dev/null

echo "QuakeKit release validation passed."
