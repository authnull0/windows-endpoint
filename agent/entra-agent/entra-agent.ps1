param (
    [string]$DownloadDir = "C:\temp\entra-download",
    [string]$InstallDir = "C:\EntraSyncAgent",
    [string]$RarUrl = "https://raw.githubusercontent.com/authnull0/windows-endpoint/linux-testing/entra-agent.rar"
)

$serviceName = "EntraSyncAgent"

# ---------------- STEP 1: Stop and delete existing service ----------------
Write-Host "Stopping and removing service '$serviceName' (if exists)..." -ForegroundColor Yellow
try {
    Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
    sc.exe delete $serviceName | Out-Null
} catch {
    Write-Host "Service not found or could not be deleted (may already be gone)." -ForegroundColor DarkYellow
}



# ---------------- STEP 3: Download entra-agent.rar ----------------
if (-not (Test-Path $DownloadDir)) {
    New-Item -Path $DownloadDir -ItemType Directory -Force | Out-Null
}
$rarPath = Join-Path $DownloadDir "entra-agent.rar"
if (-not (Test-Path $rarPath)) {
    Write-Host "Downloading entra-agent.rar..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $RarUrl -OutFile $rarPath
    Write-Host "Downloaded to: $rarPath" -ForegroundColor Green
} else {
    Write-Host "RAR already exists. Skipping download." -ForegroundColor Yellow
}

# ---------------- STEP 4: Extract entra-agent.rar ----------------
$sevenZip = "C:\Program Files\7-Zip\7z.exe"
$winrar = "C:\Program Files\WinRAR\winrar.exe"
$extracted = $false

if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

if (Get-Command "7z.exe" -ErrorAction SilentlyContinue) {
    & 7z.exe x $rarPath -o"$InstallDir" -y
    $extracted = $true
} elseif (Test-Path $sevenZip) {
    & "$sevenZip" x $rarPath -o"$InstallDir" -y
    $extracted = $true
} elseif (Test-Path $winrar) {
    & "$winrar" x $rarPath "$InstallDir\"
    $extracted = $true
} else {
    Write-Host " Could not find 7-Zip or WinRAR. Please install one of them." -ForegroundColor Red
    exit 1
}
Write-Host "Extraction complete." -ForegroundColor Green

# ---------------- STEP 5: Prompt for client_secret ----------------
$clientSecret = Read-Host "Enter your Entra Client Secret"
$yamlPath = Join-Path $InstallDir "entra-credentials.yaml"
$deltaPath = Join-Path $InstallDir "delta_link.txt"
$yaml = @"
client_secret: $clientSecret
sync_interval_seconds: 3600
delta_link_file: $deltaPath
"@
$yaml | Out-File -FilePath $yamlPath -Encoding utf8
Write-Host "Created entra-credentials.yaml" -ForegroundColor Green

# ---------------- STEP 6: Validate app.env ----------------
$envPath = Join-Path $InstallDir "app.env"
if (-not (Test-Path $envPath)) {
    Write-Host " Missing required app.env in $InstallDir. Please place it before continuing." -ForegroundColor Red
    exit 1
}
Write-Host "Found app.env, continuing." -ForegroundColor Green

# ---------------- STEP 7: Find binary and install service ----------------
$exePath = Get-ChildItem -Path $InstallDir -Recurse -Filter "entra-sync-agent.exe" | Select-Object -First 1
if (-not $exePath) {
    Write-Host " entra-sync-agent.exe not found in extracted files." -ForegroundColor Red
    exit 1
}

Write-Host "Installing service via entra-sync-agent.exe..." -ForegroundColor Cyan
& $exePath.FullName install

Start-Sleep -Seconds 2

# ---------------- STEP 8: Start service ----------------
try {
    Start-Service -Name $serviceName
    Write-Host "Service '$serviceName' started successfully." -ForegroundColor Green
} catch {
    Write-Host " Failed to start service: $_" -ForegroundColor Red
    exit 1
}

# ---------------- STEP 9: Show status ----------------
Get-Service -Name $serviceName
