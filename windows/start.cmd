@echo off
setlocal
cd /d "%~dp0"

echo Starting ClaudeProxy_%USERNAME%...
schtasks /run /tn "ClaudeProxy_%USERNAME%" >nul 2>&1
timeout /t 2 >nul
call "%~dp0status.cmd"
