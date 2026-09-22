# start_proxy.ps1 - Запуск прокси-моста и автопатчера Claude Code в фоновом режиме на Windows
# Part of Claude Code Proxy Toolkit

$ErrorActionPreference = "Continue"

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ScriptDir -or -not (Test-Path $ScriptDir)) {
    $ScriptDir = Join-Path $env:USERPROFILE ".config\claude-proxy\bin"
}

$ConfigDir = Join-Path $env:USERPROFILE ".config\claude-proxy"
if (-not (Test-Path $ConfigDir)) {
    New-Item -Path $ConfigDir -ItemType Directory -Force | Out-Null
}

$ConfigFile = Join-Path $ConfigDir "proxy.env"
$ProxyPort = 19000

if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
            $parts = $line.Split("=", 2)
            if ($parts[0].Trim() -eq "PROXY_PORT") {
                $ProxyPort = [int]$parts[1].Trim().Trim('"').Trim("'")
            }
        }
    }
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " Запуск служб Claude Code Proxy (Windows)" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Проверка, не слушает ли уже порт
$alreadyListening = $false
try {
    $conn = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $ProxyPort -State Listen -ErrorAction SilentlyContinue
    if ($conn) { $alreadyListening = $true }
} catch {}

if ($alreadyListening) {
    Write-Host "[bridge] Прокси-мост уже запущен и слушает порт $ProxyPort." -ForegroundColor Green
} else {
    Write-Host "[bridge] Запуск прокси-моста на порту $ProxyPort..." -ForegroundColor Cyan

    # Поиск файла скрипта моста
    $bridgeScript = Join-Path $ScriptDir "claude_proxy_bridge.js"
    if (-not (Test-Path $bridgeScript)) {
        $candidatePaths = @(
            (Join-Path $ConfigDir "bin\claude_proxy_bridge.js"),
            (Join-Path $env:USERPROFILE "Downloads\claudefix-main\claudefix-main\windows\claude_proxy_bridge.js"),
            (Join-Path (Get-Location) "claude_proxy_bridge.js"),
            (Join-Path (Get-Location) "windows\claude_proxy_bridge.js")
        )
        foreach ($cand in $candidatePaths) {
            if (Test-Path $cand) { $bridgeScript = $cand; break }
        }
    }

    # Поиск node.exe
    $nodePath = ""
    $nodeCmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $nodePath = $nodeCmd.Source
    } else {
        $commonNodePaths = @(
            "C:\Program Files\nodejs\node.exe",
            "C:\Program Files (x86)\nodejs\node.exe",
            "$env:LOCALAPPDATA\Programs\nodejs\node.exe",
            "$env:APPDATA\nvm\current\node.exe"
        )
        foreach ($p in $commonNodePaths) {
            if (Test-Path $p) { $nodePath = $p; break }
        }
    }

    $bridgeOutLog = Join-Path $ConfigDir "bridge.log"
    $bridgeErrLog = Join-Path $ConfigDir "bridge_err.log"

    if ($nodePath -and (Test-Path $bridgeScript)) {
        $bridgeDir = Split-Path -Parent $bridgeScript
        Start-Process -FilePath $nodePath `
            -ArgumentList "`"$bridgeScript`"" `
            -WorkingDirectory $bridgeDir `
            -RedirectStandardOutput $bridgeOutLog `
            -RedirectStandardError $bridgeErrLog `
            -WindowStyle Hidden
    } else {
        # Fallback на Python
        $pyBridge = Join-Path $ScriptDir "claude_proxy_bridge.py"
        if (-not (Test-Path $pyBridge)) {
            $pyBridge = Join-Path $ConfigDir "bin\claude_proxy_bridge.py"
        }
        $pyCmd = Get-Command pythonw.exe -ErrorAction SilentlyContinue
        if (-not $pyCmd) { $pyCmd = Get-Command python.exe -ErrorAction SilentlyContinue }

        if ($pyCmd -and (Test-Path $pyBridge)) {
            $bridgeDir = Split-Path -Parent $pyBridge
            Start-Process -FilePath $pyCmd.Source `
                -ArgumentList "`"$pyBridge`"" `
                -WorkingDirectory $bridgeDir `
                -RedirectStandardOutput $bridgeOutLog `
                -RedirectStandardError $bridgeErrLog `
                -WindowStyle Hidden
        } else {
            Write-Error "Ошибка: Не найден node.exe или файл claude_proxy_bridge.js!"
            Write-Host "Проверьте путь: $bridgeScript" -ForegroundColor Red
        }
    }

    # Ожидание открытия порта до 5 секунд
    $started = $false
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        $conn = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $ProxyPort -State Listen -ErrorAction SilentlyContinue
        if ($conn) { $started = $true; break }
    }

    if ($started) {
        Write-Host "[bridge] [OK] Прокси-мост успешно поднят на http://127.0.0.1:$ProxyPort" -ForegroundColor Green
    } else {
        Write-Host "[bridge] Предупреждение: Порт $ProxyPort не открылся в течение 5 секунд." -ForegroundColor Yellow
        if (Test-Path $bridgeErrLog) {
            $errs = Get-Content $bridgeErrLog -ErrorAction SilentlyContinue
            if ($errs) {
                Write-Host "[bridge] Ошибка из лога ($bridgeErrLog):" -ForegroundColor Red
                $errs | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            }
        }
    }
}

# 2. Проверка и запуск Watcher
$watcherProc = Get-CimInstance Win32_Process -Filter "CommandLine LIKE '%claude_watcher%'" -ErrorAction SilentlyContinue
if ($watcherProc) {
    Write-Host "[watcher] Фоновый автопатчер (watcher) уже активен." -ForegroundColor Green
} else {
    Write-Host "[watcher] Запуск фонового автопатчера (watcher)..." -ForegroundColor Cyan
    $watcherScript = Join-Path $ScriptDir "claude_watcher.ps1"
    if (-not (Test-Path $watcherScript)) {
        $watcherScript = Join-Path $ConfigDir "bin\claude_watcher.ps1"
    }

    if (Test-Path $watcherScript) {
        $watcherOutLog = Join-Path $ConfigDir "watcher.log"
        $watcherErrLog = Join-Path $ConfigDir "watcher_err.log"
        $watcherDir = Split-Path -Parent $watcherScript
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watcherScript`"" `
            -WorkingDirectory $watcherDir `
            -RedirectStandardOutput $watcherOutLog `
            -RedirectStandardError $watcherErrLog `
            -WindowStyle Hidden
        Write-Host "[watcher] [OK] Автопатчер запущен в фоновом режиме." -ForegroundColor Green
    }
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " Проверка завершена." -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan

