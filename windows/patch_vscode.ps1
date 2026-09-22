# patch_vscode.ps1 - Direct VS Code Claude Code Extension Patcher & Binary Sync
# Part of Claude Code Proxy Toolkit

[CmdletBinding()]
param(
    [int]$ProxyPort = 19000
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$WrapperCs = Join-Path $ScriptDir "claude_wrapper.cs"
$WrapperExe = Join-Path $ScriptDir "claude_wrapper.exe"

# 1. Read proxy port from config if available
$ConfigFile = Join-Path $env:USERPROFILE ".config\claude-proxy\proxy.env"
if (Test-Path $ConfigFile) {
    Get-Content $ConfigFile | ForEach-Object {
        $l = $_.Trim()
        if ($l -and -not $l.StartsWith("#") -and $l.Contains("=")) {
            $p = $l.Split("=", 2)
            if ($p[0].Trim() -eq "PROXY_PORT") {
                $ProxyPort = [int]$p[1].Trim().Trim('"').Trim("'")
            }
        }
    }
}

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " VS Code Claude Code Extension Auto-Patcher" -ForegroundColor Cyan
Write-Host " Local Proxy: http://127.0.0.1:$ProxyPort" -ForegroundColor Gray
Write-Host "=========================================================" -ForegroundColor Cyan

# 2. Ensure claude_wrapper.exe exists
if (-not (Test-Path $WrapperExe)) {
    Write-Host "[1/4] Compiling claude_wrapper.exe..." -ForegroundColor Cyan
    $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $csc)) {
        $cscCmd = Get-Command csc.exe -ErrorAction SilentlyContinue
        if ($cscCmd) { $csc = $cscCmd.Source }
    }
    if (Test-Path $csc) {
        & $csc /nologo /target:exe /optimize+ /out:"$WrapperExe" "$WrapperCs"
    }
}

if (-not (Test-Path $WrapperExe)) {
    Write-Error "Error: claude_wrapper.exe not found and could not be compiled!"
    exit 1
}
Write-Host "[1/4] claude_wrapper.exe ready: $WrapperExe" -ForegroundColor Green

# 3. Locate the real Anthropic CLI binary
Write-Host "[2/4] Locating official Claude Code binary..." -ForegroundColor Cyan
$realBinary = $null

# Candidate A: versions folder
$versDir = Join-Path $env:USERPROFILE ".local\share\claude\versions"
if (Test-Path $versDir) {
    $found = Get-ChildItem -Path $versDir -Filter "claude.exe" -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.Length -gt 1000000 } | Select-Object -First 1
    if ($found) { $realBinary = $found.FullName }
}

# Candidate B: .local\bin
if (-not $realBinary) {
    $localReal = Join-Path $env:USERPROFILE ".local\bin\claude.real.exe"
    if (Test-Path $localReal) { $realBinary = $localReal }
    else {
        $localExe = Join-Path $env:USERPROFILE ".local\bin\claude.exe"
        if ((Test-Path $localExe) -and ((Get-Item $localExe).Length -gt 1000000)) {
            $realBinary = $localExe
        }
    }
}

# Candidate C: search any claude.real.exe on profile
if (-not $realBinary) {
    $anyReal = Get-ChildItem -Path $env:USERPROFILE -Filter "claude.real.exe" -Recurse -ErrorAction SilentlyContinue |
               Where-Object { $_.Length -gt 1000000 } | Select-Object -First 1
    if ($anyReal) { $realBinary = $anyReal.FullName }
}

