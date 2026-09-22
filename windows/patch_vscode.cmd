@echo off
setlocal
cd /d "%~dp0"

echo =========================================================
echo  Patching VS Code Claude Code Extension
echo =========================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch_vscode.ps1" %*
echo.
