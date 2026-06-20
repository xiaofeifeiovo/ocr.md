#!/bin/bash

# Build a distributable DMG containing the standalone macOS app.
# The resulting app is fully self-contained: users install only this DMG and
# configure everything inside the app. No project files or Python are required.

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

cat > "$STAGING_DIR/使用说明.txt" <<'EOF_README'
Screenshot OCR（截图 OCR）
==========================

这是一个独立的 macOS 菜单栏应用，安装后无需任何其他文件即可使用。

安装：
1. 将 “Screenshot OCR.app” 拖到 “Applications”（应用程序）文件夹。
2. 双击打开。首次打开若被 Gatekeeper 拦截，可在
   “系统设置 > 隐私与安全性” 中点击 “仍要打开”。
3. 菜单栏会出现一个图标。首次启动会弹出设置面板。

配置：
- 在设置面板中填写对应模型的 API Key（DashScope / MiMo / OpenRouter）。
- 选择模型与输出格式（LaTeX / Markdown / 公式 / 纯文本）。
- 可填写自定义系统提示词。
- 可勾选 “开机自动启动” 和 “开机静默启动”。
- 点击 “保存配置”。

使用：
- 按 Command-Shift-6，框选屏幕区域。
- 应用自动进行 AI OCR，并把结果复制到剪贴板，完成后弹出提示。

菜单（点击菜单栏图标）：
- 立即截图 OCR
- 启用 / 停用快捷键 ⌘⇧6
- 设置…
- 开机自动启动
- 退出

提示：
- 若 Command-Shift-6 被系统占用，请在
  “系统设置 > 键盘 > 键盘快捷键 > 截屏” 中关闭冲突项，
  然后在菜单中重新启用快捷键。
- 需要 macOS 13 (Ventura) 或更高版本。
EOF_README

/usr/bin/hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

echo "Built: $DMG_PATH"
