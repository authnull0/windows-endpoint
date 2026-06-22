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
$sspDll     = "AuthnullSSP"
$binaryUrl      = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-sensor/AuthnullDCSensor.exe"
$winDivertDllUrl = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-sensor/WinDivert.dll"
$winDivertSysUrl = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-sensor/WinDivert64.sys"
$sspDllUrl       = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-sensor/AuthnullSSP.dll"

Write-Host "[1/7] Creating directories..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $configDir  | Out-Null

Write-Host "[2/7] Copying sensor config..." -ForegroundColor Cyan
$sensorYml = Join-Path $PSScriptRoot "sensor.yml"
if (-not (Test-Path $sensorYml)) {
    Write-Error "sensor.yml not found at $sensorYml`nDownload it from the Authnull dashboard and place it in the same folder as this script."
}
Copy-Item $sensorYml "$configDir\sensor.yml" -Force
Write-Host "    Config written to $configDir\sensor.yml" -ForegroundColor Green

Write-Host "[3/7] Downloading AuthnullDCSensor binary..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $binaryUrl -OutFile $exePath -UseBasicParsing
Write-Host "    Binary saved to $exePath" -ForegroundColor Green

Write-Host "    Downloading WinDivert drivers..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $winDivertDllUrl -OutFile "$installDir\WinDivert.dll"   -UseBasicParsing
Invoke-WebRequest -Uri $winDivertSysUrl -OutFile "$installDir\WinDivert64.sys" -UseBasicParsing
Write-Host "    WinDivert drivers saved to $installDir" -ForegroundColor Green

Write-Host "[4/7] Installing AuthnullSSP DLL..." -ForegroundColor Cyan
$sspDest = "$env:SystemRoot\System32\AuthnullSSP.dll"
Invoke-WebRequest -Uri $sspDllUrl -OutFile $sspDest -UseBasicParsing
Write-Host "    AuthnullSSP.dll copied to $sspDest" -ForegroundColor Green

# Register AuthnullSSP as an LSA Security Package
$lsaKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
$current = (Get-ItemProperty -Path $lsaKey -Name "Security Packages")."Security Packages"
if ($current -notcontains $sspDll) {
    $updated = $current + $sspDll
    Set-ItemProperty -Path $lsaKey -Name "Security Packages" -Value $updated
    Write-Host "    AuthnullSSP registered in LSA Security Packages." -ForegroundColor Green
} else {
    Write-Host "    AuthnullSSP already registered in LSA Security Packages." -ForegroundColor Yellow
}

Write-Host "[5/7] Installing Windows service..." -ForegroundColor Cyan
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

Write-Host "[6/7] Starting service..." -ForegroundColor Cyan
Start-Service -Name $svcName

$svc = Get-Service -Name $svcName
Write-Host "    Service status: $($svc.Status)" -ForegroundColor Green

Write-Host ""
Write-Host "[7/7] Reboot required." -ForegroundColor Yellow
Write-Host "    AuthnullSSP.dll is registered but will not load into LSASS until the DC is rebooted."
Write-Host "    Schedule a reboot at your earliest maintenance window to activate NTLM enforcement."
Write-Host ""
$reboot = Read-Host "Reboot now? (y/n)"
if ($reboot -eq "y") {
    Write-Host "Rebooting..." -ForegroundColor Yellow
    Restart-Computer -Force
} else {
    Write-Host ""
    Write-Host "Installation complete. Reboot the DC to activate NTLM enforcement." -ForegroundColor Green
    Write-Host ""
    Write-Host "To verify after reboot:"
    Write-Host "  Get-Service AuthnullDCSensor"
    Write-Host "  Get-EventLog -LogName Application -Source AuthnullDCSensor -Newest 20"
}
