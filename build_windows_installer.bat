@echo off
setlocal

rem Build the Windows app and, when Inno Setup is installed, package an installer.
cd /d "%~dp0"

call "%~dp0build_windows_app.bat"
if errorlevel 1 exit /b 1

set "ISCC_CMD="
where ISCC >nul 2>nul
if %errorlevel%==0 (
    set "ISCC_CMD=ISCC"
)

if not defined ISCC_CMD (
    if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" (
        set "ISCC_CMD=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
    )
)

if not defined ISCC_CMD (
    if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" (
        set "ISCC_CMD=%ProgramFiles%\Inno Setup 6\ISCC.exe"
    )
)

if not defined ISCC_CMD (
    echo.
    echo Inno Setup was not found. The executable was built successfully:
    echo %CD%\dist\OCR Clipboard.exe
    echo.
    echo Install Inno Setup 6 and run this file again to create the installer.
    exit /b 0
)

echo Building installer...
"%ISCC_CMD%" "%~dp0installer\OCRClipboard.iss"
if errorlevel 1 exit /b 1

echo.
echo Built installer in:
echo %CD%\dist
