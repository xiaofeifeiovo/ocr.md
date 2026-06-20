# macOS App

`Screenshot OCR.app` is a **standalone, self-contained** macOS menu-bar app. It
does not depend on this project's Python scripts, a Python runtime, or any other
file — users install the single DMG and configure everything inside the app.

```text
Command-Shift-6 -> select a screen region -> AI OCR -> clipboard -> notification
```

The OCR model configuration and prompts are a native port of `ocr_core.py`, so
the app stays consistent with the web and Windows builds.

## Features

- Lives in the macOS menu bar (no Dock icon).
- Global `Command-Shift-6` hotkey: capture a region, OCR it, copy the result to
  the clipboard, and show an on-screen confirmation.
- Settings panel (like the web UI):
  - model selection (Qwen / MiMo / OpenRouter Gemini)
  - output format: LaTeX / Markdown / 公式识别 / 纯文本
  - custom system prompt
  - API keys for DashScope, MiMo, and OpenRouter
  - launch at login + silent launch (menu-bar only)
- Menu toggle to enable/disable the `Command-Shift-6` hotkey.

No special permissions are required: the interactive `screencapture` flow does
not need Screen Recording permission, and the Carbon hotkey does not need
Accessibility/Input Monitoring permission.

## Build the app

From the project directory:

```bash
./build_macos_hotkey_app.command
```

The app is created at `dist/Screenshot OCR.app`. Launch it with:

```bash
open "dist/Screenshot OCR.app"
```

## Build the DMG

```bash
./build_macos_dmg.command
```

The installable disk image is created at `dist/Screenshot OCR.dmg`. Open it and
drag `Screenshot OCR.app` to `Applications`.

## First run

1. Open the app. A menu-bar icon appears and the settings panel opens.
2. Enter the API key for the model you want to use, pick a model and output
   format, then click **保存配置**.
3. Press `Command-Shift-6` to capture a region. The result is copied to the
   clipboard and a confirmation appears on screen.

## Launch at login

Use the **开机自动启动** menu item or the checkbox in the settings panel. This
uses `SMAppService` (macOS 13+); manage it later in
`System Settings > General > Login Items`. Enable **开机静默启动** to start
directly in the menu bar without opening the panel.

## Shortcut conflict

If `Command-Shift-6` is already taken, the app shows a warning. Disable the
conflicting shortcut in `System Settings > Keyboard > Keyboard Shortcuts`, then
re-enable the hotkey from the menu.

## Configuration storage

Settings are stored as JSON at:

```text
~/Library/Application Support/ScreenshotOCR/config.json
```

The shape mirrors the Windows app's `config.json`.

## Source layout

```text
macos/ScreenshotOCRHotkey/
  main.m                      app entry point
  AppDelegate.{h,m}           status item, hotkey, capture flow, HUD, login item
  SettingsWindowController.{h,m}  settings panel
  OCREngine.{h,m}             native OCR over the chat-completions API
  OCRSettings.{h,m}           config load/save + API key resolution
  OCRConfig.{h,m}             model list + prompts (ported from ocr_core.py)
```

## Requirements

- macOS 13 (Ventura) or later.
- Xcode Command Line Tools (`clang`) to build.
