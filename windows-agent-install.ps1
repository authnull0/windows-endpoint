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
#-------------------------------------------------------------------------------------
# Define the URL of the file to download
$url = "https://github.com/authnull0/windows-endpoint/archive/refs/heads/windows-agent.zip"

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

#-----------------------------------------------------------------------
#Installing pGina
$InstallerPath= $OutputPath + "\windows-endpoint-main\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"


 
if (-not $InstallerPath) {
    Write-Host "Installation path does not exist" -ForegroundColor Yellow
    exit
} 
 


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


#-------------------------------------------------------------------------------------

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

        
        # Check if the <runtime> tag has already been modified
        if ($fileContent -match '<runtime>.*?<loadFromRemoteSources enabled="true".*?</runtime>'){
            Write-Host "Machine.config already contains the required changes." -ForegroundColor Yellow
        }


        
       
        elseif ($fileContent -match '<runtime />') {
           if ($fileContent -notmatch '<runtime>.*?<loadFromRemoteSources enabled="true".*?</runtime>') {
                # Replace the <runtime/> tag with the specified replacement
                Write-Host "Machine.config modification...in progress" -ForegroundColor Green
                $newContent = $fileContent -replace '<runtime />', $replacementString
                Write-Host "New string $newContent"
                # Write the updated content back to the file
                $newContent | Set-Content -Path $machineConfigPath -Force
                
                Write-Host "Machine.config modification completed successfully." -ForegroundColor Green
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

#-----------------------------------------------------------------------

#write c:\authnull-agent folder and write app.env file
# Define the path where the environment file should be saved
$envFilePath = "C:\authnull-agent\app.env"

# Ask for the content of the environment file
$envContent = Read-Host "Enter the content of the environment file (press Enter twice to finish):"


# Prompt the user for input
$envContent = ""
do {
    $line = Read-Host
    if (-not [string]::IsNullOrEmpty($line)) {
        $envContent += "$line`n" # Append the line to the text blob
    }
} while (-not [string]::IsNullOrEmpty($line))

# Write the text blob to the text file
try {
   # $envContent | Out-File -FilePath $agentFile -Encoding utf8
    if (-not [string]::IsNullOrEmpty($envContent)) {
        $envContent | Out-File -FilePath $envFilePath -Encoding utf8
        Write-Host "Config saved successfully to: $envFilePath" -ForegroundColor Green
    } else {
        Write-Host "The content to be written to the file is null or empty" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to save Config: $_" -ForegroundColor Red
}

<# Create or overwrite the environment file with the provided content
try {

    if (-not [string]::IsNullOrEmpty($envContent)) {
        $envContent | Out-File -FilePath $envFilePath -Encoding utf8
        Write-Host "Environment file saved successfully to: $envFilePath" -ForegroundColor Green
    } else {
        Write-Host "The content to be written to the file is null or empty." -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "Failed to save environment file: $_" -ForegroundColor Red
}
#>

#----------------------------------------------------------------------
# Log using high verbosity
Write-Host "Script execution completed." -ForegroundColor Cyan


Write-Host "Extracting agent"

$AgentPath= $OutputPath + "\windows-endpoint-main\agent\windows-build.zip"



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
$AgentPath= $OutputPath + "\windows-endpoint-main\agent\windows-build\windows-agent-amd64.exe"



Copy-Item -Path $AgentPath -Destination "C:\authnull-agent" -Force -Verbose

try {
    New-Service -Name "AuthNullAgent" -BinaryPathName "C:\authnull-agent\windows-agent-amd64.exe" 

    Start-Service AuthNullAgent -WarningAction SilentlyContinue
} catch {
    Write-Host "Registering AuthNull Agent failed!" -ForegroundColor Red
}
finally {
    # Do this after the try block regardless of whether an exception occurred or not
}

#--------------------------------------------------------------------------

#copy plugins 

# Define the source directory path
$sourceDirectory = $OutputPath + "\windows-endpoint-main\credential-provider\plugins" 

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
#--------------------------------------------------------------------
# Copy files from source directory to destination directory
Copy-Item -Path "$sourceDirectory\*" -Destination $destinationDirectory -Recurse -Force -Verbose
Write-Host "Copied files successfully to the plugin folder. Open Pgina and configure plugins.." -ForegroundColor Green


#copy depedency dlls
Write-Host "Copying dependencies .." -ForegroundColor Green
$sourceDirectory = $OutputPath + "\windows-endpoint-main\credential-provider\dll-dependencies" 
$destinationDirectory = "C:\program files\system32" 

Copy-Item -Path "$sourceDirectory\*" -Destination $destinationDirectory -Recurse -Force -Verbose
Write-Host "Copied dependencies successfully" -ForegroundColor Green

#----------------------------------------------------------
#updating group policy to enable and disable respective credential providers
# Define paths
$lgpoPath = "C:\authnull-agent\GPO\LGPO.exe"
$backupFolder = "C:\authnull-agent\GPO\registry.pol"

# Step 1: Create a backup of current group policy settings
Start-Process -FilePath $lgpoPath -ArgumentList "/m $backupFolder" -Wait
gpupdate /force

#----------------------------------------------------------------------------
#plugin directory
# Define the registry key path
$registryKeyPath = "HKLM:\Software\Pgina3"

# Define the name of the multi-string value
$valueName = "PluginDirectories"

$destinationDirectory = "C:\program files\pGina\plugins\authnull-plugins"
Set-ItemProperty -Path $registryKeyPath -Name $valueName -Value $destinationDirectory -Force -Verbose -Type MultiString 
Write-Host "Plugin selection - search directory modified successfully..." -ForegroundColor Green

#------------------------------------------------------------------------------------------
#current plugins
# Define the registry key path
$registryKeyPath = "HKLM:\Software\Pgina3"
$hexaValue=0x0000000e

# Define the name of the multi-string value

Set-ItemProperty -Path $registryKeyPath -Name "0f52390b-c781-43ae-bd62-553c77fa4cf7" -Value $hexaValue -Force -Verbose -Type DWORD 
Set-ItemProperty -Path $registryKeyPath -Name "12FA152D-A2E3-4C8D-9535-5DCD49DFCB6D" -Value $hexaValue -Force -Verbose -Type DWORD 

Write-Host "Plugin selection - Current plugins selected successfully..." -ForegroundColor Green
#---------------------------------------------------------------------------------------------------------

#verify the plugins order
$registryKeyPath = "HKLM:\SOFTWARE\pGina3"

$multiLineContent = @"
0f52390b-c781-43ae-bd62-553c77fa4cf7
12fa152d-a2e3-4c8d-9535-5dcd49dfcb6d
"@

Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthentication_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthorization_Order" -Value $multiLineContent -Force -Verbose -Type MultiString
Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthenticationGateway_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
#Set-ItemProperty -Path $registryKeyPath -Name "IPluginGateway_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
#-----------------------------------------------------------------------------------------

# Step 3: Verify LDAP authentication configuration
$ldapRegistryPath = "HKLM:\SOFTWARE\pGina3\Plugins\0f52390b-c781-43ae-bd62-553c77fa4cf7"

# Set LDAP server address and port in the registry
$ldapRegistryPath = "HKLM:\SOFTWARE\pGina3\Plugins\0f52390b-c781-43ae-bd62-553c77fa4cf7"
Set-ItemProperty -Path $ldapRegistryPath -Name "LdapHost" -Value "10.0.0.4" -Force

Set-ItemProperty -Path $ldapRegistryPath -Name "GroupDnPattern" -Value "cn=Users,cn=Authnull2,cn=com,CN=%u,CN=Users,DC=authnull2,DC=com" -Force -Verbose

Set-ItemProperty -Path $ldapRegistryPath -Name "DnPattern" -Value "CN=%u,CN=Users,DC=authnull2,DC=com" -Force -Verbose

Set-ItemProperty -Path $ldapRegistryPath -Name "SearchDn" -Value "CN=%u,CN=Users,DC=authnull2,DC=com" -Force -Verbose

#Set-ItemProperty -Path $ldapRegistryPath -Name "LdapPort" -Value 389 -Force -Verbose -Type 

Write-Host "LDAP configuration updated successfully." -ForegroundColor Green
#-----------------------------------------------------------------------------------------------------------------------------

# Start the process again
Start-Process -FilePath "C:\Program Files\pGina\pGina.Configuration.exe"

#------------------------------------------------------------------------------------------------------------------------------------