# Candidate D: download via proxy if not present
if (-not $realBinary) {
    Write-Host "      Native binary not found locally. Downloading official binary via proxy..." -ForegroundColor Yellow
    $dlDir = Join-Path $env:USERPROFILE ".claude\downloads"
    New-Item -ItemType Directory -Force -Path $dlDir | Out-Null
    $ProxyUrl = "http://127.0.0.1:$ProxyPort"
    $env:HTTP_PROXY = $ProxyUrl
    $env:HTTPS_PROXY = $ProxyUrl
    $PSDefaultParameterValues['*:Proxy'] = $ProxyUrl
    [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy("127.0.0.1", $ProxyPort)
    try {
        $ver = (Invoke-RestMethod -Uri "https://downloads.claude.ai/claude-code-releases/latest" -Proxy $ProxyUrl).Trim()
        $dest = Join-Path $dlDir "claude-$ver-win32-x64.exe"
        Invoke-WebRequest -Uri "https://downloads.claude.ai/claude-code-releases/$ver/win32-x64/claude.exe" -OutFile $dest -Proxy $ProxyUrl
        if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 1000000)) {
            $realBinary = $dest
        }
    } catch {
        Write-Host "      Download failed: $_" -ForegroundColor Red
    }
}

if (-not $realBinary) {
    Write-Error "Error: Unable to locate or download real Anthropic claude.exe binary!"
    exit 1
}

Write-Host "      [OK] Real binary found: $realBinary ($([math]::Round((Get-Item $realBinary).Length/1MB, 2)) MB)" -ForegroundColor Green

# 4. Patch all VS Code extension locations
Write-Host "[3/4] Patching VS Code extensions..." -ForegroundColor Cyan

$extRoots = @(
    (Join-Path $env:USERPROFILE ".vscode\extensions"),
    (Join-Path $env:USERPROFILE ".vscode-insiders\extensions"),
    (Join-Path $env:USERPROFILE ".cursor\extensions"),
    (Join-Path $env:USERPROFILE ".windsurf\extensions")
)

$extensionCount = 0
foreach ($root in $extRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -Path $root -Directory -Filter "anthropic.claude-code-*" | ForEach-Object {
        $extDir = $_.FullName
        Write-Host "      Target Extension: $($_.Name)" -ForegroundColor Yellow

        $subDirs = @(
            (Join-Path $extDir "resources\native-binary"),
            (Join-Path $extDir "resources\native-binaries\win32-x64")
        )

        foreach ($dir in $subDirs) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }

            $targetReal = Join-Path $dir "claude.real.exe"
            $targetExe = Join-Path $dir "claude.exe"

            # 1. Copy real binary to claude.real.exe
            if (-not (Test-Path $targetReal) -or ((Get-Item $targetReal).Length -lt 1000000)) {
                Copy-Item -Path $realBinary -Destination $targetReal -Force
                Write-Host "      [OK] Deployed claude.real.exe -> $dir" -ForegroundColor Green
            }

            # 2. Deploy wrapper as claude.exe
            Copy-Item -Path $WrapperExe -Destination $targetExe -Force
            Write-Host "      [OK] Deployed claude.exe (wrapper) -> $dir" -ForegroundColor Green
        }
        $extensionCount++
    }
}

if ($extensionCount -eq 0) {
    Write-Host "      [WARN] No anthropic.claude-code-* extension directory found in .vscode/extensions!" -ForegroundColor Yellow
} else {
    Write-Host "      [OK] Successfully patched $extensionCount VS Code extension(s)." -ForegroundColor Green
}

# 5. Configure VS Code proxy settings (settings.json)
Write-Host "[4/4] Configuring VS Code proxy settings..." -ForegroundColor Cyan
$settingsPaths = @(
    (Join-Path $env:APPDATA "Code\User\settings.json"),
    (Join-Path $env:APPDATA "Code - Insiders\User\settings.json"),
    (Join-Path $env:APPDATA "Cursor\User\settings.json"),
    (Join-Path $env:APPDATA "Windsurf\User\settings.json")
)

foreach ($sf in $settingsPaths) {
    $parent = Split-Path -Parent $sf
    if (Test-Path $parent) {
        try {
            $settings = @{}
            if (Test-Path $sf) {
                $raw = Get-Content $sf -Raw -ErrorAction SilentlyContinue
                if ($raw) { $settings = $raw | ConvertFrom-Json }
            }
            $settings | Add-Member -NotePropertyName "http.proxy" -NotePropertyValue "http://127.0.0.1:$ProxyPort" -Force
            $settings | Add-Member -NotePropertyName "http.proxySupport" -NotePropertyValue "override" -Force
            $settings | ConvertTo-Json -Depth 10 | Set-Content $sf -Encoding UTF8
            Write-Host "      [OK] Proxy configured in: $sf" -ForegroundColor Green
        } catch {
            Write-Host "      Note: Unable to update $sf: $_" -ForegroundColor Gray
        }
    }
}

