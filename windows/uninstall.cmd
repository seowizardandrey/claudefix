@echo off
setlocal
cd /d "%~dp0"

REM Run setup.exe with uninstall flag
"%~dp0setup.exe" --uninstall
