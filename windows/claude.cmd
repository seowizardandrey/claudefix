@echo off
setlocal enabledelayedexpansion

:: claude.cmd - Global Launcher for Claude Code on Windows
:: Part of Claude Code Proxy Toolkit

:: 1. Check Standalone Claude CLI in .local\bin
if exist "%USERPROFILE%\.local\bin\claude.exe" (
    endlocal
    "%USERPROFILE%\.local\bin\claude.exe" %*
    exit /b %ERRORLEVEL%
)

:: 2. Check Standalone Claude CLI versions in .local\share\claude
set "CLI_DIR=%USERPROFILE%\.local\share\claude\versions"
if exist "%CLI_DIR%" (
    for /f "delims=" %%f in ('dir /b /s "%CLI_DIR%\claude.exe" 2^>nul') do (
        endlocal
        "%%f" %*
        exit /b %ERRORLEVEL%
    )
)

:: 3. Check VS Code extension native binary
set "VSCODE_DIR=%USERPROFILE%\.vscode\extensions"
if exist "%VSCODE_DIR%" (
    for /d %%d in ("%VSCODE_DIR%\anthropic.claude-code-*") do (
        if exist "%%d\resources\native-binary\claude.exe" (
            endlocal
            "%%d\resources\native-binary\claude.exe" %*
            exit /b %ERRORLEVEL%
        )
        if exist "%%d\resources\native-binaries\win32-x64\claude.exe" (
            endlocal
            "%%d\resources\native-binaries\win32-x64\claude.exe" %*
            exit /b %ERRORLEVEL%
        )
    )
)

:: 4. Check VS Code Insiders
set "VSCODE_INSIDERS_DIR=%USERPROFILE%\.vscode-insiders\extensions"
if exist "%VSCODE_INSIDERS_DIR%" (
    for /d %%d in ("%VSCODE_INSIDERS_DIR%\anthropic.claude-code-*") do (
        if exist "%%d\resources\native-binary\claude.exe" (
            endlocal
            "%%d\resources\native-binary\claude.exe" %*
            exit /b %ERRORLEVEL%
        )
        if exist "%%d\resources\native-binaries\win32-x64\claude.exe" (
            endlocal
            "%%d\resources\native-binaries\win32-x64\claude.exe" %*
            exit /b %ERRORLEVEL%
        )
    )
)

:: 5. Check global npm package
if exist "%APPDATA%\npm\claude.cmd" (
    endlocal
    call "%APPDATA%\npm\claude.cmd" %*
    exit /b %ERRORLEVEL%
)

echo [Error] Claude Code executable not found! >&2
echo Please run: install_cli.cmd (or install_claude_cli.ps1) >&2
echo to install official Claude Code via your active proxy bridge. >&2
exit /b 1
