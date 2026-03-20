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

# Signing
SIGN_IDENTITY="Developer ID Application: Arach Tchoupani (2U83JFPW66)"
TEAM_ID="2U83JFPW66"
NOTARY_PROFILE="notarytool"

echo "==> Building release binary..."
cd "$APP_DIR"
swift build -c release 2>&1 | tail -3

echo "==> Building voxd release binary..."
cd "$ROOT/swift"
swift build -c release --product voxd 2>&1 | tail -3

echo "==> Creating app bundle..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# Copy binary
cp "$APP_DIR/.build/release/Vox" "$BUNDLE/Contents/MacOS/Vox"

# Copy voxd daemon binary
VOXD_PATH="$ROOT/swift/.build/release/voxd"
if [ -f "$VOXD_PATH" ]; then
    cp "$VOXD_PATH" "$BUNDLE/Contents/Resources/voxd"
    echo "    Bundled voxd daemon"
fi

# Generate .icns from iconset
ICNS="$ROOT/app/Vox/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICNS" ]; then
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

# Entitlements
cat > "$BUILD_DIR/Vox.entitlements" << 'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
ENT

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

sed -i '' "s/VOXVERSION/$VERSION/g" "$BUNDLE/Contents/Info.plist"

echo "==> App bundle created at $BUNDLE"

# ── Codesign ──────────────────────────────────────────────
echo "==> Signing..."

# Sign voxd helper first (inside-out signing)
if [ -f "$BUNDLE/Contents/Resources/voxd" ]; then
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$BUNDLE/Contents/Resources/voxd"
    echo "    Signed voxd"
fi

# Sign the main app bundle
codesign --force --options runtime --timestamp \
    --entitlements "$BUILD_DIR/Vox.entitlements" \
    --sign "$SIGN_IDENTITY" \
    "$BUNDLE"

echo "    Signed Vox.app"

# Verify
codesign --verify --deep --strict --verbose=2 "$BUNDLE" 2>&1 | tail -3

# ── Create DMG ────────────────────────────────────────────
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

# Sign the DMG itself
codesign --force --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$BUILD_DIR/$DMG_NAME"

echo "    Signed Vox.dmg"

# ── Notarize ──────────────────────────────────────────────
echo "==> Submitting for notarization..."
xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$BUILD_DIR/$DMG_NAME"

# ── Done ──────────────────────────────────────────────────
echo ""
echo "==> Done: $BUILD_DIR/$DMG_NAME"
ls -lh "$BUILD_DIR/$DMG_NAME"
spctl --assess --type open --context context:primary-signature -v "$BUILD_DIR/$DMG_NAME" 2>&1 || true