# SIG # Begin signature block
# MIIcyAYJKoZIhvcNAQcCoIIcuTCCHLUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBwosFnow8Dij2v
# J/3DXYTutrbkzAmuxHCxEJLeOnloR6CCFs4wggOQMIICeKADAgECAhA+YjK6lN32
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
# BgkqhkiG9w0BCQQxIgQgZJg67gjGa+TJJWer4gtM5nPKRsTyC5jT3FyXOZR0IBMw
# DQYJKoZIhvcNAQEBBQAEggEACJ4oJogIXtGCXFkifX71mLGLmoT5nXgqXhJbBnj0
# WMjgFUUB3GPCUdrKymUZb+rxEX23fnEkeTPSfnINkHcz0r6V5DwzGZt0DJ3YqmwQ
# iHSPyTnIFG2Kk489a00J+nZaSK32lbnPZnn8JbKAaADnSmuMVXoGmOZqv81Sm2Xk
# MXMKkF53nFgTsAD0jzCcj80SiQ1aNiIaBe/vwSWOLp2E0sePsCRioqB2dOQOz4n0
# NMUjBBhLuyenkjKDI4TFZUxAHgN6Ekb1tCeuVBM0UNS49iZ4fhOpwHH76GO+bZCx
# uQwfE3Rt7IS0TQMTAxH1fh89DmzM8WT42vhYjM7v7MtItqGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjA5MjIxMzE5NTdaMC8GCSqGSIb3DQEJBDEiBCDkP0lhVOVD
# vQv0FG4bUhuqHTEf044HB8wX0UWS002IMjANBgkqhkiG9w0BAQEFAASCAgCPViiO
# 87/F4FA62pZJZ6rDu3EziiOQrsYcb6TQX7CE6DSFBA0bkX/cPGV1yPyK1bHqzp/z
# U9Jd0LsdPAuVT1RxX/ZZyZ8rk/TINc4pKZMwcPZa5+mxqACubtIp/pL0BUKPs5/K
# cmB14GfakTIYUBHJ3lSs+jEs0EfU4DzzoJ1Llr5TdFIGGRhxe9uzlDueQH+X/As2
# YgAEb3lonIqdN0ZmtHjbw1pyKqu7WUIXbNLNdA509OLWa6+eR2xoeAmCOSK2BaUB
# 5c7NljymxV1WrrlVFXKMON/WageHPShsif3R7FYnIZ7YlGirhNedrEcKfKZ5jAm0
# 9Kz8/k53dq2yct50mkFzXacWZ1A2HN9K300JCJTVeObrJR9sX7ij4Bd+XhmDDpqv
# pt+pm0PBBaErfvbcp3KcglHyWDzjzYVrfSPGunAXSyGIoQtcv2DIBjZ1Svne9pwz
# IWBbmf2w2Etpp7k7qB2x5Dv2GQxHG+Z21lrnVJFgPuk1bH5OFAK6hAUfNS5QrZLw
# +iriAywteIzDqaKuzxpQnzYA92RBw5MXCBhiab+Su/CqR8NzsXuKWs3zohVW3EBG
# RZhMHuz3PHAlIxF7U7dPUrYgl5jSHQdrlpZsKTwd7ILUaeWVaLdEQoXrmGXP58or
# xfw0DYayeAhqBqi3dchOirckNEuWiCwqvrFu6w==
# SIG # End signature block
