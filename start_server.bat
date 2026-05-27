@echo off
setlocal

rem OCR Clipboard - Windows one-click startup script
cd /d "%~dp0"

set "PORT=8080"
set "URL=http://127.0.0.1:%PORT%"

where py >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON_CMD=py"
) else (
    set "PYTHON_CMD=python"
)

echo Starting OCR server on %URL% ...
echo.

start "OCR Clipboard Server" cmd /k "%PYTHON_CMD% -m uvicorn server:app --reload --port %PORT%"

echo.
echo Waiting for the server window to start...
timeout /t 3 /nobreak >nul
start "" "%URL%"
