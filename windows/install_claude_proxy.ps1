# install_claude_proxy.ps1 - Полная автоматическая установка Claude Code Proxy & Auto-Patcher для Windows
# Part of Claude Code Proxy Toolkit
# Использование:
#   .\install_claude_proxy.ps1 "socks5://USER:PASSWORD@HOST:PORT"
#   .\install_claude_proxy.ps1 (интерактивный ввод)

[CmdletBinding()]
param(
    [string]$Socks5Url = "",
    [int]$ProxyPort = 19000,
    [switch]$NoAutoStart,
    [switch]$EnableScheduledTasks
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " Claude Code Proxy & Auto-Patcher для Windows" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Запрос адреса SOCKS5-прокси
if (-not $Socks5Url) {
    Write-Host "`nУкажите адрес вашего SOCKS5-прокси." -ForegroundColor Yellow
    Write-Host "Формат: socks5://USER:PASSWORD@HOST:PORT" -ForegroundColor Gray
    Write-Host "   или: socks5://HOST:PORT (если без пароля)" -ForegroundColor Gray
    Write-Host "   или: USER:PASSWORD@HOST:PORT`n" -ForegroundColor Gray
    
    $inputVal = Read-Host "Введите адрес SOCKS5"
    if ($inputVal) { $Socks5Url = $inputVal.Trim() }
}

if (-not $Socks5Url) {
    Write-Error "Ошибка: Адрес SOCKS5-прокси не указан!"
    exit 1
}

# Нормализация схемы socks5://
if (-not ($Socks5Url.StartsWith("socks5://") -or $Socks5Url.StartsWith("socks5h://"))) {
    $Socks5Url = "socks5://" + $Socks5Url
}

Write-Host "`nПараметры установки:" -ForegroundColor Cyan
Write-Host "  SOCKS5 прокси : $Socks5Url" -ForegroundColor White
Write-Host "  Локальный порт: $ProxyPort" -ForegroundColor White
Write-Host "  Пользователь  : $env:USERNAME" -ForegroundColor White
Write-Host "  Папка профиля : $env:USERPROFILE`n" -ForegroundColor White

# 2. Создание каталога конфигурации ~/.config/claude-proxy
$configDir = Join-Path $env:USERPROFILE ".config\claude-proxy"
if (-not (Test-Path $configDir)) {
    New-Item -Path $configDir -ItemType Directory -Force | Out-Null
}

$proxyEnvPath = Join-Path $configDir "proxy.env"
$envContent = @"
# Claude Code Proxy Configuration (Windows)
PROXY_PORT=$ProxyPort
SOCKS5_URL="$Socks5Url"
PROXY_MODE="anthropic_only"
"@
Set-Content -Path $proxyEnvPath -Value $envContent -Encoding utf8
Write-Host "[1/5] Конфигурация сохранена в: $proxyEnvPath" -ForegroundColor Green

# Копирование bypass.conf
$destBypass = Join-Path $configDir "bypass.conf"
$srcBypass = Join-Path $ScriptDir "bypass.conf"
if (-not (Test-Path $destBypass) -and (Test-Path $srcBypass)) {
    Copy-Item -Path $srcBypass -Destination $destBypass -Force
    Write-Host "[2/5] Список исключений bypass.conf скопирован в: $destBypass" -ForegroundColor Green
} else {
    Write-Host "[2/5] Список исключений bypass.conf уже существует." -ForegroundColor Green
}

# 3. Компиляция нативного C# враппера
Write-Host "[3/5] Компиляция нативного микро-враппера claude_wrapper.exe..." -ForegroundColor Cyan
$wrapperCs = Join-Path $ScriptDir "claude_wrapper.cs"
$wrapperExe = Join-Path $ScriptDir "claude_wrapper.exe"

$cscPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $cscPath)) {
    $cscCmd = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($cscCmd) { $cscPath = $cscCmd.Source }
}

if (-not (Test-Path $cscPath)) {
    Write-Error "Не найден компилятор csc.exe в Windows .NET Framework!"
    exit 1
}

