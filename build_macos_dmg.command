#!/bin/bash

# Build a distributable DMG for the standalone macOS hotkey app.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Screenshot OCR"
VOLUME_NAME="$APP_NAME"
DIST_DIR="$SCRIPT_DIR/dist"
BUILD_DIR="$SCRIPT_DIR/build/macos-dmg"
STAGING_DIR="$BUILD_DIR/$VOLUME_NAME"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

"$SCRIPT_DIR/build_macos_hotkey_app.command"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle was not built: $APP_BUNDLE" >&2
    exit 1
fi

rm -rf "$BUILD_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

/bin/cp -R "$APP_BUNDLE" "$STAGING_DIR/"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/README.txt" <<EOF_README
Screenshot OCR
==============

Install:
1. Drag "Screenshot OCR.app" to Applications.
2. Open the app.
3. Click the "OCR" menu-bar item and choose "Install Login Item" if you want it to start after sign-in.

Usage:
Press Command-Shift-6 to select a screen region. The app runs OCR and copies LaTeX text to the clipboard.

Notes:
- If Command-Shift-6 is already used by macOS screenshots, disable the conflicting shortcut in System Settings > Keyboard > Keyboard Shortcuts > Screenshots.
- This build calls the OCR scripts from:
  $SCRIPT_DIR
- Rebuild the app/DMG after moving the project folder.
EOF_README

/usr/bin/hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

echo "Built: $DMG_PATH"
