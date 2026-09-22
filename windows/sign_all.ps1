# sign_all.ps1 - Sign all executables, MSI and PowerShell scripts with Andrey Sokolov Code Signing Certificate
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " Signing Binaries and Scripts (Andrey Sokolov)" -ForegroundColor Cyan
Write-Host " RFC 3161 Timestamp: http://timestamp.digicert.com (SHA-256)" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# 1. Locate or create certificate
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object { $_.Subject -like "*Andrey Sokolov*" } | Select-Object -First 1

if (-not $cert) {
    Write-Host "[CERT] Creating new 10-year Code Signing Certificate..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate -Type CodeSigningCert `
        -Subject "CN=Andrey Sokolov, O=Claude Code Proxy, E=seowizard.andrey@gmail.com" `
        -FriendlyName "Andrey Sokolov (https://github.com/seowizardandrey/claudefix)" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -NotAfter (Get-Date).AddYears(10) `
        -KeyLength 2048 `
        -HashAlgorithm "SHA256"
}

Write-Host "Using Certificate: $($cert.Subject)" -ForegroundColor Green
Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green

# 2. Export public certificate
$cerPath = Join-Path $scriptDir "ClaudeProxy.cer"
$certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
[System.IO.File]::WriteAllBytes($cerPath, $certBytes)
Write-Host "Public certificate updated: $cerPath" -ForegroundColor Green

# 3. Find files to sign: .exe, .msi, .ps1
$targetExtensions = @("*.exe", "*.msi", "*.ps1")
$filesToSign = @()
foreach ($ext in $targetExtensions) {
    $found = Get-ChildItem -Path $scriptDir -Filter $ext -File
    $filesToSign += $found
}

# Exclude signing script itself to avoid changing its own file during execution
$filesToSign = $filesToSign | Where-Object { $_.Name -ne "sign_all.ps1" }

Write-Host "`nFound $($filesToSign.Count) files to sign in $scriptDir..." -ForegroundColor Cyan

foreach ($file in $filesToSign) {
    Write-Host "Signing: $($file.Name)..." -NoNewline
    try {
        $res = Set-AuthenticodeSignature -FilePath $file.FullName `
            -Certificate $cert `
            -HashAlgorithm "SHA256" `
            -TimestampServer "http://timestamp.digicert.com" `
            -ErrorAction Stop

        if ($res.Status -eq "Valid" -or $res.Status -eq "UnknownError") {
            Write-Host " [OK] ($($res.Status))" -ForegroundColor Green
        } else {
            Write-Host " [WARNING: $($res.Status)]" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " [FAILED: $($_.Exception.Message)]" -ForegroundColor Red
    }
}

Write-Host "`n=========================================================" -ForegroundColor Cyan
Write-Host " Signing process completed!" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Cyan
