@echo off
setlocal

rem OCR Clipboard - Windows clipboard OCR launcher
cd /d "%~dp0"

where py >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON_CMD=py"
) else (
    set "PYTHON_CMD=python"
)

%PYTHON_CMD% "%~dp0ocr_clipboard.command"

echo.
echo Press any key to close this window.
pause >nul
