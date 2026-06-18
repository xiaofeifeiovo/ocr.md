# macOS Hotkey App

`Screenshot OCR.app` is a standalone menu-bar app for macOS. It registers
`Command-Shift-6` globally and calls the existing project OCR flow:

```text
Command-Shift-6 -> selected screenshot -> LaTeX OCR -> clipboard
```

The app does not use the Shortcuts app. It still uses this project's
`screenshot_ocr.command`, which calls `ocr_clipboard.command`, so the OCR model,
API key loading, and LaTeX prompt stay in one place.

## Build

From the project directory:

```bash
./build_macos_hotkey_app.command
```

The app is created at:

```text
dist/Screenshot OCR.app
```

Launch it:

```bash
open "dist/Screenshot OCR.app"
```

When the app is running, an `OCR` item appears in the macOS menu bar.

## Login Item

To keep the shortcut available after reboot:

1. Click the `OCR` menu-bar item.
2. Choose `Install Login Item`.
3. Allow macOS automation permission if prompted.

You can remove it later from the same menu or from
`System Settings > General > Login Items`.

## Shortcut Conflict

`Command-Shift-6` can conflict with macOS's Touch Bar screenshot shortcut.
If the app reports that the hotkey is unavailable, disable the conflicting
system shortcut:

```text
System Settings > Keyboard > Keyboard Shortcuts > Screenshots
```

Then choose `Re-register Command-Shift-6` from the `OCR` menu.

## Logs

The app writes logs here:

```text
~/Library/Logs/ScreenshotOCRHotkey.log
```

Use `Open Log File` from the `OCR` menu to inspect failures.
