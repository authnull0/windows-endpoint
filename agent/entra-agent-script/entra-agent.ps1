# -------------------------------
# Entra Agent Installation Script
# -------------------------------

$ErrorActionPreference = "Stop"

# === Variables ===
$downloadUrl = "https://github.com/authnull0/windows-endpoint/raw/linux-testing/entra-agent.rar"
$installDir = "C:\authnull-entra-agent"
$rarPath = "$env:USERPROFILE\Downloads\entra-agent.rar"
$envPath = "$env:USERPROFILE\Downloads\app.env"
$sevenZipPath = "${env:ProgramFiles}\7-Zip\7z.exe"  # Adjust path if different

# === Step 1: Create installation directory ===
Write-Host "===> Creating installation directory..." -ForegroundColor Cyan
if (-Not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir | Out-Null
}

# === Step 2: Download the RAR file ===
Write-Host "===> Downloading agent archive..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $downloadUrl -OutFile $rarPath

# === Step 3: Extract RAR using 7-Zip ===
if (-Not (Test-Path $sevenZipPath)) {
    Write-Host "❌ 7-Zip not found at $sevenZipPath. Please install 7-Zip or update the script." -ForegroundColor Red
    exit 1
}

Write-Host "===> Extracting agent archive..." -ForegroundColor Cyan
Start-Process -Wait -NoNewWindow -FilePath $sevenZipPath -ArgumentList "x `"$rarPath`" -o`"$installDir`" -y"

# === Step 4: Prompt for CLIENT_SECRET and update app.env ===
$clientSecret = Read-Host -Prompt "Enter the CLIENT_SECRET"
$clientSecret = $clientSecret.Trim("`"`' ")  # Safely trim quotes and spaces


if (-Not (Test-Path $envPath)) {
    Write-Host "❌ app.env not found in Downloads folder. Please place it there before running the script." -ForegroundColor Red
    exit 1
}

# Remove old CLIENT_SECRET if present
(Get-Content $envPath) | Where-Object { $_ -notmatch "^CLIENT_SECRET=" } | Set-Content $envPath

# Append the new CLIENT_SECRET
Add-Content -Path $envPath -Value "CLIENT_SECRET=$clientSecret"
Write-Host "===> Updated app.env with CLIENT_SECRET." -ForegroundColor Green

# === Step 5: Move app.env to agent directory ===
Move-Item -Path $envPath -Destination "$installDir\entra-agent\app.env" -Force
Write-Host "===> Moved app.env to agent folder." -ForegroundColor Green

# === Step 6: Install and start the agent ===
$exePath = Join-Path $installDir "entra-agent\agent.exe"

if (-Not (Test-Path $exePath)) {
    Write-Host "❌ agent.exe not found at $exePath. Check extraction or archive contents." -ForegroundColor Red
    exit 1
}

Write-Host "===> Installing agent service..." -ForegroundColor Cyan
Start-Process -FilePath $exePath -ArgumentList "install" -Wait

Write-Host "===> Starting agent service..." -ForegroundColor Cyan
Start-Process -FilePath $exePath -ArgumentList "start" -Wait

Write-Host "`n✅ Entra Agent installed and started successfully!" -ForegroundColor Green
