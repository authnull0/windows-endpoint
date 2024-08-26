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


# Check if pGina already installed
$uninstallPath = "C:\Program Files\pGina\unins000.exe"

# Check if the uninstaller executable exists
if (Test-Path $uninstallPath -PathType Leaf) {
    try{
    # Start the uninstaller process
    Write-Host "Uninstalling the already configured pGina" -ForegroundColor Yellow
    Start-Process -FilePath $uninstallPath -ArgumentList "/SILENT" -Wait
    Write-Host "pGina uninstalled successfully." -ForegroundColor Green
}
catch {
    Write-Host "Uninstalling Pgina Failed: $_" -ForegroundColor Red
}
} else {
    Write-Host "Uninstaller not found at $uninstallPath." -ForegroundColor Red
}

$pginaPath = "C:\Program Files\pGina"

if(Test-Path $pginaPath)
{
    try{
        Remove-Item -Path $pginaPath -Force -Recurse -WarningAction SilentlyContinue
        Write-Host "Pgina folder in C Drive removed sucessfully..." -ForegroundColor Green
    }
    catch{
        Write-Host "Pgina folder cannot be deleted: $_" -ForegroundColor Red 
    }
}

#Deleting dlls
$files = @("C:\Windows\System32\golib.dll", "C:\Windows\System32\pGinaGINA.dll")

foreach ($file in $files) {
    if (Test-Path -Path $file) {
        try {
            Remove-Item -Path $file -Force
            Write-Host "Deleted $file successfully.." -ForegroundColor Green
        } catch {
            Write-Host "Failed to delete $file" -ForegroundColor Red
        }
    } else {
        Write-Host "$file does not exist" -ForegroundColor Yellow
    }
}


#Deleting the pGina3 registry key values
$keyPath = "HKLM:\Software\pGina3"

# Check if the registry key exists
if (Test-Path -Path $keyPath) {
$RegistryKeyPath = "HKLM:\SOFTWARE\pGina3"
# Check if the registry key exists
if (Test-Path -Path $RegistryKeyPath) {
    try{
    # Remove the registry key and all its subkeys and values
    Remove-Item -Path $RegistryKeyPath -Recurse -Force
    Write-Host "Registry key and all subkeys and values deleted successfully." -ForegroundColor Green
    }

    catch{
        Write-Host "Failed to delete pgina registry keys and values: $_" -ForegroundColor Red
    }

} 
else {
    Write-Host "Registry key does not exist." -ForegroundColor Yellow
}

    } 
else {
    Write-Host "Registry key '$keyPath' not found." -ForegroundColor Yellow
}
#-------------------------------------------------------------------------------------
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

#---------------------------------------------------------------------------------
# Define the path where the environment file should be saved
if (-not (Test-Path -Path "C:\authnull-agent\app.env" -PathType Leaf)) {
    try {
        New-Item -Path "C:\authnull-agent\app.env" -ItemType File -Force | Out-Null
        Write-Host "Created file: C:\authnull-agent\app.env" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create app.env: $_" -ForegroundColor Red
        exit
    }
}


Write-Host "Copy and paste the content to C:\authnull-agent\app.env file. Ensure the first line is not blank. Save the file..." -ForegroundColor Green
Read-Host "After saving the file press ENTER to continue" 

#$envFilePath = "C:\authnull-agent\app.env"
# $envCount=0
# $blank="_"
# Write-Host "Please enter the content for the text file. Press Enter on a blank line to finish. Ensure the first line is not blank."
# $envContent = ""
# do {
#     $line = Read-Host
#     if (-not [string]::IsNullOrEmpty($line)) {
#         $envContent += "$line`n" # Append the line to the text blob
#     } else {
#             $envCount=$envCount+1
#             if ($envCount -gt 1) { 
#                 $blank=""
#             }
#     }
# } while (-not [string]::IsNullOrEmpty($blank))

# # Define the path for the text file
# $agentFile = "C:\authnull-agent\app.env"

