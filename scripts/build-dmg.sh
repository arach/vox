#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP_DIR="$ROOT/apps/vox"
BUILD_DIR="$ROOT/dist"
APP_NAME="Vox.app"
DMG_NAME="Vox.dmg"
BUNDLE="$BUILD_DIR/$APP_NAME"
APP_BUILD_LOG="$(mktemp -t vox-app-build.XXXXXX.log)"
VOXD_BUILD_LOG="$(mktemp -t vox-voxd-build.XXXXXX.log)"
DEFAULT_VERSION="$(sed -n 's/  "version": "\(.*\)",/\1/p' "$ROOT/packages/cli/package.json" | head -n 1)"
VERSION="${VOX_VERSION:-$DEFAULT_VERSION}"
SWIFT_VERSION="$(sed -n 's/.*public static let current = "\(.*\)".*/\1/p' "$ROOT/swift/Sources/VoxCore/RuntimePaths.swift" | head -n 1)"

if [ "$VERSION" != "$SWIFT_VERSION" ]; then
    echo "Version mismatch: package/tag version is $VERSION but VoxVersion.current is $SWIFT_VERSION." >&2
    exit 1
fi

# Signing and notarization are optional for local/dev builds, but release automation
# should provide them so the published DMG is ready for Gatekeeper.
SIGN_IDENTITY="${VOX_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${VOX_NOTARY_PROFILE:-}"
REQUIRE_SIGNED_RELEASE="${VOX_REQUIRE_SIGNED_RELEASE:-}"

if [ -n "$REQUIRE_SIGNED_RELEASE" ]; then
    if [ -z "$SIGN_IDENTITY" ] || [ -z "$NOTARY_PROFILE" ]; then
        echo "Signed release builds require VOX_SIGN_IDENTITY and VOX_NOTARY_PROFILE." >&2
        exit 1
    fi
fi

echo "==> Building release binary..."
cd "$APP_DIR"
swift build -c release 2>&1 | tee "$APP_BUILD_LOG"

echo "==> Building voxd release binary..."
cd "$ROOT/swift"
swift build -c release --product voxd 2>&1 | tee "$VOXD_BUILD_LOG"
swift build -c release --product voxttsd 2>&1 | tee -a "$VOXD_BUILD_LOG"

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

VOXTTS_PATH="$ROOT/swift/.build/release/voxttsd"
if [ -f "$VOXTTS_PATH" ]; then
    cp "$VOXTTS_PATH" "$BUNDLE/Contents/Resources/voxttsd"
    echo "    Bundled voxttsd daemon"
fi

# Generate .icns from iconset
ICNS="$ROOT/apps/vox/Vox/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICNS" ]; then
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"
    cp "$ICNS"/icon_*.png "$ICONSET_DIR/"
    iconutil -c icns "$ICONSET_DIR" -o "$BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

# Copy bundled resources from SPM builds. VoxEngine's bundle contains the
# built-in MLX provider script used by the packaged daemon.
while IFS= read -r -d '' RESOURCES; do
    rm -rf "$BUNDLE/Contents/Resources/$(basename "$RESOURCES")"
    cp -R "$RESOURCES" "$BUNDLE/Contents/Resources/"
    echo "    Bundled $(basename "$RESOURCES")"
done < <(find "$APP_DIR/.build/release/" "$ROOT/swift/.build/release/" \
    -maxdepth 1 \
    -type d \
    -name "*.bundle" \
    -print0)

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
    <string>cc.voxd.app</string>
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
            <string>cc.voxd.app.url</string>
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
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing..."

    # Sign voxd helper first (inside-out signing)
    if [ -f "$BUNDLE/Contents/Resources/voxd" ]; then
        codesign --force --options runtime --timestamp \
            --sign "$SIGN_IDENTITY" \
            "$BUNDLE/Contents/Resources/voxd"
        echo "    Signed voxd"
    fi

    if [ -f "$BUNDLE/Contents/Resources/voxttsd" ]; then
        codesign --force --options runtime --timestamp \
            --sign "$SIGN_IDENTITY" \
            "$BUNDLE/Contents/Resources/voxttsd"
        echo "    Signed voxttsd"
    fi

    # Sign the main app bundle
    codesign --force --options runtime --timestamp \
        --entitlements "$BUILD_DIR/Vox.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$BUNDLE"

    echo "    Signed Vox.app"

    # Verify
    codesign --verify --deep --strict --verbose=2 "$BUNDLE" 2>&1 | tail -3
else
    echo "==> Skipping codesign (VOX_SIGN_IDENTITY not set)"
fi

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

if [ -n "$SIGN_IDENTITY" ]; then
    # Sign the DMG itself
    codesign --force --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$BUILD_DIR/$DMG_NAME"

    echo "    Signed Vox.dmg"
else
    echo "==> Skipping DMG codesign (VOX_SIGN_IDENTITY not set)"
fi

# ── Notarize ──────────────────────────────────────────────
if [ -n "$SIGN_IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$BUILD_DIR/$DMG_NAME"
else
    echo "==> Skipping notarization (VOX_SIGN_IDENTITY or VOX_NOTARY_PROFILE not set)"
fi

# ── Done ──────────────────────────────────────────────────
echo ""
echo "==> Done: $BUILD_DIR/$DMG_NAME"
ls -lh "$BUILD_DIR/$DMG_NAME"
if [ -n "$REQUIRE_SIGNED_RELEASE" ]; then
    spctl --assess --type open --context context:primary-signature -v "$BUILD_DIR/$DMG_NAME" 2>&1
else
    spctl --assess --type open --context context:primary-signature -v "$BUILD_DIR/$DMG_NAME" 2>&1 || true
fi
