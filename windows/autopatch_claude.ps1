# autopatch_claude.ps1 - Patch Claude Code binaries (VS Code extension & Standalone CLI) for Windows
# Part of Claude Code Proxy Toolkit

[CmdletBinding()]
param(
    [switch]$Restart,
    [switch]$Restore,
    [switch]$VerboseOutput,
    [string]$CustomPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$WrapperCs = Join-Path $ScriptDir "claude_wrapper.cs"
$WrapperExe = Join-Path $ScriptDir "claude_wrapper.exe"

# 1. Ensure wrapper executable is compiled
if (-not (Test-Path $WrapperExe) -and -not $Restore) {
    Write-Host "[autopatch] claude_wrapper.exe not found. Compiling via csc.exe..." -ForegroundColor Cyan
    $cscPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $cscPath)) {
        $cscCmd = Get-Command csc.exe -ErrorAction SilentlyContinue
        if ($cscCmd) { $cscPath = $cscCmd.Source }
    }
    if (-not (Test-Path $cscPath)) {
        Write-Error "[autopatch] Error: Microsoft .NET C# Compiler (csc.exe) not found!"
        exit 1
    }
    & $cscPath /nologo /target:exe /optimize+ /out:"$WrapperExe" "$WrapperCs"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $WrapperExe)) {
        Write-Error "[autopatch] Error compiling claude_wrapper.cs"
        exit 1
    }
    Write-Host "[autopatch] Successfully compiled $WrapperExe" -ForegroundColor Green
}

# 2. Optionally stop running Claude processes to release file locks
if ($Restart) {
    $running = Get-Process -Name "claude" -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "[autopatch] Stopping running Claude processes to release file locks..." -ForegroundColor Yellow
        Stop-Process -Name "claude" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
}

# 3. Locate real Anthropic binary if available
$globalReal = $null
$versDir = Join-Path $env:USERPROFILE ".local\share\claude\versions"
if (Test-Path $versDir) {
    $found = Get-ChildItem -Path $versDir -Filter "claude.exe" -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.Length -gt 1000000 } | Select-Object -First 1
    if ($found) { $globalReal = $found.FullName }
}
if (-not $globalReal) {
    $localReal = Join-Path $env:USERPROFILE ".local\bin\claude.real.exe"
    if (Test-Path $localReal) { $globalReal = $localReal }
    else {
        $localExe = Join-Path $env:USERPROFILE ".local\bin\claude.exe"
        if ((Test-Path $localExe) -and ((Get-Item $localExe).Length -gt 1000000)) { $globalReal = $localExe }
    }
}

# 4. Find target directories
$targetDirs = @()

$extRoots = @(
    "$env:USERPROFILE\.vscode\extensions",
    "$env:USERPROFILE\.vscode-insiders\extensions",
    "$env:USERPROFILE\.cursor\extensions",
    "$env:USERPROFILE\.windsurf\extensions"
)

foreach ($root in $extRoots) {
    if (Test-Path $root) {
        Get-ChildItem -Path $root -Directory -Filter "anthropic.claude-code-*" | ForEach-Object {
            $b1 = Join-Path $_.FullName "resources\native-binary"
            $b2 = Join-Path $_.FullName "resources\native-binaries\win32-x64"
            if (-not (Test-Path $b1)) { New-Item -ItemType Directory -Path $b1 -Force | Out-Null }
            if (-not (Test-Path $b2)) { New-Item -ItemType Directory -Path $b2 -Force | Out-Null }
            $targetDirs += $b1
            $targetDirs += $b2
        }
    }
}

$cliVersionsDir = "$env:USERPROFILE\.local\share\claude\versions"
if (Test-Path $cliVersionsDir) {
    $targetDirs += $cliVersionsDir
}
$localBinDir = "$env:USERPROFILE\.local\bin"
if (Test-Path $localBinDir) {
    $targetDirs += $localBinDir
}

if ($CustomPath -and (Test-Path $CustomPath)) {
    $targetDirs += $CustomPath
}

$patchedCount = 0
$restoredCount = 0

