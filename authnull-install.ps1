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
    Write-Host "Output directory already exists. Skipping download and extraction." -ForegroundColor Yellow
    
}

# Define the URL of the file to download
$url = "https://github.com/authnull0/windows-endpoint/archive/refs/heads/main.zip"

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


$InstallerPath= $OutputPath + "\Windows-endpoint-main\windows-endpoint-main\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"


 
if (-not $InstallerPath) {
    Write-Host "Installation path does not exist" -ForegroundColor Yellow
    exit
} 
 

#$InstallerPath="C:\Downloads\Windows-endpoint-main\windows-endpoint-main\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"

# Check if the installer executable exists
if (Test-Path $InstallerPath) {
    try {
        # Start the installation process
        $process = Start-Process -FilePath $InstallerPath -PassThru -Wait
        
        # Check the exit code to determine if the installation was successful
        if ($process.ExitCode -eq 0) {
            Write-Host "Installation completed successfully." -ForegroundColor Green
        } else {
            Write-Host "Installation failed with exit code $($process.ExitCode)." -ForegroundColor Red
        }
    } 
    catch {
        Write-Host "Error occurred during installation: $_" -ForegroundColor Red
    }
} 
else {
    Write-Host "Installer not found at: $InstallerPath" -ForegroundColor Red
}




#modify machine config
# Define the path to the machine.config file
$machineConfigPath = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\Config\machine.config"

# Define the replacement string
$replacementString = "<runtime> <loadFromRemoteSources enabled=`"true`"/> </runtime>"

# Check if the file exists
if (Test-Path $machineConfigPath) {
    try {
        # Read the contents of the file as plain text
        $fileContent = Get-Content -Path $machineConfigPath -Raw
        
        # Check if the <runtime> tag already exists
        if ($fileContent -match '<runtime />') {
            # Check if the <runtime> tag has already been modified
            if ($fileContent -notmatch '<runtime>.*?<loadFromRemoteSources enabled="true".*?</runtime>') {
                # Replace the <runtime/> tag with the specified replacement
                Write-Host "Machine.config modification...in progress" -ForegroundColor Green
                $newContent = $fileContent -replace '<runtime />', $replacementString
                Write-Host "New string $newContent"
                # Write the updated content back to the file
                $newContent | Set-Content -Path $machineConfigPath -Force
                
                Write-Host "Machine.config modification completed successfully." -ForegroundColor Green
            } else {
                Write-Host "Machine.config already contains the required changes." -ForegroundColor Yellow
            }
        } else {
            Write-Host "The <runtime> tag is not found in the machine.config file." -ForegroundColor Red
        }
    } 
    catch {
        Write-Host "Error occurred during modification: $_" -ForegroundColor Red
    }
} 
else {
    Write-Host "Machine.config file not found at: $machineConfigPath" -ForegroundColor Red
}



#write c:\authnull-agent folder and write app.env file
# Define the path where the environment file should be saved
$envFilePath = "C:\authnull-agent\app.env"

# Check if the directory exists; if not, create it
if (-not (Test-Path -Path "C:\authnull-agent" -PathType Container)) {
    try {
        New-Item -Path "C:\authnull-agent" -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: C:\authnull-agent" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create directory: $_" -ForegroundColor Red
        exit
    }
}

# Ask for the content of the environment file
$envContent = Read-Host "Enter the content of the environment file (press Enter to finish):"


# Prompt the user for input
Write-Host "Please enter the content for the text file. Press Enter on a blank line to finish."
$envContent = ""
do {
    $line = Read-Host
    if (-not [string]::IsNullOrEmpty($line)) {
        $envContent += "$line`n" # Append the line to the text blob
    }
} while (-not [string]::IsNullOrEmpty($line))

# Define the path for the text file
$agentFile = "C:\authnull-agent\app.env"

# Write the text blob to the text file
try {
    $envContent | Out-File -FilePath $agentFile -Encoding utf8
    Write-Host "Config saved successfully to: $agentFile" -ForegroundColor Green
} catch {
    Write-Host "Failed to save Config: $_" -ForegroundColor Red
}

# Create or overwrite the environment file with the provided content
try {
    $envContent | Out-File -FilePath $envFilePath -Encoding utf8
    Write-Host "Environment file saved successfully to: $envFilePath" -ForegroundColor Green
} catch {
    Write-Host "Failed to save environment file: $_" -ForegroundColor Red
}

# Log using high verbosity
Write-Host "Script execution completed." -ForegroundColor Cyan


Write-Host "Extracting agent"

$AgentPath= $OutputPath + "\Windows-endpoint-main\windows-endpoint-main\agent\windows-build.zip"



if (Test-Path $AgentPath) {
    # Extract the file
        try {
            Expand-Archive -Path "$OutputPath\file.zip" -DestinationPath $OutputPath -Force
            Write-Host "Extraction completed successfully." -ForegroundColor Green
        } catch {
            Write-Host "Extraction failed: $_" -ForegroundColor Red
        }
    } 
    else {
        Write-Host "Zip file not found at: $zipFilePath" -ForegroundColor Red
    }

#reusing agent path
$AgentPath= $OutputPath + "\Windows-endpoint-main\windows-endpoint-main\agent\windows-build\windows-build\windows-agent-amd64.exe"



Copy-Item -Path $AgentPath -Destination "C:\authnull-agent" -Force -Verbose

