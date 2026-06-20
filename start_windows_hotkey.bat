@echo off
setlocal

rem OCR Clipboard - Windows desktop app launcher
cd /d "%~dp0"

where pyw >nul 2>nul
if %errorlevel%==0 (
    start "" pyw "%~dp0windows_screenshot_ocr.pyw"
    exit /b 0
)

where pythonw >nul 2>nul
if %errorlevel%==0 (
    start "" pythonw "%~dp0windows_screenshot_ocr.pyw"
    exit /b 0
)

where py >nul 2>nul
if %errorlevel%==0 (
    start "OCR Clipboard Hotkey" /min py "%~dp0windows_screenshot_ocr.pyw"
    exit /b 0
)

where python >nul 2>nul
if %errorlevel%==0 (
    start "OCR Clipboard Hotkey" /min python "%~dp0windows_screenshot_ocr.pyw"
    exit /b 0
)

echo Python was not found. Install Python 3.10 or newer, then run this file again.
pause
exit /b 1
