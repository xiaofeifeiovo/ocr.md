#!/bin/bash

# Capture a selected screen region, OCR it, and copy the result to the clipboard.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_IMAGE="$(mktemp -t ocr_clipboard_screenshot)"

cleanup() {
    rm -f "$TEMP_IMAGE"
}

notify() {
    /usr/bin/osascript \
        -e "display notification \"$1\" with title \"OCR Clipboard\"" \
        > /dev/null 2>&1 || true
}

trap cleanup EXIT
rm -f "$TEMP_IMAGE"

# An empty or missing output file means the user cancelled the screenshot.
if ! /usr/sbin/screencapture -i -s -tpng "$TEMP_IMAGE"; then
    exit 0
fi
if [ ! -s "$TEMP_IMAGE" ]; then
    exit 0
fi

PYTHON_BIN="${OCR_PYTHON:-}"
if [ -z "$PYTHON_BIN" ]; then
    PYTHON_BIN="$(command -v python3 || true)"
fi
if [ -z "$PYTHON_BIN" ]; then
    notify "未找到 Python 3，无法执行 OCR。"
    echo "Python 3 was not found. Set OCR_PYTHON to the Python executable." >&2
    exit 1
fi

notify "正在识别截图..."
if "$PYTHON_BIN" "$SCRIPT_DIR/ocr_clipboard.command" --image "$TEMP_IMAGE"; then
    notify "OCR 已完成，结果已复制到剪切板。"
else
    notify "OCR 失败，请检查 API Key 和终端输出。"
    exit 1
fi
