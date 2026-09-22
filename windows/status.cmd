@echo off
setlocal
cd /d "%~dp0"

set "PORT=19000"
set "CONFIG=%USERPROFILE%\.config\claude-proxy\proxy.env"
if exist "%CONFIG%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%CONFIG%") do (
        if "%%A"=="PROXY_PORT" set "PORT=%%B"
    )
)

echo =========================================================
echo  Claude Code Proxy Status for %USERNAME%
echo =========================================================
echo Local Port   : 127.0.0.1:%PORT%
echo Config File  : %CONFIG%
echo ---------------------------------------------------------

netstat -ano | findstr ":%PORT%" | findstr "LISTENING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [PORT]    Port %PORT% is LISTENING [ACTIVE]
    netstat -ano | findstr ":%PORT%" | findstr "LISTENING"
) else (
    echo [PORT]    Port %PORT% is NOT LISTENING [STOPPED]
)

echo.
echo Process Status (GOST):
tasklist /fi "imagename eq gost.exe" 2>nul | findstr /i "gost.exe"
if %ERRORLEVEL% NEQ 0 (
    echo [PROCESS] gost.exe is NOT running
) else (
    echo [PROCESS] gost.exe is RUNNING
)

echo.
echo Scheduled Task Status:
schtasks /query /tn "ClaudeProxy_%USERNAME%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [TASK]    Task "ClaudeProxy_%USERNAME%" is REGISTERED
    schtasks /query /tn "ClaudeProxy_%USERNAME%" /fo LIST 2>nul
) else (
    echo [TASK]    Task "ClaudeProxy_%USERNAME%" is NOT registered
)

echo =========================================================
