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
# # Define the URL of the file to download
# $url = "https://github.com/authnull0/windows-endpoint/archive/refs/heads/mysql-db-agent.zip"

# # Download the file

# try {
#     $webClient = New-Object System.Net.WebClient
#     $webClient.DownloadFile($url, "$OutputPath\file.zip")
#     Write-Host "Download completed successfully." -ForegroundColor Green
# } catch {
#     Write-Host "Download failed: $_" -ForegroundColor Red
#     exit
# }

# if (Test-Path "$OutputPath\file.zip") {
# # Extract the file
# try {
#     Expand-Archive -Path "$OutputPath\file.zip" -DestinationPath $OutputPath -Force
#     Write-Host "Extraction completed successfully." -ForegroundColor Green
# } catch {
#     Write-Host "Extraction failed: $_" -ForegroundColor Red
# }
# }
# else {
#     Write-Host "Zip file not found at: $OutputPath\file.zip" -ForegroundColor Red

# }
# #----------------------------------------------------------------------------------

# # Define the source path in the current working directory
# $sourcePath = (Get-Location).Path + "\db.env"
# $destinationPath = $OutputPath + "\db.env"

# # Check if the source file exists
# if (Test-Path $sourcePath) {
   
#     Copy-Item -Path $sourcePath -Destination $destinationPath -Force
#     Write-Host "File app.env has been copied to C:\authnull-db-agent successfully." -ForegroundColor Green
# } else {
#     # If the file doesn't exist, stop the script
#     Write-Host "File app.env not found in the current working directory. The script cannot proceed." -ForegroundColor Red
#     exit
# }
 
#---------------------------------------------------------------------------
# Prompt the user for runtime inputs
$DbPort = Read-Host "Enter the database port"
$DbPassword = Read-Host "Enter the database password"
$DbHost = Read-Host "Enter the database host"
$ApiKey = Read-Host "Enter the API key"

# Ensure the agent path is correct
$agentPath = "C:\authnull-db-agent\agent.exe"

# Check if the agent executable exists
if (-Not (Test-Path $agentPath)) {
    Write-Host "Agent executable not found at $agentPath" -ForegroundColor Red
    exit
}

# Run the agent with the provided arguments
& $agentPath --port $DbPort --password $DbPassword --host $DbHost --api_key $ApiKey

# Check the exit code to verify success or failure
if ($LASTEXITCODE -eq 0) {
    Write-Host "Agent executed successfully." -ForegroundColor Green
} else {
    Write-Host "Agent failed with exit code $LASTEXITCODE." -ForegroundColor Red
}
