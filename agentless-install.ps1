# Path to configuration file
$destinationPath = "C:\authnull-ad-agent\agent.conf"
 
# Check if the config file exists
if (-not (Test-Path -Path $destinationPath)) {
    Write-Host "The config file does not exist at: $destinationPath" -ForegroundColor Red
    exit
}
 
# Read config file contents
try {
    $envFileContent = Get-Content -Path $destinationPath
    Write-Host "Successfully read the config file." -ForegroundColor Green
} catch {
    Write-Host "Failed to read the config file: $_" -ForegroundColor Red
    exit
}
 
# Look for ADMFA=1 in the config
$admfaEnabled = $false
$envFileContent | ForEach-Object {
    if ($_ -match "^ADMFA\s*=\s*1") {
        $admfaEnabled = $true
    }
}
 
if (-not $admfaEnabled) {
    Write-Host "ADMFA is not enabled. Exiting script." -ForegroundColor Yellow
    exit
}
 
# Variables
$GitHubURL = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/SubAuth.dll"
$DestinationPath = "$env:SystemRoot\System32\SubAuth.dll"
$RegistryPathMsv1 = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"
$DllName = "SubAuth"
$SubAuthValueName = "Auth0"
 
# Download SubAuth.dll
try {
    Write-Host "Downloading SubAuth.dll from $GitHubURL..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $GitHubURL -OutFile $DestinationPath -UseBasicParsing
    Write-Host "SubAuth.dll successfully downloaded to $DestinationPath" -ForegroundColor Green
} catch {
    Write-Host "Error downloading SubAuth.dll: $_" -ForegroundColor Red
    exit
}
 
# Modify MSV1_0 registry key
try {
    if (-not (Test-Path $RegistryPathMsv1)) {
        Write-Host "MSV1_0 registry path does not exist. Creating it..." -ForegroundColor Yellow
        New-Item -Path $RegistryPathMsv1 -Force
    }
 
    $existingAuth = Get-ItemProperty -Path $RegistryPathMsv1 -Name $SubAuthValueName -ErrorAction SilentlyContinue
 
    if ($existingAuth) {
        Write-Host "$SubAuthValueName already set to: $($existingAuth.$SubAuthValueName)" -ForegroundColor Yellow
    } else {
        Write-Host "Creating $SubAuthValueName and assigning value '$DllName'..." -ForegroundColor Cyan
        New-ItemProperty -Path $RegistryPathMsv1 -Name $SubAuthValueName -PropertyType String -Value $DllName -Force
        Write-Host "$SubAuthValueName successfully created and set." -ForegroundColor Green
    }
} catch {
    Write-Host "Error modifying MSV1_0 registry key: $_" -ForegroundColor Red
    exit
}
 
# Prompt restart
try {
    Write-Host "`nSystem will restart in 10 seconds to apply changes..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} catch {
    Write-Host "Error restarting the system: $_" -ForegroundColor Red
    exit
}