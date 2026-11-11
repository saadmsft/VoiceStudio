#!/usr/bin/env bash
set -euo pipefail

REPO="saadmsft/VoiceStudio"
INSTALL_DIR="/Applications"
if [ ! -w "$INSTALL_DIR" ]; then
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
fi

echo "==> Checking for BlackHole 2ch virtual audio driver..."
if [ ! -d "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver" ]; then
    if command -v brew >/dev/null 2>&1; then
        echo "==> Installing BlackHole 2ch via Homebrew..."
        brew install --cask blackhole-2ch
    else
        echo "WARNING: BlackHole 2ch not detected. Install from https://existential.audio/blackhole/ or via 'brew install --cask blackhole-2ch'."
    fi
else
    echo "    ✓ BlackHole 2ch already installed."
fi

echo "==> Fetching latest VoiceStudio DMG release from GitHub ($REPO)..."
DMG_URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep -Eo 'https://[^"]+\.dmg' | head -n 1)"

if [ -z "$DMG_URL" ]; then
    echo "ERROR: Could not find a .dmg asset in the latest release of $REPO."
    exit 1
fi

TMP_DIR="$(mktemp -d)"
MOUNT_POINT="$TMP_DIR/mnt"
mkdir -p "$MOUNT_POINT"
trap 'hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT

echo "==> Downloading $DMG_URL..."
curl -fL "$DMG_URL" -o "$TMP_DIR/VoiceStudio.dmg"

echo "==> Mounting DMG..."
hdiutil attach "$TMP_DIR/VoiceStudio.dmg" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet

echo "==> Installing VoiceStudio.app to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/VoiceStudio.app"
cp -R "$MOUNT_POINT/VoiceStudio.app" "$INSTALL_DIR/VoiceStudio.app"
xattr -cr "$INSTALL_DIR/VoiceStudio.app" 2>/dev/null || true

echo "==> Installed to $INSTALL_DIR/VoiceStudio.app!"
echo "==> Launching VoiceStudio..."
open "$INSTALL_DIR/VoiceStudio.app"