Write-Host "`n=========================================================" -ForegroundColor Green
Write-Host " VS Code Claude Code Extension successfully patched!" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
Write-Host " Please reload VS Code:" -ForegroundColor White
Write-Host "   Press Ctrl+Shift+P -> Developer: Reload Window" -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Cyan

# SIG # Begin signature block
# MIIcyAYJKoZIhvcNAQcCoIIcuTCCHLUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC9ffObFrk/15D/
# WVXK8MjEEkNspKNH49a/AOHgL4rOCaCCFs4wggOQMIICeKADAgECAhA+YjK6lN32
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
# BgkqhkiG9w0BCQQxIgQgF30LVZjNKGwz5hqnQpYcYqqUZPQ2ealX6WwLaOg3+dgw
# DQYJKoZIhvcNAQEBBQAEggEAje179D0wwiI7v4Yv9+Tw97e/DkR4ba0szXSIQ9cg
# F2+Pw+i/0uQq9Tzz9lZcIvgAExNXSMe9C7JVPIb9LDucidE12KiNqH+EvdkNCWZa
# amiVgcQmWL6v5pyew4V3zZ6cqV9v4l29u/hmF6x0mVD/HPwqN+9ljUwhuDtDncmC
# 3p7/0GlhgzG23yPFMf46viuTPqTEu2u3pJkWW3rUP0YbYG6rYSxhy8n9KHCreRnh
# dm5rnVaayieo21uGIzOqF1y975zAIn09rip9It3dKunkrca6bkJemuUlZptO6R2N
# J0AejvnMU6cI//VTXZejA8UHdyJ0Dy6zna9AdXHsW8XbEqGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjA5MjIxMzE5NTZaMC8GCSqGSIb3DQEJBDEiBCDVTAjUEu/8
# dqfHBA4uRC0Xu3I7EQkwwEAUxPJeQAtPmDANBgkqhkiG9w0BAQEFAASCAgCaio2/
# ddt7Zt56qrPpT4lFai1c7Ra+c7uiTKiQyO4ufY32TSHnhWqqJe1wd/NRuZ6CUGFS
# TAn49IdSNGbCppxj8s/GGb0Oyh7bC/O6xcxkkS3kD0KmD0ECQti+nu/PNiicnBgM
# u2/8AxpRWnbBaX35macRQjtMMLy+6Z1QpJpTHbgtbzy0HYT6T5nR8Vjj8trf6dOV
# j06iFbl4NTY1H+B8Yo9U1a0z6Ac3n3EGE4tjeMgZ7vZZoW+EvuBlegXL2B3SRo7u
# RhgE28aY/BKFfvBu7F/YYWvGLq0zm2flD19hqosZcUFe3DuvibertONx8DhgB4k8
# 2BOOpsHjcggUxjDboPmfYhd/8FOJQuAGi2oTDTJdvsJdxuY2ViVU9/AKGtwytc0y
# yyjlR9q03jKddv09h8RBud8VgQPhZkpxjTXStvYWMlJozlBEwiSxqeO/zuqdpG8C
# QUlnoK2qUKvbFvfStzNyc9QF1/uzAvQ/wiDnWV4q687NO4Ta8a9wvRSgrQ3IWpks
# xPjKaqH54G/Nvvcg33XNfZy4AZO3yVUFF1hEgcIcGKosNuM/J+pUgd0vwsiMLb3X
# unJyitDp5mtrhLeCa1OFC9wXff0G9AX5RbdIbpBK6IMHpRq0TSmiIPhL9ncExFRa
# ZgvtlA7cAl41cX2lC+FSqRWH6aael8e8AacuFg==
# SIG # End signature block
