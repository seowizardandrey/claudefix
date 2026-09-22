# install.ps1 - Fast Web / One-Liner Installer for Claude Code Proxy (Windows)
# Developer: Andrey Sokolov (seowizard.andrey@gmail.com)
# Web: https://github.com/seowizardandrey/claudefix
# Usage:
#   irm https://raw.githubusercontent.com/seowizardandrey/claudefix/main/windows/install.ps1 | iex
# Or with parameters:
#   & ([ScriptBlock]::Create((irm https://raw.githubusercontent.com/seowizardandrey/claudefix/main/windows/install.ps1))) -Proxy "socks5://user:pass@host:port"

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Proxy = "",
    [int]$Port = 19000,
    [switch]$Uninstall,
    [switch]$NoPrompt
)

$ErrorActionPreference = "Stop"

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host " Claude Code Proxy & Auto-Patcher (Windows)" -ForegroundColor Cyan
Write-Host " Developer: Andrey Sokolov (seowizard.andrey@gmail.com)" -ForegroundColor Cyan
Write-Host " Repository: https://github.com/seowizardandrey/claudefix" -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host ""

$baseGitHub = "https://raw.githubusercontent.com/seowizardandrey/claudefix/main/windows"
$isAdmin = $false
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {}

$installDir = if ($isAdmin) {
    Join-Path $env:ProgramData "claude-proxy\bin"
} else {
    Join-Path $env:LOCALAPPDATA "Programs\Claude Code Proxy"
}
$configDir = Join-Path $env:USERPROFILE ".config\claude-proxy"

if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

# 1. Handle Uninstall
if ($Uninstall) {
    Write-Host "[UNINSTALL] Removing Claude Code Proxy..." -ForegroundColor Yellow
    $setupExe = Join-Path $installDir "setup.exe"
    if (Test-Path $setupExe) {
        & $setupExe --uninstall
    } else {
        Write-Host "Setup executable not found at $setupExe. Cleaning registry and startup..." -ForegroundColor Yellow
        # Kill running processes
        Stop-Process -Name "ClaudeProxyPatcher", "gost" -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[OK] Claude Code Proxy removed." -ForegroundColor Green
    return
}

# 2. Acquire SOCKS5 Proxy
$proxyEnv = Join-Path $configDir "proxy.env"
if ([string]::IsNullOrWhiteSpace($Proxy) -and (Test-Path $proxyEnv)) {
    try {
        Get-Content $proxyEnv | ForEach-Object {
            $line = $_.Trim()
            if ($line -like "SOCKS5_PROXY=*") {
                $Proxy = $line.Substring("SOCKS5_PROXY=".Length).Trim()
            }
        }
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($Proxy) -and (-not $NoPrompt)) {
    Write-Host "[?] Введите адрес вашего внешнего SOCKS5 прокси:" -ForegroundColor Yellow
    Write-Host "    Пример: socks5://user:password@host:port или socks5://host:port" -ForegroundColor Gray
    Write-Host "    > " -ForegroundColor Cyan -NoNewline
    $Proxy = [Console]::ReadLine()
}

if ([string]::IsNullOrWhiteSpace($Proxy)) {
    Write-Host "[ERROR] SOCKS5 прокси не указан. Запустите скрипт с параметром -Proxy 'socks5://...'" -ForegroundColor Red
    return
}

$Proxy = $Proxy.Trim()
if (-not ($Proxy -like "socks5://*" -or $Proxy -like "socks5h://*")) {
    $Proxy = "socks5://" + $Proxy
}

Write-Host "`n[1/4] Скачивание компонентов Claude Code Proxy..." -ForegroundColor Cyan

$filesToDownload = @(
    "setup.exe",
    "ClaudeProxyPatcher.exe",
    "gost.exe",
    "claude_wrapper.exe",
    "bypass.conf",
    "app.ico",
    "ClaudeProxy.cer",
    "patch.cmd",
    "status.cmd",
    "start.cmd",
    "stop.cmd",
    "uninstall.cmd"
)

# If running from a local git repository, copy local files instead of web downloading
$localDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$useLocal = ($localDir -and (Test-Path (Join-Path $localDir "setup.exe")) -and (Test-Path (Join-Path $localDir "ClaudeProxyPatcher.exe")))

foreach ($fn in $filesToDownload) {
    $dest = Join-Path $installDir $fn
    Write-Host "  - $fn... " -NoNewline
    if ($useLocal) {
        Copy-Item -Path (Join-Path $localDir $fn) -Destination $dest -Force
        Write-Host "[OK (Local)]" -ForegroundColor Green
    } else {
        $url = "$baseGitHub/$fn"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 30
            Write-Host "[OK (Web)]" -ForegroundColor Green
        } catch {
            Write-Host "[FAILED: $($_.Exception.Message)]" -ForegroundColor Red
            throw
        }
    }
}

# 3. Strip Mark of the Web & Register Certificate
Write-Host "`n[2/4] Подготовка системы и доверия..." -ForegroundColor Cyan
Get-ChildItem -Path $installDir -Recurse | Unblock-File -ErrorAction SilentlyContinue

$cerPath = Join-Path $installDir "ClaudeProxy.cer"
if (Test-Path $cerPath) {
    try {
        certutil -user -addstore -f "Root" $cerPath >$null 2>&1
        certutil -user -addstore -f "TrustedPublisher" $cerPath >$null 2>&1
        if ($isAdmin) {
            certutil -addstore -f "Root" $cerPath >$null 2>&1
            certutil -addstore -f "TrustedPublisher" $cerPath >$null 2>&1
        }
        Write-Host "  [OK] Сертификат Andrey Sokolov зарегистрирован в доверенных издателях." -ForegroundColor Green
    } catch {}
}

# Add installDir to user PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$installDir;$userPath", "User")
    $env:PATH = "$installDir;$env:PATH"
    Write-Host "  [OK] Папка $installDir добавлена в переменную PATH пользователя." -ForegroundColor Green
}