try {
    New-Service -Name "AuthNullAgent" -BinaryPathName "C:\authnull-agent\windows-agent-amd64.exe"

    Start-Service AuthNullAgent
} catch {
    Write-Host "Registering AuthNull Agent failed!" -ForegroundColor Red
}
finally {
    # Do this after the try block regardless of whether an exception occurred or not
}



#copy plugins 

# Define the source directory path
$sourceDirectory = $OutputPath + "\Windows-endpoint-main\windows-endpoint-main\credential-provider\plugins" 

# Define the destination directory path
Write-Host "Copying plugins... please wait" -ForegroundColor Red
$destinationDirectory = "C:\program files\pGina\plugins\authnull-plugins"

# Check if the directory exists; if not, create it
if (-not (Test-Path -Path  $destinationDirectory -PathType Container)) {
    try {
        New-Item -Path $destinationDirectory -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $destinationDirectory" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create directory: $_" -ForegroundColor Red
        exit
    }
}

# Copy files from source directory to destination directory
Copy-Item -Path "$sourceDirectory\*" -Destination $destinationDirectory -Recurse -Force -Verbose
Write-Host "Copied files successfully to the plugin folder. Open Pgina and configure plugins.." -ForegroundColor Green


#copy depedency dlls
Write-Host "Copying dependencies .." -ForegroundColor Green
$sourceDirectory = $OutputPath + "\windows-endpoint-main\windows-endpoint-main\credential-provider\dll-dependencies" 
$destinationDirectory = "C:\program files\system32" 

Copy-Item -Path "$sourceDirectory\*" -Destination $destinationDirectory -Recurse -Force -Verbose
Write-Host "Copied dependencies successfully" -ForegroundColor Green

 
# Define the registry key path
$registryKeyPath = "HKLM:\Software\Pgina3"

# Define the name of the multi-string value
$valueName = "PluginDirectories"

$destinationDirectory = "C:\program files\pGina\plugins\authnull-plugins"
# Define the new value data
$newValueData = @(
    $destinationDirectory 
)

# Set the multi-string value
try {
    Set-ItemProperty -Path $registryKeyPath -Name $valueName -Value $newValueData -Type MultiString -Force -Verbose
    Write-Host "Registry value modified successfully." -ForegroundColor Green
} catch {
    Write-Host "Failed to modify registry value: $_" -ForegroundColor Red
}




#force restart pgina service
Write-Host "Restarting pgina: $_" -ForegroundColor Green

Restart-Service -Name "pGina" -Force

# Stop the process



# Start the process again
Start-Process -FilePath "C:\Program Files\pGina\pGina.Configuration.exe"


#Update other registry items for active directory plugin


# Define the registry key path
$registryKeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\pGina3\Plugins\0f52390b-c781-43ae-bd62-553c77fa4cf7"

# Define the name of the multi-string value
$valueName =   Read-Host "Please enter a DN pattern"

# Define the new value data
$newValueData = @(
    $valueName 
)


Set-ItemProperty -Path $registryKeyPath -Name "DnPattern" -Value "NewValue"

 

# Define the name of the multi-string value
$valueName =   Read-Host "Please enter a DN pattern"

# Define the new value data
$newValueData = @(
    $valueName 
)


Set-ItemProperty -Path $registryKeyPath -Name "DnPattern" -Value $newValueData


# Define the registry key path
$registryKeyPath = "HKLM:\SOFTWARE\pGina3\Plugins\0f52390b-c781-43ae-bd62-553c77fa4cf7"

# Define the name of the multi-string value\\

$valueName =   Read-Host "Please enter a search DN pattern"

# Define the new value data
$newValueData = @(
    $valueName 
)



Set-ItemProperty -Path $registryKeyPath -Name "SearchDN" -Value  $newValueData

 
$valueName =   Read-Host "Please enter a DN pattern"

# Define the new value data
$newValueData = @(
    $valueName 
)


Set-ItemProperty -Path $registryKeyPath -Name "DnPattern" -Value  $newValueData

 

 

# Define the name of the multi-string value
$valueName =   Read-Host "Please enter a Group DN pattern"

# Define the new value data
$newValueData = @(
    $valueName 
)

Set-ItemProperty -Path $registryKeyPath -Name "GroupDNPattern" -Value $newValueData 



 

# Define the name of the multi-string value


Set-ItemProperty -Path $registryKeyPath -Name "GroupGatewayRules" -Value "Users0administrators"

$valueName =   Read-Host "Please enter a LDAP Host URL"

# Define the new value data
$newValueData = @(
    $valueName 
)

Set-ItemProperty -Path $registryKeyPath -Name "LdapHost" -Value $newValueData 


 
Write-Host "Configured LDAP Successfully.." -ForegroundColor Red
 

$registryKeyPath = "HKLM:\SOFTWARE\pGina3\Plugins\12fa152d-a2e3-4c8d-9535-5dcd49dfcb6d"

Set-ItemProperty -Path $registryKeyPath -Name "AlwaysAuthenticate" -Value "false" 

Set-ItemProperty -Path $registryKeyPath -Name "ApplyAuthZtoAllUsers" -Value "true" 

Set-ItemProperty -Path $registryKeyPath -Name "ScramblePasswordsWhenLMAuthFails" -Value "false" 


Set-ItemProperty -Path $registryKeyPath -Name "AuthZLocalGroupsOnly" -Value "false" 


Write-Host "Disabling network level authentication.." -ForegroundColor Green

Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 0


