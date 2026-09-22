@echo off
setlocal
cd /d "%~dp0"

REM 1. Unblock downloaded files in this folder (removes Mark of the Web / SmartScreen trigger)
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue" 2>nul

REM 2. Silently trust developer certificate if present
if exist "%~dp0ClaudeProxy.cer" (
    certutil -addstore -f "Root" "%~dp0ClaudeProxy.cer" >nul 2>&1
    certutil -addstore -f "TrustedPublisher" "%~dp0ClaudeProxy.cer" >nul 2>&1
    certutil -user -addstore -f "Root" "%~dp0ClaudeProxy.cer" >nul 2>&1
    certutil -user -addstore -f "TrustedPublisher" "%~dp0ClaudeProxy.cer" >nul 2>&1
)

REM 3. Run native setup.exe installer
"%~dp0setup.exe" %*
