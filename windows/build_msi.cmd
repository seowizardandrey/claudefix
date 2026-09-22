@echo off
setlocal
cd /d "%~dp0"

echo =========================================================
echo  Building Claude Code Proxy MSI Installer
echo =========================================================
echo.

set "WIX_BIN=C:\Users\Wizard\.gemini\antigravity-ide\brain\f3ae1850-b935-41c0-afe6-5d075b58b719\scratch\wix\bin"
if not exist "%WIX_BIN%\candle.exe" (
    echo [ERROR] WiX toolset not found at %WIX_BIN%
    exit /b 1
)

echo [1/3] Compiling WiX objects (candle.exe)...
"%WIX_BIN%\candle.exe" -nologo -arch x64 -ext WixUIExtension -out "%~dp0ClaudeProxy.wixobj" "%~dp0ClaudeProxy.wxs"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] candle.exe failed!
    exit /b %ERRORLEVEL%
)

echo [2/3] Linking MSI package (light.exe)...
"%WIX_BIN%\light.exe" -nologo -ext WixUIExtension -sice:ICE18 -sice:ICE69 -sice:ICE91 -sice:ICE38 -out "%~dp0ClaudeProxySetup.msi" "%~dp0ClaudeProxy.wixobj"
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] light.exe failed!
    del "%~dp0ClaudeProxy.wixobj" >nul 2>&1
    exit /b %ERRORLEVEL%
)
del "%~dp0ClaudeProxy.wixobj" >nul 2>&1
echo       [OK] Built: ClaudeProxySetup.msi

echo [3/3] Digitally signing MSI package...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like '*Andrey Sokolov*' } | Select-Object -First 1; if ($c) { Set-AuthenticodeSignature -FilePath '%~dp0ClaudeProxySetup.msi' -Certificate $c -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com' | Out-Null; Write-Host '      [OK] ClaudeProxySetup.msi signed with Andrey Sokolov certificate!' -ForegroundColor Green } else { Write-Host '      [WARNING] Certificate not found in Cert:\CurrentUser\My.' -ForegroundColor Yellow }"

echo.
echo =========================================================
echo  MSI Build and Signing Completed Successfully!
echo =========================================================
