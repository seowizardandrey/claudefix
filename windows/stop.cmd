@echo off
setlocal
cd /d "%~dp0"

echo Stopping ClaudeProxy_%USERNAME%...
schtasks /end /tn "ClaudeProxy_%USERNAME%" >nul 2>&1
taskkill /f /im gost.exe >nul 2>&1
echo [OK] Proxy bridge stopped.