# 4. Run Setup Engine
Write-Host "`n[3/4] Выполнение автоматической настройки и патчинга..." -ForegroundColor Cyan
$setupExe = Join-Path $installDir "setup.exe"
$setupArgs = "`"$Proxy`" --port $Port"
$process = Start-Process -FilePath $setupExe -ArgumentList $setupArgs -Wait -NoNewWindow -PassThru

if ($process.ExitCode -eq 0) {
    Write-Host "  [OK] Базовая настройка успешно завершена." -ForegroundColor Green
} else {
    Write-Host "  [WARNING] Установщик вернул код $($process.ExitCode)." -ForegroundColor Yellow
}

# 5. Launch Claude Proxy Manager
Write-Host "`n[4/4] Запуск графического менеджера (System Tray)..." -ForegroundColor Cyan
$managerExe = Join-Path $installDir "ClaudeProxyPatcher.exe"
if (Test-Path $managerExe) {
    Start-Process -FilePath $managerExe
    Write-Host "  [OK] Claude Proxy Manager запущен в системном трее." -ForegroundColor Green
}

Write-Host "`n==============================================================" -ForegroundColor Green
Write-Host " Установка Claude Code Proxy успешно завершена!" -ForegroundColor Green
Write-Host "==============================================================" -ForegroundColor Green
Write-Host " Управление и статус:" -ForegroundColor Cyan
Write-Host "   - Иконка в системном трее (рядом с часами Windows)" -ForegroundColor White
Write-Host "   - Ярлык на Рабочем столе: Claude Proxy Manager" -ForegroundColor White
Write-Host "   - Команда статуса в терминале: status.cmd" -ForegroundColor White
Write-Host "   - Проверка Claude в терминале: claude --version" -ForegroundColor White
Write-Host ""

# SIG # Begin signature block
# MIIcyAYJKoZIhvcNAQcCoIIcuTCCHLUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB+BuBseVclbdbM
# 0sMtdCkJGJ+5Hu82fo/HwmdtyY6NTqCCFs4wggOQMIICeKADAgECAhA+YjK6lN32
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
# BgkqhkiG9w0BCQQxIgQgoFB5FD/6HGi+3zH8TDikFECOOJX3/7yb+7utiDYOO40w
# DQYJKoZIhvcNAQEBBQAEggEAezEOLEYMYkw0pSl0B9CCsLGbDJIj8or97Ve2r/VU
# 2BEQohnA2Up93gZ7Ov6JVCNaQWICYc3vTIIESq6WVcuDGwz9fq8MPtiMHOJPqZ6d
# u7IT2y4B/pfZojSIdrZE4pq+UGYr7yOIzAnmGDbE7JVQ0vxFrHSgZHnt8Iwf2noI
# jbMeIuj+PGp/UIOiZKxjkKOCtWDb9uF2Vc+OXRk4L0QEBDxbdtwNsXDRHIMR13Vd
# ZgWXT9HgjfBy4mydE3frBH9s5iO2+oziQJxqArtlcqCi6/ELQiDb8rUwW3PZ337b
# HPWEGicQK6P2RE6fdNNfUMzicVprd80h+gUKfQv2h+rtVKGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjA5MjIxMzE5NTZaMC8GCSqGSIb3DQEJBDEiBCAxx907qOyH
# 0iAy114UfMcxd9cTEI0EaUNppA8id9w4nDANBgkqhkiG9w0BAQEFAASCAgA/Ipax
# qj8EGHXLe+MOi3XFGH8JUKT6iJnqAe5sSp/VjJJGHbNvofw+7s5P0CPHOGnLqiDw
# 1tmCC6gwOP6hr08ler2vkYpzKqT1TSeAZ0CO5RtkwD/e0XTEQbLw8SY9qjnrL4h8
# znM7miGduiQidDLSpluFOoismbNLU57G4F2zk0HiE7IifKyCFib0ZRMjlmgfzfEV
# URR+nx3huwmjej2B6A1pq5ne5s5Y+rauoi04mcEZcu/B3HG4Ahi56GyNlNf8n63i
# uAwWb6XcAoXLojWFyzC5LJzSZ7Okj5cPyazy6lbLtSEYclbeux9EJYx0AA+vvDql
# 5R2T3rrYLhirADb8fFQtT58pfBEHvRnoYPPJSlyU6GuSruwEW1QPYbm8uH9A5xb0
# wOX5fBkbWos5yCHfETaq1MrFeOoFR5ZVFfvK+Z4uwVCs6Pd7nfEdkAdl+ipLbKel
# zLBnIPMhSEKWdvTsx/DbisepQfxxLG05DC9iT4fPtfJTI4FiTEk8S9HpyVYmYOb+
# PZ/7ZfJ6P87Wcbytzig4AK8dB0HrmzplkcQ+4QdccajC8JTbPhymVBU3s3eywHug
# z9HMDZU4PRR/0wwzhE3V15hiMoBLx+6Km/iOsBnsCVs1GhHyp/6Jmv2RL5gfrKvG
# L6wtrWnd0t4BKGj34rDKo6pCOeQE8CGeJ2+kTg==
# SIG # End signature block
