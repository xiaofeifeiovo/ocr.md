#!/bin/bash

# Build the standalone, self-contained macOS menu-bar app.
# The app performs screenshot OCR entirely on its own: it registers
# Command-Shift-6, captures a region, calls the AI OCR API directly, and copies
# the result to the clipboard. It does not depend on the project's Python scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/macos/ScreenshotOCRHotkey"
BUILD_DIR="$SCRIPT_DIR/build/macos-hotkey"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="Screenshot OCR"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
EXECUTABLE_NAME="ScreenshotOCRHotkey"
BUNDLE_ID="local.ocrclipboard.hotkey"
APP_VERSION="2.2"
APP_BUILD="4"

rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR" "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

# Compile every Objective-C source file in the app directory.
/usr/bin/clang \
    -fobjc-arc \
    -O2 \
    -mmacosx-version-min=13.0 \
    -framework Cocoa \
    -framework Carbon \
    -framework ServiceManagement \
    "$SOURCE_DIR"/*.m \
    -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026</string>
</dict>
</plist>
EOF_PLIST

# Prefer a real, stable signing identity when one is available. If this is a
# local build without a certificate, keep the ad-hoc signature's designated
# requirement stable; otherwise macOS TCC Screen Recording grants can remain
# visible in System Settings while no longer matching a rebuilt binary.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$CODESIGN_IDENTITY" ]; then
    CODESIGN_IDENTITY="$(
        /usr/bin/security find-identity -v -p codesigning 2>/dev/null |
            /usr/bin/awk -F'"' '/Developer ID Application/ { print $2; exit }'
    )"
fi

if [ -n "$CODESIGN_IDENTITY" ]; then
    /usr/bin/codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
    echo "Signed with identity: $CODESIGN_IDENTITY"
else
    CODESIGN_REQUIREMENT="=designated => identifier \"$BUNDLE_ID\""
    /usr/bin/codesign --force --deep --sign - --requirements "$CODESIGN_REQUIREMENT" "$APP_BUNDLE" >/dev/null
    echo "Signed ad-hoc with stable TCC requirement: $BUNDLE_ID"
fi

echo "Built: $APP_BUNDLE"
echo "Open it with:"
echo "  open \"$APP_BUNDLE\""