# # Write the text blob to the text file
# try {
#    # $envContent | Out-File -FilePath $agentFile -Encoding utf8
#     if (-not [string]::IsNullOrEmpty($envContent)) {
#         $envContent | Out-File -FilePath $agentFile -Encoding utf8
#         Write-Host "Config saved successfully to: $agentFile" -ForegroundColor Green
#     } else {
#         Write-Host "The content to be written to the file is null or empty" -ForegroundColor Yellow
#     }
# } catch {
#     Write-Host "Failed to save Config: $_" -ForegroundColor Red
# }
# # Create or overwrite the environment file with the provided content
# try {
   
#     if (-not [string]::IsNullOrEmpty($envContent)) {
#         $envContent | Out-File -FilePath $envFilePath -Encoding utf8
#         Write-Host "Config saved successfully to: $envFilePath" -ForegroundColor Green
#     } else {
#         Write-Host "The content to be written to the file is null or empty" -ForegroundColor Yellow
#     }
# } catch {
#     Write-Host "Failed to save Config: $_" -ForegroundColor Red
# }
 
#---------------------------------------------------------------------------
Write-Host "Extracting agent" -ForegroundColor Yellow

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
Copy-Item -Path $AgentPath -Destination $OutputPath -Force -Verbose


try {
    New-Service -Name "AuthNullAgent" -BinaryPathName $OutputPath"\windows-agent-amd64.exe" 
    Start-Service AuthNullAgent -WarningAction SilentlyContinue
} catch {
    Write-Host "Registering AuthNull Agent failed!" -ForegroundColor Red
}
finally {
    # Do this after the try block regardless of whether an exception occurred or not
}
Get-Service AuthNullAgent
Write-Host "The path of the agent is " $OutputPath"\windows-agent-amd64.exe" -ForegroundColor Yellow


#-------------------------------------------------------------------------------------

#Installing pGina
$InstallerPath= $OutputPath + "\windows-endpoint-main\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"

if (-not $InstallerPath) {
    Write-Host "Installation path does not exist" -ForegroundColor Yellow
    exit
} 
 # Check if the installer executable exists
