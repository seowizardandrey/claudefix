@echo off
setlocal
cd /d "%~dp0"

echo =========================================================
echo  Compiling Claude Proxy Manager
echo =========================================================

set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe

if not exist "%CSC%" (
    echo [ERROR] Microsoft .NET C# Compiler (csc.exe) not found!
    exit /b 1
)

echo Compiling ClaudeProxyPatcher.exe...
"%CSC%" /nologo /target:winexe /optimize+ /win32icon:"app.ico" /out:"ClaudeProxyPatcher.exe" /reference:System.Windows.Forms.dll,System.Drawing.dll,System.dll,System.Core.dll ClaudeProxyGUI.cs

if %ERRORLEVEL% EQU 0 (
    echo [OK] Successfully compiled: ClaudeProxyPatcher.exe
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like '*Andrey Sokolov*' } | Select-Object -First 1; if ($c) { Set-AuthenticodeSignature -FilePath '%~dp0ClaudeProxyPatcher.exe' -Certificate $c -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com' | Out-Null; Write-Host ' [OK] Digitally signed with Andrey Sokolov Code Signing Certificate.' -ForegroundColor Green } else { Write-Host ' [INFO] Code signing skipped (certificate not found in Cert:\CurrentUser\My).' -ForegroundColor Yellow }"
) else (
    echo [ERROR] Compilation failed!
    exit /b %ERRORLEVEL%
)
