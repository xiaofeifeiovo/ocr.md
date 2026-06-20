# Windows App

`windows_screenshot_ocr.pyw` is the source entry for the Windows desktop app.
After packaging, users install and launch `OCR Clipboard.exe`, configure API
keys/model/output format in the app window, then press:

```text
Ctrl+Shift+6
```

The app lets the user drag a screenshot region, sends that image to the
configured AI vision model, copies the OCR result to the clipboard, and defaults
to LaTeX output. When OCR completes, it shows a Windows notification and falls
back to an in-app toast if Windows notification delivery is unavailable.

## Source Run

Install source-run dependencies:

```powershell
pip install -r requirements-windows-app.txt
```

Then run from the project directory:

```powershell
py windows_screenshot_ocr.pyw
```

You can also double-click:

```text
start_windows_hotkey.bat
```

## Build Executable

Double-click:

```text
build_windows_app.bat
```

The executable is created at:

```text
dist\OCR Clipboard.exe
```

## Build Installer

Install Inno Setup 6, then double-click:

```text
build_windows_installer.bat
```

The installer is created at:

```text
dist\OCRClipboardSetup.exe
```

If Inno Setup is not installed, the build script still creates the standalone
executable and prints its path.

## Runtime Configuration

The installed app stores user settings here:

```text
%APPDATA%\OCRClipboard\config.json
```

Configurable options:

- DashScope / Qwen API key
- MiMo API key
- OpenRouter API key
- Model
- Output format
- Optional custom system prompt
- Optional launch at login
- Optional silent launch at login

When both launch-at-login options are enabled, the registry startup command is
written with `--silent`. The app starts in the background after sign-in, keeps
the `Ctrl+Shift+6` hotkey active, and does not show the settings window. Opening
`OCR Clipboard.exe` again brings the existing background instance to the front.

## Logs

Logs are written here:

```text
%LOCALAPPDATA%\OCRClipboard\ScreenshotOCRHotkey.log
```
