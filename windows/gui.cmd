@echo off
setlocal
cd /d "%~dp0"

set "PORT=19000"
set "CONFIG=%USERPROFILE%\.config\claude-proxy\proxy.env"
if exist "%CONFIG%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG%") do (
        if "%%A"=="PROXY_PORT" set "PORT=%%B"
    )
)

echo [INFO] Closing any running Claude Desktop instances to apply proxy...
taskkill /f /im Claude.exe >nul 2>&1
timeout /t 1 >nul

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_claude_gui.ps1" -ProxyPort %PORT%
