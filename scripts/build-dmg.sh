#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
DIST_DIR="$PROJECT_DIR/dist"
DMG_NAME="VoiceStudio-${VERSION}-macOS.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
TMP_DIR="$(mktemp -d)"
STAGE_DIR="$TMP_DIR/dmg-stage"
APP_BUNDLE="$STAGE_DIR/VoiceStudio.app"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$DIST_DIR" "$STAGE_DIR"

echo "==> Building VoiceStudio v${VERSION} (Release Universal Binary)..."
cd "$PROJECT_DIR"
if swift build -c release --arch arm64 --arch x86_64; then
    BIN_PATH="$PROJECT_DIR/.build/apple/Products/Release/VoiceStudio"
    echo "    Built Universal binary (arm64 + x86_64)"
else
    echo "    Universal toolchain unavailable; falling back to native Release build..."
    swift build -c release
    BIN_PATH="$(swift build -c release --show-bin-path)/VoiceStudio"
fi

echo "==> Generating AppIcon.icns..."
ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
swift "$PROJECT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$TMP_DIR/AppIcon.icns"

echo "==> Packaging VoiceStudio.app..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/VoiceStudio"
chmod +x "$APP_BUNDLE/Contents/MacOS/VoiceStudio"
cp "$TMP_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VoiceStudio</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.saadmahmood.voicestudio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>VoiceStudio</string>
    <key>CFBundleDisplayName</key>
    <string>VoiceStudio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceStudio processes your microphone audio in real time to deliver crisp, studio-quality voice to Microsoft Teams via BlackHole 2ch.</string>
</dict>
</plist>
PLIST

cat > "$TMP_DIR/entitlements.plist" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
ENT

codesign --force --deep --entitlements "$TMP_DIR/entitlements.plist" --sign - "$APP_BUNDLE"

# Create standard macOS Applications drag-target symlink inside DMG
ln -s /Applications "$STAGE_DIR/Applications"

# Include quick setup guide inside the DMG
cat > "$STAGE_DIR/Quick Start — Teams Setup.txt" <<'TXT'
VoiceStudio for Microsoft Teams — Quick Setup
=============================================

1. Drag VoiceStudio.app into the Applications folder.
2. Prerequisite (Virtual Audio Cable):
   Install BlackHole 2ch if you don't already have it:
     brew install --cask blackhole-2ch
3. First Launch (Unnotarized Open-Source App):
   If macOS Gatekeeper blocks launch after browser download, run in Terminal:
     xattr -cr /Applications/VoiceStudio.app
   Then open VoiceStudio from Applications or Spotlight, and grant Microphone access.
4. Connect to Microsoft Teams:
   Open Microsoft Teams -> Settings -> Devices:
   - Microphone: BlackHole 2ch
   - Speaker: Your normal Headphones or Speakers (never BlackHole 2ch)
   - Tip: Set Teams "Noise suppression" to Low or Off to preserve warm bass & 9.5 kHz air.
TXT

echo "==> Creating compressed DMG installer: $DMG_PATH..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "VoiceStudio ${VERSION}" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

(cd "$DIST_DIR" && shasum -a 256 "$DMG_NAME" | tee "${DMG_NAME}.sha256")
echo "==> Done! DMG ready at: $DMG_PATH"
