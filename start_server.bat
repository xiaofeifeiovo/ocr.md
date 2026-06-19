@echo off
setlocal

rem OCR Clipboard - Windows one-click startup script
cd /d "%~dp0"

set "DEFAULT_PORT=8080"
set "REQUESTED_PORT=%~1"
if not defined REQUESTED_PORT (
    if defined PORT (
        set "REQUESTED_PORT=%PORT%"
    ) else (
        set "REQUESTED_PORT=%DEFAULT_PORT%"
    )
)

echo %REQUESTED_PORT%| findstr /r "^[1-9][0-9]*$" >nul
if errorlevel 1 (
    echo Invalid port: %REQUESTED_PORT%
    echo Usage: start_server.bat [port]
    pause
    exit /b 1
)

set "PORT=%REQUESTED_PORT%"
if %PORT% GTR 65535 (
    echo Invalid port: %REQUESTED_PORT%
    echo Usage: start_server.bat [port]
    pause
    exit /b 1
)

where py >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON_CMD=py"
) else (
    set "PYTHON_CMD=python"
)

:find_port
netstat -ano | findstr /r /c:":%PORT% .*LISTENING" >nul
if errorlevel 1 goto port_found
set /a PORT+=1
if %PORT% GTR 65535 (
    echo No available port found.
    pause
    exit /b 1
)
goto find_port

:port_found
set "URL=http://127.0.0.1:%PORT%"

if not "%PORT%"=="%REQUESTED_PORT%" (
    echo Port %REQUESTED_PORT% is already in use. Using %PORT% instead.
)

echo Starting OCR server on %URL% ...
echo.

start "OCR Clipboard Server %PORT%" cmd /k "%PYTHON_CMD% -m uvicorn server:app --reload --port %PORT%"

echo.
echo Waiting for the server window to start...
timeout /t 3 /nobreak >nul
start "" "%URL%"
