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
} else {
    Write-Host "Zip file not found at: $OutputPath\ad-agent.zip" -ForegroundColor Red
}

# Create folder C:\authnull-ad-agent
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
} else {
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
    } catch {
        Write-Host "Failed to create conf.env file: $_" -ForegroundColor Red
        exit
    }
}

# Add-Content -Path $destinationPath -Value "LDAP_PASSWORD=$securePassword" add in the new line
Add-Content -Path $destinationPath -Value "LDAP_PASSWORD=$securePassword" -NewLine
Write-Host "Password stored successfully in the env file." -ForegroundColor Green

# Start service
try {
    New-Service -Name "AuthNullADAgent" -BinaryPathName "C:\authnull-ad-agent\publish\ADagent.exe"
    Start-Service -Name "AuthNullADAgent" -WarningAction SilentlyContinue
} catch {
    Write-Host "Failed to start service" -ForegroundColor Red
}

Get-Service AuthNullADAgent

# Check ADMFA is enabled or not using env file 
$envFileContent = Get-Content -Path $destinationPath

# Check if the env file exists
if (-not (Test-Path -Path $envFilePath)) {
    Write-Host "The env file does not exist at path: $envFilePath" -ForegroundColor Red
    exit
}

# Read the content of the env file
try {
    $envFileContent = Get-Content -Path $envFilePath
    Write-Host "Successfully read the env file." -ForegroundColor Green
} catch {
    Write-Host "Failed to read the env file: $_" -ForegroundColor Red
    exit
}

# Process each line in the env file
$envFileContent | ForEach-Object {
    if ($_ -match "ADMFA") {
        $value = $_ -replace "ADMFA=", ""
        if ($value -eq "1") {
            # Variables
            $GitHubURL = "https://raw.githubusercontent.com/authnull0/windows-endpoint/ad-agent/SubAuth.dll"  # Corrected URL of the DLL to download
            $DestinationPath = "$env:SystemRoot\System32\SubAuth.dll"  # Destination path for the downloaded DLL
            $RegistryPathLsa = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
            $RegistryPathKerberos = "$RegistryPathLsa\Kerberos"
            $DllName = "SubAuth"
            $SubAuthValueName = "Auth0"  # The name of the sub-authentication package in Kerberos

            # Step 1: Download DLL from GitHub and place it in System32
            try {
                Write-Host "Downloading DLL from $GitHubURL..."
                Invoke-WebRequest -Uri $GitHubURL -OutFile $DestinationPath -UseBasicParsing
                Write-Host "DLL downloaded and placed in $DestinationPath"
            } catch {
                Write-Host "Error downloading the DLL: $_" -ForegroundColor Red
                exit
            }

            # Step 2: Modify the Kerberos registry key to add the DLL
            try {
                # Check if the Kerberos registry key exists and create it if necessary
                if (-not (Test-Path $RegistryPathKerberos)) {
                    New-Item -Path $RegistryPathKerberos -Force
                }

                # Add the DLL to the Kerberos "Auth0" sub-authentication package value
                $KerberosPackages = Get-ItemProperty -Path $RegistryPathKerberos -Name $SubAuthValueName -ErrorAction SilentlyContinue
                if ($KerberosPackages) {
                    Write-Host "Current Kerberos packages: $($KerberosPackages.$SubAuthValueName)" -ForegroundColor Yellow
                    if ($KerberosPackages.$SubAuthValueName -notcontains $DllName) {
                        Write-Host "Appending $DllName to the existing Kerberos authentication packages..."
                        $NewKerberosPackages = $KerberosPackages.$SubAuthValueName + "," + $DllName
                        Set-ItemProperty -Path $RegistryPathKerberos -Name $SubAuthValueName -Value $NewKerberosPackages
                        Write-Host "New Kerberos packages: $NewKerberosPackages" -ForegroundColor Yellow
                    } else {
                        Write-Host "$DllName already exists in Kerberos authentication packages."
                    }
                } else {
                    # Create the value if it doesn't exist
                    Write-Host "Creating new Kerberos authentication packages registry value..."
                    Set-ItemProperty -Path $RegistryPathKerberos -Name $SubAuthValueName -Value $DllName
                    Write-Host "New Kerberos packages: $DllName" -ForegroundColor Yellow
                }

                Write-Host "Successfully modified the Kerberos registry."
            } catch {
                Write-Host "Error modifying the Kerberos registry: $_" -ForegroundColor Red
                exit
            }

            # Final step: Notify the user to restart the machine
            Write-Host "You may need to restart the system for changes to take effect."
        } else {
            Write-Host "ADMFA is set to false. No further action is required."
        }
    }
}