& $cscPath /nologo /target:exe /optimize+ /out:"$wrapperExe" "$wrapperCs"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $wrapperExe)) {
    Write-Error "Ошибка при компиляции claude_wrapper.cs"
    exit 1
}
Write-Host "      [OK] Враппер успешно скомпилирован: $wrapperExe" -ForegroundColor Green

# 4. Наложение патча на текущие установленные версии
Write-Host "[4/5] Применение патчера к установленным версиям VS Code и CLI..." -ForegroundColor Cyan
$autopatchScript = Join-Path $ScriptDir "autopatch_claude.ps1"
& $autopatchScript -Restart

# 5. Развертывание исполняемых скриптов в ~/.config/claude-proxy/bin и настройка PATH
$userBinDir = Join-Path $configDir "bin"
if (-not (Test-Path $userBinDir)) {
    New-Item -Path $userBinDir -ItemType Directory -Force | Out-Null
}

$filesToDeploy = @(
    "claude.cmd", "claude-stats.ps1", "with-proxy.ps1", "start_proxy.ps1", "stop_proxy.ps1",
    "claude_proxy_bridge.js", "claude_proxy_bridge.py", "claude_watcher.ps1", "autopatch_claude.ps1",
    "claude_wrapper.exe", "claude_wrapper.cs", "bypass.conf", "setup_claude_gui.ps1",
    "stats.cmd", "gui.cmd", "start.cmd", "stop.cmd", "status.cmd", "status_proxy.ps1"
)

foreach ($f in $filesToDeploy) {
    $src = Join-Path $ScriptDir $f
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $userBinDir $f) -Force
    }
}

# Копирование в ProgramData для системного автозапуска (если есть права)
$programDataDir = "C:\ProgramData\claude-proxy"
try {
    if (-not (Test-Path $programDataDir)) {
        New-Item -Path $programDataDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -Path $proxyEnvPath -Destination (Join-Path $programDataDir "proxy.env") -Force -ErrorAction SilentlyContinue
    if (Test-Path $destBypass) {
        Copy-Item -Path $destBypass -Destination (Join-Path $programDataDir "bypass.conf") -Force -ErrorAction SilentlyContinue
    }
} catch {}

# Проверка и добавление в User PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$userBinDir*") {
    $newUserPath = "$userBinDir;" + $userPath
    [Environment]::SetEnvironmentVariable("PATH", $newUserPath, "User")
    $env:PATH = "$userBinDir;" + $env:PATH
    Write-Host "[5/6] Папка $userBinDir добавлена в переменную окружения PATH пользователя." -ForegroundColor Green
} else {
    Write-Host "[5/6] Папка $userBinDir уже находится в PATH." -ForegroundColor Green
}

