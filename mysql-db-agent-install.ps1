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
    Write-Host "File db.env has been copied to C:\authnull-db-agent successfully." -ForegroundColor Green
} else {
    # If the file doesn't exist, stop the script
    Write-Host "File db.env not found in the current working directory. The script cannot proceed." -ForegroundColor Red
    exit
}
#--------------------------------------------------------------------
Write-Host ("Copying the agent to $OutputPath") -ForegroundColor Yellow
#reusing agent path
$AgentPath= $OutputPath + "\windows-endpoint-mysql-db-agent\agent\windows-build\windows-authnull-db-agent.exe"
Copy-Item -Path $AgentPath -Destination $OutputPath -Force -Verbose

#---------------------------------------------------------------------------
# Function to read a password with completely hidden input
function Read-Password {
    $password = ""
    while ($true) {
        $key = [System.Console]::ReadKey($true)
        if ($key.Key -eq "Enter") {
            break
        } elseif ($key.Key -eq "Backspace") {
            if ($password.Length -gt 0) {
                $password = $password.Substring(0, $password.Length - 1)
            }
        } else {
            $password += $key.KeyChar
        }
    }
    return $password
}

# Prompt the user for runtime inputs
$DbHost = Read-Host "Enter the database host IP"
$DbUserName = Read-Host "Enter the user name"

# Use the custom Read-Password function to hide the password input
Write-Host "Enter the database password:" -NoNewline
$DbPassword = Read-Password 

# Hardcode the mode as 'service'
#$mode = "service"

# Escape the password for command-line compatibility
$EscapedPassword = "`"$DbPassword`""


# Save credentials to db.env file
$envFileContent = @"
DB_HOST=$DbHost
DB_USER=$DbUserName
DB_PASSWORD=$EscapedPassword
"@

$envFileContent | Add-Content -Path $destinationPath -Force
Write-Host "Database credentials saved to db.env." -ForegroundColor Green


# # Command to run the Go agent
# $command = "C:\authnull-db-agent\windows-mysql-db-agent.exe --host `"$DbHost`" --username `"$DbUserName`" --password `"$EscapedPassword`" --apikey `"$ApiKey`""

# # Output the command for debugging 
# #Write-Host "Command: $command"

# # run the command
# Invoke-Expression $command

#---------------------------------------------------------------------------
# Create Windows Service

try {
    New-Service -Name "AuthNullDBAgent" -BinaryPathName $OutputPath"\windows-authnull-db-agent.exe" 
    Start-Service AuthNullDBAgent -WarningAction SilentlyContinue
}
catch {
    Write-Host "Registering AuthNull Agent failed!" -ForegroundColor Red
}
finally {
    # Do this after the try block regardless of whether an exception occurred or not
}
Get-Service AuthNullDBAgent
Write-Host "The path of the agent is " $OutputPath"\windows-authnull-db-agent.exe" -ForegroundColor Yellow
