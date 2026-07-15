#!/bin/bash
# link-dev-app.sh — create and register a dev Vox.app bundle for vox:// links.
#
# Usage: ./scripts/link-dev-app.sh [--no-build] [--launch]
#
# Options:
#   --no-build  Reuse existing debug binaries.
#   --launch    Launch the dev bundle after registering it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEV_VERSION="$(sed -n 's/.*public static let current = "\(.*\)".*/\1/p' "$ROOT/swift/Sources/VoxCore/RuntimePaths.swift" | head -n 1)"

BOLD='\033[1m'; GREEN='\033[32m'; RESET='\033[0m'
say() { printf "  ${BOLD}→${RESET} %s\n" "$1"; }
ok() { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }

DO_BUILD=true
DO_LAUNCH=false

for arg in "$@"; do
  case "$arg" in
    --no-build) DO_BUILD=false ;;
    --launch) DO_LAUNCH=true ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

SCRATCH="$ROOT/apps/vox/.build-$(swift --version 2>&1 | shasum | cut -d ' ' -f 1)"
DEV_DIR="$ROOT/dist/dev"
BUNDLE="$DEV_DIR/Vox Dev.app"
APP_ICONSET="$ROOT/apps/vox/Vox/Assets.xcassets/AppIcon.appiconset"
APP_ICON="$BUNDLE/Contents/Resources/Vox.icns"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

stop_dev_app() {
  if ! pgrep -f "$BUNDLE/Contents/MacOS/Vox" >/dev/null 2>&1; then
    return
  fi

  say "stopping existing dev app"
  osascript -e 'tell application id "cc.voxd.app.dev" to quit' >/dev/null 2>&1 || true

  for _ in {1..20}; do
    if ! pgrep -f "$BUNDLE/Contents/MacOS/Vox" >/dev/null 2>&1; then
      ok "existing dev app stopped"
      return
    fi
    sleep 0.25
  done

  pkill -f "$BUNDLE/Contents/MacOS/Vox" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    if ! pgrep -f "$BUNDLE/Contents/MacOS/Vox" >/dev/null 2>&1; then
      ok "existing dev app stopped"
      return
    fi
    sleep 0.25
  done

  echo "failed to stop existing dev app" >&2
  exit 1
}

if $DO_BUILD; then
  say "building dev app and helper binaries"
  swift build --package-path "$ROOT/apps/vox" --scratch-path "$SCRATCH"
  swift build --package-path "$ROOT/swift" --product voxd --product voxttsd
fi

APP_BIN_DIR="$(swift build --package-path "$ROOT/apps/vox" --scratch-path "$SCRATCH" --show-bin-path)"
SWIFT_BIN_DIR="$(swift build --package-path "$ROOT/swift" --show-bin-path)"
APP_BIN="$APP_BIN_DIR/Vox"
VOXD_BIN="$SWIFT_BIN_DIR/voxd"
VOXTTS_BIN="$SWIFT_BIN_DIR/voxttsd"

[ -x "$APP_BIN" ] || { echo "missing app binary: $APP_BIN" >&2; exit 1; }
[ -x "$VOXD_BIN" ] || { echo "missing voxd binary: $VOXD_BIN" >&2; exit 1; }
[ -x "$VOXTTS_BIN" ] || { echo "missing voxttsd binary: $VOXTTS_BIN" >&2; exit 1; }

if $DO_LAUNCH; then
  stop_dev_app
fi

say "creating $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$APP_BIN" "$BUNDLE/Contents/MacOS/Vox"
cp "$VOXD_BIN" "$BUNDLE/Contents/Resources/voxd"
cp "$VOXTTS_BIN" "$BUNDLE/Contents/Resources/voxttsd"

if [ -d "$APP_ICONSET" ]; then
  say "installing app icon"
  ICONSET_TMP="$DEV_DIR/Vox.iconset"
  rm -rf "$ICONSET_TMP"
  mkdir -p "$ICONSET_TMP"
  cp "$APP_ICONSET"/icon_*.png "$ICONSET_TMP/"
  iconutil -c icns "$ICONSET_TMP" -o "$APP_ICON"
  rm -rf "$ICONSET_TMP"
fi

while IFS= read -r -d '' resource; do
  rm -rf "$BUNDLE/Contents/Resources/$(basename "$resource")"
  cp -R "$resource" "$BUNDLE/Contents/Resources/"
done < <(find "$APP_BIN_DIR" "$SWIFT_BIN_DIR" -maxdepth 1 -type d -name "*.bundle" -print0)

cat > "$BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Vox Dev</string>
    <key>CFBundleDisplayName</key>
    <string>Vox Dev</string>
    <key>CFBundleIdentifier</key>
    <string>cc.voxd.app.dev</string>
    <key>CFBundleVersion</key>
    <string>$DEV_VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$DEV_VERSION</string>
    <key>CFBundleExecutable</key>
    <string>Vox</string>
    <key>CFBundleIconFile</key>
    <string>Vox</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Vox uses the microphone for live transcription.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>cc.voxd.app.dev.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>vox</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

say "registering dev bundle as vox:// handler"
"$LSREGISTER" -f "$BUNDLE"
swift -e 'import Foundation; import CoreServices; let scheme = "vox" as NSString; let bundle = "cc.voxd.app.dev" as NSString; let status = LSSetDefaultHandlerForURLScheme(scheme, bundle); if status != 0 { Foundation.exit(Int32(status)) }'
ok "vox:// handler: cc.voxd.app.dev"

if $DO_LAUNCH; then
  say "launching dev bundle"
  open "$BUNDLE" --args --show-settings
fi

ok "vox:// is linked to $BUNDLE"
