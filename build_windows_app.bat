@echo off
setlocal

rem Build the Windows desktop app executable with PyInstaller.
cd /d "%~dp0"

where py >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON_CMD=py"
) else (
    set "PYTHON_CMD=python"
)

if not exist ".venv-build\Scripts\python.exe" (
    echo Creating build virtual environment...
    %PYTHON_CMD% -m venv .venv-build
    if errorlevel 1 exit /b 1
)

set "BUILD_PY=.venv-build\Scripts\python.exe"

echo Installing build dependencies...
"%BUILD_PY%" -m pip install --upgrade pip
if errorlevel 1 exit /b 1
"%BUILD_PY%" -m pip install -r requirements-windows-app.txt -r requirements-windows-build.txt
if errorlevel 1 exit /b 1

echo Building OCR Clipboard.exe...
"%BUILD_PY%" -m PyInstaller --clean "OCR Clipboard.spec"
if errorlevel 1 exit /b 1

echo.
echo Built:
echo %CD%\dist\OCR Clipboard.exe
