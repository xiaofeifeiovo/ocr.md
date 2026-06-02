# macOS Screenshot OCR Shortcut

`screenshot_ocr.command` starts a macOS region screenshot, sends the image to
the project's clipboard OCR tool, and copies the recognized text to the
clipboard.

## Test the launcher

From the project directory, run:

```bash
chmod +x screenshot_ocr.command
./screenshot_ocr.command
```

Select a screen region. After OCR finishes, paste somewhere to confirm the
recognized text is in the clipboard.

## Bind Command-Shift-6

1. Open the macOS Shortcuts app and create a new shortcut named `Screenshot OCR`.
2. Add a `Run Shell Script` action.
3. Use this command, replacing the project path if needed:

   ```bash
   /bin/zsh -lc '"/Users/feifeixiao/Desktop/gitclone/ocr.md/screenshot_ocr.command"'
   ```

4. Open the shortcut details, choose `Add Keyboard Shortcut`, then press
   `Command-Shift-6`.

On Macs with a Touch Bar, `Command-Shift-6` may already be assigned to capture
the Touch Bar. Disable that shortcut in System Settings under
`Keyboard > Keyboard Shortcuts > Screenshots`, or choose another key
combination.

The first run may ask for screen capture or automation permissions. Allow the
Shortcuts app when macOS prompts for access.

## Python environment

The Shortcuts action runs a login shell so it can find the same `python3`
installation used in Terminal. If dependencies are installed in a different
Python environment, set `OCR_PYTHON` explicitly:

```bash
OCR_PYTHON="/path/to/python3" "/Users/feifeixiao/Desktop/gitclone/ocr.md/screenshot_ocr.command"
```
