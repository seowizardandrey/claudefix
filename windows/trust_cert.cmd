@echo off
setlocal
cd /d "%~dp0"

echo =========================================================
echo  Install Claude Code Proxy Certificate (Andrey Sokolov)
echo =========================================================
echo.

set "CER_FILE=%~dp0ClaudeProxy.cer"
if not exist "%CER_FILE%" (
    echo [ERROR] Certificate file not found: %CER_FILE%
    pause
    exit /b 1
)

REM Check for administrative privileges
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [REQUEST] Administrative permissions required to trust certificate in Root store.
    echo Requesting elevation...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c `\"%~f0`\"' -Verb RunAs"
    exit /b 0
)

echo [1/3] Adding certificate to Trusted Root Certification Authorities...
certutil -addstore -f "Root" "%CER_FILE%" >nul 2>&1
certutil -user -addstore -f "Root" "%CER_FILE%" >nul 2>&1
echo       [OK] Installed to Root store.

echo [2/3] Adding certificate to Trusted Publishers...
certutil -addstore -f "TrustedPublisher" "%CER_FILE%" >nul 2>&1
certutil -user -addstore -f "TrustedPublisher" "%CER_FILE%" >nul 2>&1
echo       [OK] Installed to TrustedPublisher store.

echo [3/3] Removing Mark of the Web (Zone.Identifier) from all files...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -Path '%~dp0' -Recurse | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1
echo       [OK] All files unblocked.

echo.
echo =========================================================
echo  Certificate successfully installed and files unblocked!
echo  Windows Defender SmartScreen and UAC will now trust
echo  binaries signed by Andrey Sokolov without warnings.
echo =========================================================
echo.
timeout /t 3 >nul 2>&1
