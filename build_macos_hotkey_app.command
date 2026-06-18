#!/bin/bash

# Build the standalone macOS menu-bar app that registers Command-Shift-6.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/macos/ScreenshotOCRHotkey"
BUILD_DIR="$SCRIPT_DIR/build/macos-hotkey"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="Screenshot OCR"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
EXECUTABLE_NAME="ScreenshotOCRHotkey"
GENERATED_CONFIG="$BUILD_DIR/GeneratedConfig.h"

mkdir -p "$BUILD_DIR" "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

chmod +x "$SCRIPT_DIR/screenshot_ocr.command" "$SCRIPT_DIR/ocr_clipboard.command"

objc_string() {
    /usr/bin/python3 -c 'import json, sys; print("@" + json.dumps(sys.argv[1]))' "$1"
}

cat > "$GENERATED_CONFIG" <<EOF_CONFIG
#import <Foundation/Foundation.h>

static NSString * const AppDisplayName = $(objc_string "$APP_NAME");
static NSString * const ProjectPath = $(objc_string "$SCRIPT_DIR");
static NSString * const DefaultScriptPath = $(objc_string "$SCRIPT_DIR/screenshot_ocr.command");
EOF_CONFIG

/usr/bin/clang \
    -fobjc-arc \
    -O2 \
    -I "$BUILD_DIR" \
    -framework Cocoa \
    -framework Carbon \
    "$SOURCE_DIR/ScreenshotOCRHotkey.m" \
    -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>local.ocrclipboard.hotkey</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026</string>
</dict>
</plist>
EOF_PLIST

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

echo "Built: $APP_BUNDLE"
echo "Open it with:"
echo "  open \"$APP_BUNDLE\""
