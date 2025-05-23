# Continue with the rest of the script
param (
    [string]$OutputPath
)

# Check if the output path parameter is provided
if (-not $OutputPath) {
    Write-Host "Please provide the path where you want to save the downloaded file using the -OutputPath parameter." -ForegroundColor Yellow
    exit
}

# Check if the output directory exists; if not, create it
if (-not (Test-Path -Path $OutputPath -PathType Container)) {
    try {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $OutputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create directory: $_" -ForegroundColor Red
        exit
    }
}
else {
    Write-Host "Output directory already exists...downloading now" -ForegroundColor Yellow
}

# Define the URL of the file to download
$url = "https://github.com/authnull0/windows-endpoint/archive/refs/heads/ad-agent.zip"

# Download the file
try {
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($url, "$OutputPath\ad-agent.zip")
    Write-Host "Download completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    exit
}

if (Test-Path "$OutputPath\ad-agent.zip") {
    # Extract the file
    try {
        Expand-Archive -Path "$OutputPath\ad-agent.zip" -DestinationPath $OutputPath -Force
        Write-Host "Extraction completed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Extraction failed: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Zip file not found at: $OutputPath\ad-agent.zip" -ForegroundColor Red
}

# Create folder C:\authnull-ad-agent
$FolderPath = "C:\authnull-ad-agent"
if (-not (Test-Path -Path $FolderPath -PathType Container)) {
    try {
        New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $FolderPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create directory: $_" -ForegroundColor Red
        exit
    }
}
else {
    Write-Host "Folder already exists.." -ForegroundColor Yellow
}

# Copy publish folder
$sourceDirectory = $OutputPath + "\windows-endpoint-ad-agent\agent\ad-agent-build"
Copy-Item -Path "$sourceDirectory\*" -Destination $FolderPath -Recurse -Force -Verbose
Write-Host "Copied files successfully to the publish folder.." -ForegroundColor Green

# Copy the configuration file
$sourcePath = (Get-Location).Path + "\agent.conf"
$destinationPath = "C:\authnull-ad-agent\agent.conf"

# Check if the source file exists
if (Test-Path $sourcePath) {
    Copy-Item -Path $sourcePath -Destination $destinationPath -Force
    Write-Host "File agent.conf has been copied to C:\authnull-ad-agent successfully." -ForegroundColor Green
}
else {
    # If the file doesn't exist, stop the script
    Write-Host "File not found in the current working directory. The script cannot proceed." -ForegroundColor Red
    exit
}

# Get the password securely from the user as the first step
$cred = Get-Credential

# get the password as it is and store in the file as LDAP_PASSWORD
$securePassword = $cred.GetNetworkCredential().Password


if (-not (Test-Path -Path $destinationPath)) {
    try {
        New-Item -Path $destinationPath -ItemType File -Force | Out-Null
        Write-Host "Created conf.env file: $destinationPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to create conf.env file: $_" -ForegroundColor Red
        exit
    }
}

# Add-Content -Path $destinationPath -Value "LDAP_PASSWORD=$securePassword" add in the new line
Add-Content -Path $destinationPath -Value "`nLDAP_PASSWORD=$securePassword" -Force
Write-Host "Password stored successfully in the env file." -ForegroundColor Green

# #updating group policy to enable and disable respective credential providers

# $lgpoPath = $OutputPath + "\windows-endpoint-ad-agent\gpo\LGPO.exe"

# $infFilePath = $OutputPath + "\windows-endpoint-ad-agent\gpo\security.inf"
    
# try {
#     Start-Process -FilePath $lgpoPath -ArgumentList "/s $infFilePath"
#     Write-Host "Security settings installed successfully." -ForegroundColor Green

#     # Run gpupdate /force to refresh policies
#     Write-Host "Refreshing Group Policy settings..." -ForegroundColor Yellow
#     Start-Process -FilePath "gpupdate" -ArgumentList "/force" -Wait
#     Write-Host "Group Policy updated successfully." -ForegroundColor Green
# } 
# catch {
#     Write-Host "Security setting installation failed : $_" -ForegroundColor Red
# }

# Define paths
$BackupDirectory = "C:\Backup\SecurityPolicies"
$BackupFile = "$BackupDirectory\security.inf"
$ModifiedFile = "$BackupDirectory\modified_security.inf"
$LogFile = "$BackupDirectory\secedit.log"

# Ensure the backup directory exists
if (-not (Test-Path $BackupDirectory)) {
    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
}

try {
    # Step 1: Export the current security policy
    Write-Host "Exporting current security policy..." -ForegroundColor Yellow
    secedit /export /cfg $BackupFile /log $LogFile
    Write-Host "Exported security policy to $BackupFile" -ForegroundColor Green

    # Step 2: Modify the PasswordComplexity setting
    Write-Host "Modifying PasswordComplexity setting to 0..." -ForegroundColor Yellow
    $content = Get-Content $BackupFile
    $content = $content -replace "PasswordComplexity\s*=\s*\d+", "PasswordComplexity = 0"
    $content | Set-Content $ModifiedFile
    Write-Host "PasswordComplexity updated in $ModifiedFile" -ForegroundColor Green

    # Step 3: Reimport the modified security policy
    Write-Host "Importing modified security policy..." -ForegroundColor Yellow
    $seceditPath = Join-Path $env:SystemRoot "security\local.sdb"
    secedit /configure /db $seceditPath /cfg $ModifiedFile /log $LogFile
    Write-Host "Modified security policy applied successfully." -ForegroundColor Green

    # Step 4: Force Group Policy update
    Write-Host "Forcing Group Policy update..." -ForegroundColor Yellow
    gpupdate /force
    Write-Host "Group Policy updated successfully." -ForegroundColor Green
}
catch {
    Write-Host "An error occurred: $_" -ForegroundColor Red
}

# Check the log file for any issues
Write-Host "Check the log file at $LogFile for detailed information." -ForegroundColor Yellow


# Start service
try {
    New-Service -Name "AuthNullADAgent" -BinaryPathName "C:\authnull-ad-agent\publish\ADagent.exe"
    Start-Service -Name "AuthNullADAgent" -WarningAction SilentlyContinue
}
catch {
    Write-Host "Failed to start service" -ForegroundColor Red
}

Get-Service AuthNullADAgent
# #Restart Computer

# try {
#     Write-Host "Waiting for 10 seconds before restarting..." -ForegroundColor Yellow
#     Start-Sleep -Seconds 10
#     Restart-Computer -Force
# }
# catch {
#     Write-Host "Restarting computer failed: $_" -ForegroundColor Red
# }