if (Test-Path $InstallerPath) {
#Installing pGina
$InstallerPath= $OutputPath + "\windows-endpoint-main\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"
Write-Host "After installation completed please CLOSE the pGina" -ForegroundColor Yellow
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
#--------------------------------------------------------------------------
#copy plugins 

# Define the source directory path
$sourceDirectory = $OutputPath + "\windows-endpoint-main\credential-provider\plugins" 

# Define the destination directory path
Write-Host "Copying plugins... please wait" -ForegroundColor Yellow
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
Write-Host "Copied files successfully to the plugin folder." -ForegroundColor Green


#-------------------------------------------------------------------------------------
#copy depedency dlls
Write-Host "Copying dependencies .." -ForegroundColor Green
$sourceDirectory = $OutputPath + "\windows-endpoint-main\credential-provider\dll-dependencies" 
$destinationDirectory = "C:\Windows\System32" 

Copy-Item -Path "$sourceDirectory\*" -Destination $destinationDirectory -Recurse -Force -Verbose
Write-Host "Copied dependencies successfully." -ForegroundColor Green

#--------------------------------------------------------------------------
#updating group policy to enable and disable respective credential providers

$lgpoPath = $OutputPath+"\windows-endpoint-main\gpo\LGPO.exe"
$backupFolder = $OutputPath+"\windows-endpoint-main\gpo\registry.pol"
$infFilePath = $OutputPath + "\windows-endpoint-main\gpo\securitySettings.inf"
    
try{
    Start-Process -FilePath $lgpoPath -ArgumentList "/s $infFilePath"
    Write-Host "Security settings installed successfully." -ForegroundColor Green
    } 
catch{
        Write-Host "Security setting installation failed : $_" -ForegroundColor Red
    }

try{
    Start-Process -FilePath $lgpoPath -ArgumentList "/m $backupFolder" -Wait
    Write-Host "Group policy updated sucessfully." -ForegroundColor Green
}
catch{
    Write-Host "Group policy updation failed: $_" -ForegroundColor Red
}           
    
#---------------------------------------------------------------------
Write-Host "Configuring pgina for both local user and AD user authentication" -ForegroundColor Green
# Define the path to your registry file
$registryFilePath = $OutputPath +"\windows-endpoint-main\gpo\pgina.reg"

# Check if the file exists
try{
if (Test-Path $registryFilePath) {
    # Import the registry file using regedit
    Start-Process -FilePath "regedit.exe" -ArgumentList "/s `"$registryFilePath`"" -Wait

    # Optionally, check if the import was successful
    Write-Host "Registry file imported successfully." -ForegroundColor Green
} else {
    Write-Output "Registry file not found: $registryFilePath" -ForegroundColor Red
}
}

catch{
    Write-Host "Failed to update registry : $_" -ForegroundColor Red
}
#-----------------------------------------------------------------------
#Setting LocalAdminFallback Registry 
set-ItemProperty -Path "HKLM:\Software\pGina3\plugins\12fa152d-a2e3-4c8d-9535-5dcd49dfcb6d" -Name "LocalAdminFallBack" -Value "True" -Type String -Force -Verbose
Write-Host "Local Admin Fallback registry added successfully.." -ForegroundColor Green
#--------------------------------------------------------------------------------

Write-Host "LDAP Plugin Settings" -ForegroundColor Green
$registryFilePath = $OutputPath +"\windows-endpoint-main\gpo\ldap.reg"
try{
# Check if the file exists
if (Test-Path $registryFilePath) {
    # Import the registry file using regedit
    Start-Process -FilePath "regedit.exe" -ArgumentList "/s `"$registryFilePath`"" -Wait
    Write-Host "Ldap Registry file imported successfully." -ForegroundColor Green
} else {
    Write-Output " ldap Registry file not found: $registryFilePath" -ForegroundColor Red
}
}
catch{
    Write-Host "Failed to update LDAP registry : $_" -ForegroundColor Red
}
#---------------------------------------------------------------------------------------
#update the LDAP configuration settings
# Define the registry key path
$registryKeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\pGina3\Plugins\0f52390b-c781-43ae-bd62-553c77fa4cf7"

# Define the name of the multi-string value
$valueName =   Read-Host "Please enter a DN pattern"

# Define the new value data
$newValueData = @(
    $valueName 
)


Set-ItemProperty -Path $registryKeyPath -Name "DnPattern" -Value $newValueData
# Define the new value data
$newValueData = @(
    $valueName 
)

Set-ItemProperty -Path $registryKeyPath -Name "GroupDNPattern" -Value $newValueData 


# Define the name of the multi-string value\\

$valueName =   Read-Host "Please enter a search DN pattern"

# Define the new value data
$newValueData = @(
    $valueName 
)
Set-ItemProperty -Path $registryKeyPath -Name "SearchDN" -Value  $newValueData

$valueName =   Read-Host "Please enter a LDAP Host URL"

# Define the new value data
$newValueData = @(
    $valueName 
)

Set-ItemProperty -Path $registryKeyPath -Name "LdapHost" -Value $newValueData 


 
Write-Host "Configured LDAP Successfully.." -ForegroundColor Red



#---------------------------------------------------------------------------------------------
# Start the process again
try{
Start-Process -FilePath "C:\Program Files\pGina\pGina.Configuration.exe" -NoNewWindow
Write-Host "Restarting pGina" -ForegroundColor Green

}
catch{
    Write-Host "Restarting pGina failed: $_" -ForegroundColor Red
}
<#------------------------------------------------------------------------------------------------------------------------------------
Restart Computer
try{
    Restart-Computer -Force
}
catch{
    Write-Host "Restarting computer failed: $_" -ForegroundColor Red
}
#>
