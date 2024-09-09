#single file
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
    } catch {
        Write-Host "Failed to create directory: $_" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "Output directory already exists...downloading now" -ForegroundColor Yellow
    
}

# Define the URL of the file to download
$url = "https://github.com/authnull0/windows-endpoint/archive/refs/heads/ad-agent.zip"

# Download the file

try {
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($url, "$OutputPath\ad-agent.zip")
    Write-Host "Download completed successfully." -ForegroundColor Green
} catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    exit
}

if (Test-Path "$OutputPath\ad-agent.zip") {
# Extract the file
try {
    Expand-Archive -Path "$OutputPath\ad-agent.zip" -DestinationPath $OutputPath -Force
    Write-Host "Extraction completed successfully." -ForegroundColor Green
} catch {
    Write-Host "Extraction failed: $_" -ForegroundColor Red
}
}
else {
    Write-Host "Zip file not found at: $OutputPath\ad-agent.zip" -ForegroundColor Red
}

#create folder C:\authnull-ad-agent
$FolderPath = "C:\authnull-ad-agent"
if (-not (Test-Path -Path $FolderPath -PathType Container)) {
    try {
        New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $FolderPath" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create directory: $_" -ForegroundColor Red
        exit
    }
} else {
    Write-Host "Folder already exists.." -ForegroundColor Yellow
    
}

#copy publish folder
$sourceDirectory = $OutputPath + "\windows-endpoint-ad-agent\agent\ad-agent-build"
Copy-Item -Path "$sourceDirectory\*" -Destination $FolderPath -Recurse -Force -Verbose
Write-Host "Copied files successfully to the publish folder.." -ForegroundColor Green

# # Prompt the user for input
# Write-Host "Please copy and paste the content for the conf file. Press Enter twice to finish." -ForegroundColor DarkGreen

# #Getting the conf file content
# $confContent = ""
# do {
#     $line = Read-Host
#     if (-not [string]::IsNullOrEmpty($line)) {
#         $confContent += "$line`n" # Append the line to the text blob
#     }
# } while (-not [string]::IsNullOrEmpty($line))


# # Write the conf file with the provided content
# try {

#     #check whether the file is empty or not
#     if (-not [string]::IsNullOrEmpty($confContent)) {
#         $confContent | Out-File -FilePath $confFilePath -Encoding utf8
#         Write-Host "Configuration file saved successfully to: $confFilePath" -ForegroundColor Green
#     } else {
#         Write-Host "The content to be written to the file is null or empty." -ForegroundColor Yellow
#     }
# } catch {
#     Write-Host "Failed to save configuration file: $_" -ForegroundColor Red
# }

$sourcePath = (Get-Location).Path + "\agent.conf"
$destinationPath = "C:\authnull-ad-agent\agent.conf"

# Check if the source file exists
if (Test-Path $sourcePath) {
   
    Copy-Item -Path $sourcePath -Destination $destinationPath -Force
    Write-Host "File agent.conf has been copied to C:\authnull-ad-agent successfully." -ForegroundColor Green
} else {
    # If the file doesn't exist, stop the script
    Write-Host "File not found in the current working directory. The script cannot proceed." -ForegroundColor Red
    exit
}
#start service
    try{
        New-Service -Name "AuthNullADAgent" -BinaryPathName "C:\authnull-ad-agent\publish\ADagent.exe" 

        Start-Service -Name "AuthNullADAgent" -WarningAction SilentlyContinue
    }
    catch{
        Write-Host "Failed to start service" -ForegroundColor Red
        
    }
    Get-Service AuthNullADAgent