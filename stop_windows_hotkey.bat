@echo off
setlocal

rem Stop the OCR Clipboard Windows hotkey app started by start_windows_hotkey.bat.
cd /d "%~dp0"
set "OCR_HOTKEY_SCRIPT=%~dp0windows_screenshot_ocr.pyw"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$script=[IO.Path]::GetFullPath($env:OCR_HOTKEY_SCRIPT); $procs=Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($script) }; if (-not $procs) { Write-Host 'Windows hotkey app is not running.'; exit 0 }; foreach ($p in $procs) { Stop-Process -Id $p.ProcessId -Force; Write-Host ('Stopped Windows OCR hotkey process ' + $p.ProcessId) }"

pause
