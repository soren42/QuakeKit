#!/bin/sh
set -eu

REPO_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$REPO_DIR"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="${APP_NAME:-QuakeKit}"
BUILD_DIR="$REPO_DIR/.build"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

/usr/bin/swift build -c "$CONFIGURATION" --product quake-panel

TRIPLE_DIR="$(find "$BUILD_DIR" -maxdepth 1 -type d -name '*-apple-macosx' | sort | tail -n 1)"
PRODUCT_DIR="$TRIPLE_DIR/$CONFIGURATION"
BINARY="$PRODUCT_DIR/quake-panel"
RESOURCE_BUNDLE="$PRODUCT_DIR/QuakeKit_QuakePanelHost.bundle"

if [ ! -x "$BINARY" ]; then
  echo "Built quake-panel binary was not found at $BINARY" >&2
  exit 1
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY" "$MACOS_DIR/$APP_NAME"
if [ -d "$RESOURCE_BUNDLE" ]; then
  /usr/bin/ditto "$RESOURCE_BUNDLE" "$BUNDLE_DIR/QuakeKit_QuakePanelHost.bundle"
fi
/usr/bin/ditto "$REPO_DIR/Examples" "$RESOURCES_DIR/Examples"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.soren42.quakekit</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>QuakeKitReleaseChannel</key>
  <string>RC1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>QuakeKit uses microphone access only when you start voice capture or meeting-note recording.</string>
</dict>
</plist>
PLIST

if [ "${QUAKEKIT_CODESIGN:-0}" = "1" ] && command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null
fi

echo "$BUNDLE_DIR"