# 6. Настройка многоуровневого тихого автозапуска по умолчанию
if (-not $NoAutoStart) {
    # 1) Папка Автозагрузка Windows (Startup folder)
    $startupDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
    if (Test-Path $startupDir) {
        $oldVbs = Join-Path $startupDir "ClaudeProxyStartup.vbs"
        if (Test-Path $oldVbs) { Remove-Item -Path $oldVbs -Force -ErrorAction SilentlyContinue }

        $shortcutPath = Join-Path $startupDir "ClaudeProxy.lnk"
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $sc = $wsh.CreateShortcut($shortcutPath)
            $sc.TargetPath = "powershell.exe"
            $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherPs`""
            $sc.WorkingDirectory = $userBinDir
            $sc.Description = "Claude Code Proxy Autostart"
            $sc.Save()
        } catch {
            $cmdRunner = Join-Path $startupDir "ClaudeProxyStartup.cmd"
            Set-Content -Path $cmdRunner -Value "@start /b powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherPs`""
        }
        Write-Host "[6/6] Тихий автозапуск добавлен в папку Автозагрузка Windows." -ForegroundColor Green
    }

    # 2) Реестр Windows (HKCU Run)
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "ClaudeProxyBridge" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherPs`"" -Force | Out-Null
        Write-Host "      [OK] Добавлен ключ автозапуска в реестр (HKCU Run)." -ForegroundColor Green
    } catch {}

    # 3) Служба Планировщика Задач Windows (если запущено от Администратора)
    $isAdmin = $false
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}

    if ($isAdmin) {
        try {
            $nodePath = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
            if (-not $nodePath) { $nodePath = "C:\Program Files\nodejs\node.exe" }
            $bridgeJs = Join-Path $userBinDir "claude_proxy_bridge.js"

            $action = New-ScheduledTaskAction -Execute $nodePath -Argument "`"$bridgeJs`"" -WorkingDirectory $userBinDir
            $trigStartup = New-ScheduledTaskTrigger -AtStartup
            $trigLogon = New-ScheduledTaskTrigger -AtLogOn
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
            Register-ScheduledTask -TaskName "ClaudeProxyBridge" -Action $action -Trigger @($trigStartup, $trigLogon) -Settings $settings -Description "Claude Code Proxy Bridge (Auto-Start)" -Force | Out-Null
            Write-Host "      [OK] Служба в Планировщике Задач (AtStartup + AtLogOn) зарегистрирована." -ForegroundColor Green
        } catch {
            Write-Host "      Предупреждение при настройке Task Scheduler: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# 7. Запуск служб прямо сейчас
Write-Host "`nЗапуск фоновых служб прямо сейчас..." -ForegroundColor Cyan
$startScript = Join-Path $userBinDir "start_proxy.ps1"
& $startScript

Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host " Установка Claude Code Proxy успешно завершена!" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host " Доступные команды:" -ForegroundColor Cyan
Write-Host "   claude                  - запуск Claude Code CLI из любого места" -ForegroundColor White
Write-Host "   status.cmd              - проверка работы и диагностика служб" -ForegroundColor White
Write-Host "   stats.cmd               - просмотр логов аудита и трафика" -ForegroundColor White
Write-Host "   gui.cmd                 - включить проксирование для приложения Claude Desktop (GUI)" -ForegroundColor White
Write-Host "   start.cmd               - ручной запуск прокси-моста и наблюдателя" -ForegroundColor White
Write-Host "   stop.cmd                - остановка фоновых служб" -ForegroundColor White
Write-Host "=========================================================" -ForegroundColor Cyan

# SIG # Begin signature block
# MIIcyAYJKoZIhvcNAQcCoIIcuTCCHLUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCuqS854UrhIE17
# UVRE1E0gggGJ3ybtlvrgIG7OtN7jHaCCFs4wggOQMIICeKADAgECAhA+YjK6lN32
# uE3ze+6PK4OaMA0GCSqGSIb3DQEBCwUAMGAxKTAnBgkqhkiG9w0BCQEWGnNlb3dp
# emFyZC5hbmRyZXlAZ21haWwuY29tMRowGAYDVQQKDBFDbGF1ZGUgQ29kZSBQcm94
# eTEXMBUGA1UEAwwOQW5kcmV5IFNva29sb3YwHhcNMjYwOTIyMTIwOTMxWhcNMzYw
# OTIyMTIxOTI3WjBgMSkwJwYJKoZIhvcNAQkBFhpzZW93aXphcmQuYW5kcmV5QGdt
# YWlsLmNvbTEaMBgGA1UECgwRQ2xhdWRlIENvZGUgUHJveHkxFzAVBgNVBAMMDkFu
# ZHJleSBTb2tvbG92MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1GAM
# DgyruxehdijIKJK6MAEUg6l89i7SHfHLN7MlyDk5hdoYrX6XlwDmyfktsC4uOjeq
# QpLIkO013KsR1Wbxw6L/ESSnJ7V81BYhHPQ1NUf/vGq4p3Uzp85VLlovesXpVx4x
# S+qfhpGeLfJkt8B0VjA1XNbChcENGhpP0kvRptb77IkslNAgAz2VwZ7+KRLGyCqE
# oRDXtD2CahFEwxBfevWzUrjpJk1U4BveAHZC14XC+SEwD6eXJY/ZMyMPpo7RGcw5
# bfdq2CfbXG0UAd1+R01KtP0pVBqdMyIZ8rXOcpd1HECSSMwM3knriLvGFfHnHk5Q
# sX7cM/R12JuJuBuceQIDAQABo0YwRDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAww
# CgYIKwYBBQUHAwMwHQYDVR0OBBYEFGlvgOhYpVYNF5asQ6wl85aIOGalMA0GCSqG
# SIb3DQEBCwUAA4IBAQARVfEJpSWqCzDsUNwchZix1BF36PsW2eVyO5gWrtzTCnIb
# xzYVls3pBta9SzaEAAx7SZVyDu++LUSqMGUywHaFAzJFETxSqHXJsca7hccjZQFr
# UhfS1RCJsq/Mfw6WkxV5Rj0J10yp0Z3rf53xOpPBGi/49tcMsGDvB4r0OWkLC7Wa
# kpeIns7jLCOn9y7H2NOcArWYXLOR51HE0azx2R6IFIBWibFTkpSLJbJVS4uGpw4N
# juW1uEQNEn4BCYqmx76wXAKQqWiFV+ZlixRA/68GXxwx7VO00Yct7RHDdH+Yzx1T
# YEKvxZpBQAEs0BEhFdQLWqs9I81iiQ21sZyCOu5VMIIFjTCCBHWgAwIBAgIQDpsY
# jvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMG
# A1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQw
# IgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAw
# MDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57
# G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9o
# k3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFh
# mzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463J
# T17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFw
# q1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yh
# Tzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU
# 75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LV
# jHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJ
# bOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8Qg
# UWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IB
# OjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6
# mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/
# BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3Au
# ZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2Vy
# dC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4
# oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJv
# b3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBw
# oL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0
# E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtD
# IeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlU
# sLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFig
# DkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwY
# w02fc7cBqZ9Xql4o4rmUMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMiDDpJhjAN
# BgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2Vy
# dCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0MjM1OTU5
# WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNV
# BAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQwOTYgU0hB
# MjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtHgx
# 0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxCqvkbsDpz
# 4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qchUP+AbdJ
# gMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbDhAktVJMQ
# bzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pnYJU3Gmq6
# bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI2Wv82wnJ
# RfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS638ZxqU1
# 4lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZxst7VvwDD
# jAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17yVp2NL+cn
# T6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTnYCTKIsDq
# 1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4yUozZtqg
# PrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZMBIGA1Ud
# EwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ7MtOMB8G
# A1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjAT
# BgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYD
# VR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9
# bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0pn/N0IfF
# iBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN2n7Jd2E4
# /iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a+Z1jEMK/
# DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7pGdogP8HR
# trYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZruMvNYY2
# o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspIHBldNE2K
# 9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku/qjTY6hc
# 3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZZd/BdHLi
# Ru7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeukcyIPbAv
# jSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA6TD8dC3J
# E3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvFoW2jNrbM
# 1pD2T7m3XDCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJKoZIhvcN
# AQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEw
# PwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2
# IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQyMzU5NTla
# MGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7MDkGA1UE
# AxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3BvbmRlciAy
# MDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6byyf7NSvjU
# m0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuFgGsA31N2
# D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnDdAElETC+bhSEvNLGbA8D
# twUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf2Cros1cz
# RSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05prGV0fkjG
# 426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa+E2ujI91EZtu
# kGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN96LV/mxU
# bCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ecmtJuXaB/
# 0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p16UDTLtT0
# +aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfuXkNNhg8M
# tDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJZGUL8N/pL971DyLXcK6H
# M5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0TAQH/BAIw
# ADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgwFoAU729T
# SunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB/wQMMAoG
# CCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0MDk2
# U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL2NybDMu
# ZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5nUlNBNDA5
# NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG
# /WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECxa9Ji8sEi
# 2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dqLOYqQwst+UQQoNlDHgKR
# La3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn/Fo+FDYA
# HWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3flbDwK+hg
# GMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8aWsD7RkcmgVRs6vlIk3z
# PKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42ox7oNgC/
# r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZTgiy2HLEH
# klpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywpEWFZ4QNg+9xS43tTuW9x
# 0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L3joiQSPs
# WRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TIe0H4ngCI
# 1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0RgsmrX/EdYUo80r
# 3TfMlkD0/YMxggVQMIIFTAIBATB0MGAxKTAnBgkqhkiG9w0BCQEWGnNlb3dpemFy
# ZC5hbmRyZXlAZ21haWwuY29tMRowGAYDVQQKDBFDbGF1ZGUgQ29kZSBQcm94eTEX
# MBUGA1UEAwwOQW5kcmV5IFNva29sb3YCED5iMrqU3fa4TfN77o8rg5owDQYJYIZI
# AWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0B
# CQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAv
# BgkqhkiG9w0BCQQxIgQgM8FdI76DcD/WQUncCypThvkXp7CROKiedkpMRvbgj4cw
# DQYJKoZIhvcNAQEBBQAEggEAiL38W9VTJ7t6PLOpyXRjACLfwk2mXjdfbvF3O+49
# B11GWZdiub/pWXDmcB1tITQ3XgzvCwbU0LqVsQSqyTIlYJ1ZS7LXk2j8lGPlOvNf
# xj5QVCUEi5wJbVsOxuYn6OkpmFVJNiERy7bYRNPFPbqT98gVL+uYA/rDBIDwEauP
# XkT4L+dzBffnUsmm1dXoFk/wvZgkYiRvslqEBhW44O77i+HT5Lf6gH4E1gLCm/zA
# uaAgCWgq4/u4bjtAk9Myfxs20g9c3xokZGw/mZ6lDfr9zx6nWPChUmfn2P3HKhV3
# t8dOc6h/fAyDDkCAe5IHj4DrWxDi9ofnkEz5hDQ17k7SuqGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjA5MjIxMzE5NTZaMC8GCSqGSIb3DQEJBDEiBCAEZN7k1iO2
# sQNlo8vta+h+TcIKWhXjn57FnBYNuZUf0DANBgkqhkiG9w0BAQEFAASCAgBAsBq2
# sUO8ZXsvSk4Y0aTwshDbHLFsDo+zWC0DYzCId0iLWm48gvDyqrsdyUJYLhsbyUIa
# kuixPfV/hLkX7R0jMsOj8OADHHyPdF5fhnQy0/a6yIzKanXz2D4vEnWd7vRRQa5r
# KN8bQxTkcCdH7z9PwkhauUSLPxMSMP+NkViBN1Sqo3PxR8gE77PLGUMTkHhZczL1
# iSRYBgwSlL2Pkzlq4kBzxekstM2RAySbZ+aXollh1n1Rkvh+btjrvsDW3Z4fk81M
# gPdPqoPyj9vDCUxQdj2HEJ3AltSEjTUjA1gqAMNgGmq4tIpi/0gdLAXYXHAWHjtc
# kdwcY1DBf9qrOZeROLfdZ5C7GTQnP4Z1WeXUaUxOe0AaP9a1Kn2zG2xaush/nvy0
# v5ngFYRsodRrAB6Z2SvX+xrlJYbPE+wh2NZyLCzU1YotQqHDTKoU+4BiV1Ec5Aho
# 542LnqkIClnjIGNHh32ki+Ny+8JDga1ER+g1h4H5dGvJt2+K5ZMmSPIMjNyk3Mng
# Urkxe7STmKPuvBePA/pGtdXfKrsSwcispJk/X4ag+j5IJMhSYmepr2A30FdhV5Oz
# IhFDFI3CU1y5F+daS02J575mim7sN+rGb3q2jRXBILCcJ52oFAlm5LgDX18WAuFp
# bLOomTW1gVU624bHcpdCt85CQY+x5JA8mfhcNg==
# SIG # End signature block
