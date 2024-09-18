#single file
param (
    [string]$OutputPath
)

# Check if the output path parameter is provided
if (-not $OutputPath) {
    Write-Host "Please provide the path where you want to save the downloaded file using the -OutputPath parameter." -ForegroundColor Yellow
    exit
}
#-----------------------------------------------------------------------
#Cleaning the System 
# Check if the output directory exists; if not, create it
if (Test-Path -Path $OutputPath -PathType Container) {
    try {
        Write-Host "Directory already exist. Deleting and recreating it.." -ForegroundColor Red
        Remove-Item -Path $OutputPath -Recurse -Force -ErrorAction SilentlyContinue
        
    } catch {
        Write-Host "Failed to delete directory: $_" -ForegroundColor Red
        exit
    }

    try{
        Write-Host "Creating a new directory.." -ForegroundColor Yellow
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $OutputPath" -ForegroundColor Green   
}
catch{
    Write-Host "Failed to create directory: $_ " -ForegroundColor Red

}

    }

 else {
    try{
        Write-Host "Creating a new directory.." -ForegroundColor Yellow
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $OutputPath" -ForegroundColor Green   
}
catch{
    Write-Host "Failed to create directory: $_ " -ForegroundColor Red
}
}
# Define the URL of the file to download
$url = "https://github.com/authnull0/windows-endpoint/archive/refs/heads/mysql-db-agent.zip"

# Download the file

try {
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($url, "$OutputPath\file.zip")
    Write-Host "Download completed successfully." -ForegroundColor Green
} catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    exit
}

if (Test-Path "$OutputPath\file.zip") {
# Extract the file
try {
    Expand-Archive -Path "$OutputPath\file.zip" -DestinationPath $OutputPath -Force
    Write-Host "Extraction completed successfully." -ForegroundColor Green
} catch {
    Write-Host "Extraction failed: $_" -ForegroundColor Red
}
}
else {
    Write-Host "Zip file not found at: $OutputPath\file.zip" -ForegroundColor Red

}
#----------------------------------------------------------------------------------

# Define the source path in the current working directory
$sourcePath = (Get-Location).Path + "\db.env"
$destinationPath = $OutputPath + "\db.env"

# Check if the source file exists
if (Test-Path $sourcePath) {
   
    Copy-Item -Path $sourcePath -Destination $destinationPath -Force
    Write-Host "File app.env has been copied to C:\authnull-db-agent successfully." -ForegroundColor Green
} else {
    # If the file doesn't exist, stop the script
    Write-Host "File app.env not found in the current working directory. The script cannot proceed." -ForegroundColor Red
    exit
}
 
#---------------------------------------------------------------------------

$AgentPath= $OutputPath + "\windows-endpoint-main\mysql-db-agent\windows-build\windows-db-agent-amd64.exe"
Copy-Item -Path $AgentPath -Destination $OutputPath -Force -Verbose


try {
    New-Service -Name "AuthNullDbAgent" -BinaryPathName $OutputPath"\windows-db-agent-amd64.exe" 
    Start-Service AuthNullAgent -WarningAction SilentlyContinue
} catch {
    Write-Host "Registering AuthNull Database Agent failed!" -ForegroundColor Red
}
finally {
    # Do this after the try block regardless of whether an exception occurred or not
}
Get-Service AuthNullDbAgent
Write-Host "The path of the agent is " $OutputPath"\windows-agent-amd64.exe" -ForegroundColor Yellow