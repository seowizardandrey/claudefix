@echo off
setlocal
cd /d "%~dp0"

echo =========================================================
echo  Claude Code CLI & VS Code Extension Installer (Windows)
echo =========================================================
echo Routing through active GOST proxy bridge...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_claude_cli.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [WARN] PowerShell installer encountered an error. Trying direct npm install...
    call "%~dp0status.cmd"
    set "PORT=19000"
    set "CONFIG=%USERPROFILE%\.config\claude-proxy\proxy.env"
    if exist "%CONFIG%" (
        for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG%") do (
            if "%%A"=="PROXY_PORT" set "PORT=%%B"
        )
    )
    npm install -g @anthropic-ai/claude-code --proxy http://127.0.0.1:%PORT%
)

echo.
echo =========================================================
echo Done! You can now use:
echo   claude --version
echo   claude
echo =========================================================
