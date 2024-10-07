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

#check ADMFA is enabled or not using env file 
$envFilePath = "C:\authnull-ad-agent\conf.env"
$envFileContent = Get-Content -Path $envFilePath
$envFileContent | ForEach-Object {
    if ($_ -match "ADMFA") {
        $value = $_ -replace "ADMFA=", ""
        if ($value -eq "1") {
            # Variables
            $GitHubURL = "https://https://github.com/authnull0/windows-endpoint/blob/ad-agent/SubAuth.dll"  # URL of the DLL to download
            $DestinationPath = "$env:SystemRoot\System32\SubAuth.dll"  # Destination path for the downloaded DLL
            $RegistryPathLsa = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
            $RegistryPathMSV1 = "$RegistryPathLsa\MSV1_0"
            $DllName = "your-dll-file"  # Name of the DLL without the .dll extension
            $SubAuthValueName = "Auth0"

            # Step 1: Download DLL from GitHub and place it in System32
            try {
                Write-Host "Downloading DLL from $GitHubURL..."
                Invoke-WebRequest -Uri $GitHubURL -OutFile $DestinationPath -UseBasicParsing
                Write-Host "DLL downloaded and placed in $DestinationPath"
            } catch {
                Write-Host "Error downloading the DLL: $_"
                exit
            }

            # Step 2: Modify the MSV1_0 registry key to add the DLL
            try {
                # Check if the MSV1_0 registry key exists and create it if necessary
                if (-not (Test-Path $RegistryPathMSV1)) {
                    New-Item -Path $RegistryPathMSV1 -Force
                }

                # Add the DLL to the MSV1_0 "Auth0" sub-authentication package value
                $MSV1Packages = Get-ItemProperty -Path $RegistryPathMSV1 -Name $SubAuthValueName -ErrorAction SilentlyContinue
                if ($MSV1Packages) {
                    if ($MSV1Packages.$SubAuthValueName -notcontains $DllName) {
                        Write-Host "Appending $DllName to the existing MSV1_0 authentication packages..."
                        $NewMSV1Packages = $MSV1Packages.$SubAuthValueName + @($DllName)
                        Set-ItemProperty -Path $RegistryPathMSV1 -Name $SubAuthValueName -Value $NewMSV1Packages
                    } else {
                        Write-Host "$DllName already exists in MSV1_0 authentication packages."
                    }
                } else {
                    # Create the value if it doesn't exist
                    Write-Host "Creating new MSV1_0 authentication packages registry value..."
                    Set-ItemProperty -Path $RegistryPathMSV1 -Name $SubAuthValueName -Value @($DllName)
                }

                Write-Host "Successfully modified the MSV1_0 registry."
            } catch {
                Write-Host "Error modifying the MSV1_0 registry: $_"
                exit
            }

        # Final step: Notify the user to restart the machine
        Write-Host "You may need to restart the system for changes to take effect."
        } else {
            Write-Host "AD_MFA_ENABLED is set to false. No further action is required."
        }

    }
}