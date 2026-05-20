#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installs the AuthnullDCSensor Windows service on a Domain Controller.
.DESCRIPTION
    Downloads the AuthnullDCSensor binary from GitHub releases, copies sensor.yml
    to the expected config location, and registers + starts the Windows service.
.NOTES
    Run as Domain Admin / Administrator on the Domain Controller.
    Place sensor.yml in the same folder as this script before running.
#>

$ErrorActionPreference = "Stop"

$svcName    = "AuthnullDCSensor"
$installDir = "C:\Program Files\Authnull\DCSensor"
$configDir  = "C:\ProgramData\Authnull"
$exePath    = "$installDir\AuthnullDCSensor.exe"
$binaryUrl  = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-sensor/AuthnullDCSensor.exe"

Write-Host "[1/5] Creating directories..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $configDir  | Out-Null

Write-Host "[2/5] Copying sensor config..." -ForegroundColor Cyan
$sensorYml = Join-Path $PSScriptRoot "sensor.yml"
if (-not (Test-Path $sensorYml)) {
    Write-Error "sensor.yml not found at $sensorYml`nDownload it from the AuthNull dashboard and place it in the same folder as this script."
}
Copy-Item $sensorYml "$configDir\sensor.yml" -Force
Write-Host "    Config written to $configDir\sensor.yml" -ForegroundColor Green

Write-Host "[3/5] Downloading AuthnullDCSensor binary..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $binaryUrl -OutFile $exePath -UseBasicParsing
Write-Host "    Binary saved to $exePath" -ForegroundColor Green

Write-Host "[4/5] Installing Windows service..." -ForegroundColor Cyan
$existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "    Removing existing service..." -ForegroundColor Yellow
    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
    & sc.exe delete $svcName | Out-Null
    Start-Sleep -Seconds 2
}
New-Service -Name $svcName `
            -BinaryPathName "`"$exePath`"" `
            -DisplayName "Authnull DC Sensor" `
            -Description "Authnull AD Shield - Domain Controller authentication sensor" `
            -StartupType Automatic
# Auto-restart on crash: after 5s, 10s, then 30s
& sc.exe failure $svcName reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
Write-Host "    Service registered." -ForegroundColor Green

Write-Host "[5/5] Starting service..." -ForegroundColor Cyan
Start-Service -Name $svcName

$svc = Get-Service -Name $svcName
Write-Host ""
Write-Host "Installation complete. Service status: $($svc.Status)" -ForegroundColor Green
Write-Host ""
Write-Host "To verify:    Get-Service AuthnullDCSensor"
Write-Host "To view logs: Get-EventLog -LogName Application -Source AuthnullDCSensor -Newest 20"
