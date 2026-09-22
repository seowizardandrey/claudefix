@echo off
setlocal
cd /d "%~dp0"

echo =========================================================
echo  Claude Code Quick Re-Patcher
echo =========================================================
if exist "%~dp0setup.exe" (
    "%~dp0setup.exe" --patch
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch_vscode.ps1"
)
echo.
