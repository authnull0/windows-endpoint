#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step { param([string]$msg) Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Err  { param([string]$msg) Write-Host "    [ERR] $msg" -ForegroundColor Red }
function Write-Info { param([string]$msg) Write-Host "    $msg" -ForegroundColor Gray }

# ── Banner ────────────────────────────────────────────────────────────────────

Clear-Host
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        AuthNull AD Agent Installer           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Step 1: Load config.yaml ──────────────────────────────────────────────────

Write-Step "Loading config.yaml"
$ConfigPath = Join-Path $PSScriptRoot "config.yaml"
if (-not (Test-Path $ConfigPath)) {
    Write-Err "config.yaml not found at $ConfigPath"
    Write-Host "    Make sure config.yaml is in the same directory as this script." -ForegroundColor Yellow
    exit 1
}
$configContent = Get-Content $ConfigPath -Raw
Write-Ok "Loaded $ConfigPath"

$adServer = if ($configContent -match 'server:\s*"([^"]+)"')   { $Matches[1] } else { "(unknown)" }
$username = if ($configContent -match 'username:\s*"([^"]+)"') { $Matches[1] } else { "(unknown)" }
$baseURL  = if ($configContent -match 'base_url:\s*"([^"]+)"') { $Matches[1] } else { "(unknown)" }

Write-Host ""
Write-Info "LDAP Server : $adServer"
Write-Info "Username    : $username"
Write-Info "API URL     : $baseURL"
Write-Host ""

# ── Step 2: Collect password ──────────────────────────────────────────────────

Write-Step "Credentials"
$password = Read-Host "Password for $username" -AsSecureString
$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))

$patched = $configContent -replace '(?m)(^\s*password:\s*)"[^"]*"', "`$1`"$plainPassword`""

# ── Step 3: Create install directory ─────────────────────────────────────────

$InstallDir   = "C:\authnull-ad-agent"
$ServiceName  = "AuthNullADAgent"
$GitHubExeUrl = "https://github.com/authnull0/windows-endpoint/releases/latest/download/ad-sync-agent.exe"

Write-Step "Creating install directory"
if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
    Write-Ok "Created $InstallDir"
} else {
    Write-Info "$InstallDir already exists"
}

# ── Step 4: Write config.yaml with password ───────────────────────────────────

Write-Step "Writing config.yaml"
Set-Content -Path (Join-Path $InstallDir "config.yaml") -Value $patched -Encoding UTF8
Write-Ok "Config written to $InstallDir\config.yaml"

# ── Step 5: Download agent binary ─────────────────────────────────────────────

Write-Step "Downloading AD Sync Agent"
$exeDest = Join-Path $InstallDir "ad-sync-agent.exe"
try {
    Write-Info "Downloading from $GitHubExeUrl ..."
    Invoke-WebRequest -Uri $GitHubExeUrl -OutFile $exeDest -UseBasicParsing
    Write-Ok "Downloaded to $exeDest"
} catch {
    Write-Err "Download failed: $_"
    Write-Host "    Place ad-sync-agent.exe manually in $InstallDir and retry." -ForegroundColor Yellow
    exit 1
}

# ── Step 6: Test LDAP connectivity ───────────────────────────────────────────

Write-Step "Testing LDAP connectivity"
Write-Info "Running agent once to verify LDAP — press Ctrl+C to abort if it hangs."
Write-Host ""

Push-Location $InstallDir
$testResult = & ".\ad-sync-agent.exe" 2>&1
Pop-Location

$testOutput = $testResult -join [Environment]::NewLine
Write-Host $testOutput

if ($testOutput -match "Connected to LDAP successfully") {
    Write-Ok "LDAP connection verified."
} else {
    Write-Err "LDAP connection test failed. Check config.yaml and retry."
    Write-Host "      - Verify $adServer is reachable" -ForegroundColor Yellow
    Write-Host "      - Verify username/password are correct" -ForegroundColor Yellow
    Write-Host "      - For port 389: ensure DC allows simple bind" -ForegroundColor Yellow
    exit 1
}

# ── Step 7: Remove old service if present ────────────────────────────────────

Write-Step "Checking for existing service"
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Info "Service '$ServiceName' found — stopping and removing..."
    if ($existing.Status -eq "Running") { Stop-Service -Name $ServiceName -Force }
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
    Write-Ok "Old service removed."
}

# ── Step 8: Install as Windows service ───────────────────────────────────────

Write-Step "Installing Windows service"
New-Service -Name $ServiceName -BinaryPathName "$InstallDir\ad-sync-agent.exe" -DisplayName "AuthNull AD Agent" -StartupType Automatic
Start-Service -Name $ServiceName
$svc = Get-Service -Name $ServiceName
Write-Ok "Service '$ServiceName' is $($svc.Status)."

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   AuthNull AD Agent installed successfully   ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Service log : $InstallDir\agent.log"
Write-Host "  Config      : $InstallDir\config.yaml"
Write-Host ""
Write-Host "  To restart : Restart-Service $ServiceName" -ForegroundColor Gray
Write-Host "  To check   : Get-Service $ServiceName" -ForegroundColor Gray
