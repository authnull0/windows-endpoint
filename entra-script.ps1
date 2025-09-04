# pGina Installation Script
# Installs pGina with prerequisites and sets up plugin folders
 
param (
    [string]$OutputPath = "C:\Temp\AuthNull"
)
 
# Stop script on first error
$ErrorActionPreference = "Stop"
 
# Ensure directories exist
$directories = @($OutputPath, "C:\authnull-agent", "C:\EntraPlugin", "C:\LocalMachinePlugin")
 
foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $dir" -ForegroundColor Yellow
    }
}
 
# Download helper function
function Download-File {
    param(
        [string]$Url,
        [string]$DestPath
    )
    Write-Host "Downloading $Url ..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $Url -OutFile $DestPath -UseBasicParsing -ErrorAction Stop
        if (-not (Test-Path $DestPath)) {
            throw "File not found after download: $DestPath"
        }
    }
    catch {
        Write-Host "Download failed: $Url" -ForegroundColor Red
        throw
    }
}
 
# Base URLs
$basePgina = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/credential-provider/pgina"
$basePlugins = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/credential-provider/plugins"
 
# File paths
$pginaInstaller = "$OutputPath\pGinaSetup-3.1.8.0.exe"
$vcx64 = "$OutputPath\vcRedist_x64.exe"
$vcx86 = "$OutputPath\vcredist_x86.exe"
$entraDll = "C:\EntraPlugin\entra.dll"
$log4netDll = "C:\EntraPlugin\log4net.dll"
 
# Download dependencies
Write-Host "Downloading installation files..." -ForegroundColor Cyan
Download-File "$basePgina/pGinaSetup-3.1.8.0.exe" $pginaInstaller
Download-File "$basePgina/vcRedist_x64.exe" $vcx64
Download-File "$basePgina/vcredist_x86.exe" $vcx86
 
# Install VC++ Redistributables
Write-Host "Installing Visual C++ Redistributables..." -ForegroundColor Yellow
 
$proc1 = Start-Process -FilePath $vcx64 -ArgumentList "/quiet", "/norestart" -PassThru -Wait
if ($proc1.ExitCode -ne 0) {
    throw "VC++ x64 installer failed with code $($proc1.ExitCode)"
}
 
$proc2 = Start-Process -FilePath $vcx86 -ArgumentList "/quiet", "/norestart" -PassThru -Wait
if ($proc2.ExitCode -ne 0) {
    throw "VC++ x86 installer failed with code $($proc2.ExitCode)"
}
 
Write-Host "Visual C++ Redistributables installed successfully." -ForegroundColor Green
 
# Install pGina
Write-Host "Installing pGina..." -ForegroundColor Yellow
$proc3 = Start-Process -FilePath $pginaInstaller -ArgumentList "/SILENT" -PassThru -Wait
if ($proc3.ExitCode -ne 0) {
    throw "pGina installer failed with code $($proc3.ExitCode)"
}
 
Write-Host "pGina installed successfully." -ForegroundColor Green
 
# Download Entra plugin files
Write-Host "Downloading Entra plugin files..." -ForegroundColor Cyan
$entraDownloaded = Download-File "$basePlugins/Entra.dll" $entraDll -Optional
$log4netDownloaded = Download-File "$basePlugins/log4net.dll" $log4netDll -Optional
 
if ($entraDownloaded -and $log4netDownloaded) {
    Write-Host "Entra plugin files downloaded successfully." -ForegroundColor Green
} else {
    Write-Host "Warning: Some Entra plugin files were not available. You may need to obtain them separately." -ForegroundColor Yellow
    Write-Host "Expected locations:" -ForegroundColor Yellow
    Write-Host "  - $entraDll" -ForegroundColor Yellow  
    Write-Host "  - $log4netDll" -ForegroundColor Yellow
}
 
# Copy LocalMachine plugin
$pginaLocalDll = "C:\Program Files\pGina\Plugins\Core\pGina.Plugin.LocalMachine.dll"
if (Test-Path $pginaLocalDll) {
    Copy-Item $pginaLocalDll -Destination "C:\LocalMachinePlugin" -Force -ErrorAction Stop
    Write-Host "Copied LocalMachine plugin successfully." -ForegroundColor Green
} else {
    throw "LocalMachine plugin not found at $pginaLocalDll"
}
 
Write-Host "Setup completed successfully. pGina installed and plugins prepared." -ForegroundColor Green