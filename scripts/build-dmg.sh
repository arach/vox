#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP_DIR="$ROOT/app"
BUILD_DIR="$ROOT/dist"
APP_NAME="Vox.app"
DMG_NAME="Vox.dmg"
BUNDLE="$BUILD_DIR/$APP_NAME"
VERSION="0.1.0"

echo "==> Building release binary..."
cd "$APP_DIR"
swift build -c release 2>&1 | tail -3

echo "==> Creating app bundle..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# Copy binary
cp "$APP_DIR/.build/release/Vox" "$BUNDLE/Contents/MacOS/Vox"

# Copy voxd daemon binary if available
VOXD_PATH="$ROOT/swift/.build/release/voxd"
if [ -f "$VOXD_PATH" ]; then
    cp "$VOXD_PATH" "$BUNDLE/Contents/Resources/voxd"
    echo "    Bundled voxd daemon"
fi

# Copy icon
ICNS="$ROOT/app/Vox/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICNS" ]; then
    # Generate .icns from iconset
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"
    cp "$ICNS"/icon_*.png "$ICONSET_DIR/"
    iconutil -c icns "$ICONSET_DIR" -o "$BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

# Copy bundled resources from SPM build
RESOURCES="$APP_DIR/.build/release/Vox_Vox.bundle"
if [ -d "$RESOURCES" ]; then
    cp -R "$RESOURCES" "$BUNDLE/Contents/Resources/"
fi

# Info.plist
cat > "$BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Vox</string>
    <key>CFBundleDisplayName</key>
    <string>Vox</string>
    <key>CFBundleIdentifier</key>
    <string>dev.vox.app</string>
    <key>CFBundleVersion</key>
    <string>VOXVERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>VOXVERSION</string>
    <key>CFBundleExecutable</key>
    <string>Vox</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
            <string>dev.vox.app.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>vox</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Substitute version
sed -i '' "s/VOXVERSION/$VERSION/g" "$BUNDLE/Contents/Info.plist"

echo "==> App bundle created at $BUNDLE"

# Create DMG
echo "==> Creating DMG..."
DMG_STAGING=$(mktemp -d)
cp -R "$BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "Vox" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

rm -rf "$DMG_STAGING"

echo "==> Done: $BUILD_DIR/$DMG_NAME"
ls -lh "$BUILD_DIR/$DMG_NAME"
