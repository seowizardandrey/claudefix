@echo off
setlocal
cd /d "%~dp0"

echo =========================================================
echo  Building Claude Code Proxy Full Stack and Signing
echo =========================================================
echo.

set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe

if not exist "%CSC%" (
    echo [ERROR] Microsoft .NET C# Compiler csc.exe not found!
    exit /b 1
)

echo [1/4] Compiling ClaudeProxyPatcher.exe (GUI / Tray)...
"%CSC%" /nologo /target:winexe /optimize+ /win32icon:"app.ico" /out:"ClaudeProxyPatcher.exe" /reference:System.Windows.Forms.dll,System.Drawing.dll,System.dll,System.Core.dll ClaudeProxyGUI.cs
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Compilation of ClaudeProxyPatcher.exe failed!
    exit /b %ERRORLEVEL%
)
echo       [OK] Built: ClaudeProxyPatcher.exe

echo [2/4] Compiling setup.exe (Installer Engine)...
"%CSC%" /nologo /target:exe /optimize+ /win32icon:"app.ico" /out:"setup.exe" /reference:System.dll,System.Core.dll setup.cs
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Compilation of setup.exe failed!
    exit /b %ERRORLEVEL%
)
echo       [OK] Built: setup.exe

echo [3/4] Compiling claude_wrapper.exe (VS Code Interceptor)...
"%CSC%" /nologo /target:exe /optimize+ /out:"claude_wrapper.exe" /reference:System.dll,System.Core.dll claude_wrapper.cs
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Compilation of claude_wrapper.exe failed!
    exit /b %ERRORLEVEL%
)
echo       [OK] Built: claude_wrapper.exe

echo.
echo Building MSI package...
call "%~dp0build_msi.cmd"

echo.
echo [4/4] Digitally signing all binaries, MSI, and PowerShell scripts...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sign_all.ps1"

echo.
echo =========================================================
echo  Build, Packaging, and Signing Completed Successfully!
echo =========================================================