# 5. Process each directory
foreach ($dir in $targetDirs) {
    $claudeExe = Join-Path $dir "claude.exe"
    $claudeReal = Join-Path $dir "claude.real.exe"

    if ($Restore) {
        if (Test-Path $claudeReal) {
            Write-Host "[autopatch] Restoring original binary at $dir\claude.exe..." -ForegroundColor Cyan
            if (Test-Path $claudeExe) { Remove-Item -Path $claudeExe -Force }
            Move-Item -Path $claudeReal -Destination $claudeExe -Force
            $restoredCount++
        }
        continue
    }

    # Case 1: Both missing, but we have global real binary
    if ((-not (Test-Path $claudeExe)) -and (-not (Test-Path $claudeReal)) -and $globalReal) {
        Copy-Item -Path $globalReal -Destination $claudeReal -Force
        Copy-Item -Path $WrapperExe -Destination $claudeExe -Force
        Write-Host "[autopatch] [OK] Populated missing binary & wrapper in: $dir" -ForegroundColor Green
        $patchedCount++
        continue
    }

    # Case 2: claude.real.exe exists, but claude.exe missing
    if ((Test-Path $claudeReal) -and (-not (Test-Path $claudeExe))) {
        Copy-Item -Path $WrapperExe -Destination $claudeExe -Force
        Write-Host "[autopatch] [OK] Restored missing wrapper at: $claudeExe" -ForegroundColor Green
        $patchedCount++
        continue
    }

    # Case 3: claude.exe exists
    if (Test-Path $claudeExe) {
        $item = Get-Item $claudeExe
        if (-not (Test-Path $claudeReal)) {
            if ($item.Length -gt 1000000) {
                # Initial patch: real binary does not exist yet
                Write-Host "[autopatch] Found original Claude executable ($([math]::Round($item.Length/1MB, 2)) MB) at $claudeExe" -ForegroundColor Cyan
                Move-Item -Path $claudeExe -Destination $claudeReal -Force
                Copy-Item -Path $WrapperExe -Destination $claudeExe -Force
                Write-Host "[autopatch] [OK] Patched $claudeExe -> claude.real.exe + wrapper installed." -ForegroundColor Green
                $patchedCount++
            }
        } else {
            # claude.real.exe exists. Check if claude.exe was overwritten by auto-update (> 1MB)
            if ($item.Length -gt 1000000) {
                Write-Host "[autopatch] Detected updated Claude binary ($([math]::Round($item.Length/1MB, 2)) MB) at $claudeExe" -ForegroundColor Yellow
                Move-Item -Path $claudeExe -Destination $claudeReal -Force
                Copy-Item -Path $WrapperExe -Destination $claudeExe -Force
                Write-Host "[autopatch] [OK] Re-applied wrapper to updated version at $claudeExe" -ForegroundColor Green
                $patchedCount++
            } else {
                # Ensure wrapper is latest compiled version
                $wrapperItem = Get-Item $WrapperExe
                if ($item.LastWriteTime -lt $wrapperItem.LastWriteTime) {
                    Copy-Item -Path $WrapperExe -Destination $claudeExe -Force
                    Write-Host "[autopatch] [OK] Updated wrapper binary at $claudeExe" -ForegroundColor Green
                    $patchedCount++
                } elseif ($VerboseOutput) {
                    Write-Host "[autopatch] Already patched and up-to-date: $claudeExe" -ForegroundColor Gray
                }
            }
        }
    }
}

if ($Restore) {
    Write-Host "[autopatch] Restore complete. Restored $restoredCount binaries." -ForegroundColor Green
} else {
    if ($patchedCount -gt 0) {
        Write-Host "[autopatch] Successfully applied patch to $patchedCount location(s)." -ForegroundColor Green
    } else {
        Write-Host "[autopatch] All Claude Code binaries are already up to date and patched." -ForegroundColor Green
    }
}

# SIG # Begin signature block
# MIIcyAYJKoZIhvcNAQcCoIIcuTCCHLUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCgdPuDIPWvWs9V
# zAkILu2ixYeIxzO/WQZXS6vt1Oq4V6CCFs4wggOQMIICeKADAgECAhA+YjK6lN32
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
# BgkqhkiG9w0BCQQxIgQg6u+gAFZviBe6/yuPt6jEc1zPrKPQQkbRgvnPkvj3ziQw
# DQYJKoZIhvcNAQEBBQAEggEAHFbQrr8FUMopZVjHL/NJ8Nw79HyLW2YKEcJlgrUM
# Nq9hum3dzVfrKluHkqYoNtVqDMY9UxuEtfKRNX3hmLN3FAP6sInSXnCdizaQuUja
# i3TxaW+r4qUKTxGqzCcifHfVfPUXKEhIgxIdEN00VFJCvnP6Zg54gBzZkIpdjNJM
# 9smEi+66OLGJ6IQr1/naVkDM+7N7BvWabKKkpVbPzc5LUbS/YLWPrXkPDl/YwR32
# xCjnUFy9cY39mlg1v5r2hxgDHGt0eTks4LVSNIVKjDk1S1zcgIwtg5Zr2W5082JG
# n5vciLxwmZCnNpjsyX+JbAswmdcNpVTV0JCi+3oTyW2s7qGCAyYwggMiBgkqhkiG
# 9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdp
# Q2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3Rh
# bXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO28MPj/mSGDUw
# DQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcNAQcBMBwGCSqG
# SIb3DQEJBTEPFw0yNjA5MjIxMzE5NTZaMC8GCSqGSIb3DQEJBDEiBCDGiI21IF2e
# PBh7LWYTqF//fTFMpLw1pWbmDmLwd/5T+zANBgkqhkiG9w0BAQEFAASCAgBpBk8/
# eE570gZe/DpSODTJ03FsxqDc+qJdkq3Px2O7lo2Xc3csj4M7WpA59iExqokMMvJ7
# JLfLDu/NIHVqbrZmkpkWbSIO9I38WXSjmaKqtQwDlZxIgOaCTV7LCZTx7FZB5BU/
# shGVgee47dV5CRE9B0HKpeqP9Cmp7aEGegbnDZoTeOvg8RNybQ2bIDyw/znplqdd
# XEo69GBpzAqsDozAGeUY4f/WUO3qxTsjShLfLRn5rAPsjerVS0zNV64FQh3zTmFI
# M2KN6qb8+C8nu68Z1ggiPZTEJANQoFJDhpFPyVgwhiNilUT4P9fttW65g9IDcZg4
# Q4+0t65QIy1/ZgKhNmQ/IjLs90JTuhja3XXt/FWxbGoIs/Ij94AAiZ7stqF+wBkm
# onw1MHf717aScc47mQXIHZp5BJQbnr8t8YQAMFl8Cy1fx9umGqOkHiOnkWxcWob3
# lmzzF4bjN51+R7POsL4lfQvsYZQjzr3NAE/dTcsmE1OXeCTzNnzPxEufmrkEVFIy
# HenONhhE+xSX0TNgATf2J8Ue8J/j2UFdQwS8UhluRN61gCVmY9Li25PYuBxKHBfN
# spp+7OCkxEDmtGKVb9F5T2K2nJL69K9wm6V/vqcHtA++IW4x6rQgNs+QcqymTYZ9
# +dqtWG7f65Cws/lCp2zX+9SAcbOH73OwPrlZfA==
# SIG # End signature block
