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
    # Start the uninstaller process
    Write-Host "Uninstalling the already configured pGina" -ForegroundColor Yellow
    Start-Process -FilePath $uninstallPath -ArgumentList "/SILENT" -Wait
    Write-Host "pGina uninstalled successfully." -ForegroundColor Green
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

#---------------------------------------------------------------------------------
# Define the path where the environment file should be saved
$envFilePath = $OutputPath+ "\app.env"

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
#----------------------------------------------------------------------
Write-Host "Extracting agent"

$AgentPath= $OutputPath + "\windows-endpoint-windows-agent\agent\windows-build.zip"



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
$AgentPath= $OutputPath + "\windows-endpoint-windows-agent\agent\windows-build\windows-agent-amd64.exe"



Copy-Item -Path $AgentPath -Destination $OutputPath -Force -Verbose

try {
    New-Service -Name "AuthNullAgent" -BinaryPathName $OutputPath+"\windows-agent-amd64.exe" 

    Start-Service AuthNullAgent -WarningAction SilentlyContinue
} catch {
    Write-Host "Registering AuthNull Agent failed!" -ForegroundColor Red
}
finally {
    # Do this after the try block regardless of whether an exception occurred or not
}


#-----------------------------------------------------------------------
#Installing pGina
$InstallerPath= $OutputPath + "\windows-endpoint-windows-agent\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"


 
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

Write-Host "Closing pGina" -ForegroundColor Yellow
# Get the process associated with pGina
$pginaProcess = Get-Process -Name "pGina.Configuration"

# Check if the pGina process exists
if ($pginaProcess) {
    # Terminate the pGina process
    $pginaProcess | Stop-Process -Force
    Write-Host "pGina application closed successfully." -ForegroundColor Green
} else {
    Write-Host "pGina application is not running." -ForegroundColor Yellow
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
$sourceDirectory = $OutputPath + "\windows-endpoint-windows-agent\credential-provider\plugins" 

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
$sourceDirectory = $OutputPath + "\windows-endpoint-windows-agent\credential-provider\dll-dependencies" 
$destinationDirectory = "C:\program files\system32" 

Copy-Item -Path "$sourceDirectory\*" -Destination $destinationDirectory -Recurse -Force -Verbose
Write-Host "Copied dependencies successfully" -ForegroundColor Green

#---------------------------------------------------------------------
#updating group policy to enable and disable respective credential providers
# Define paths
$lgpoPath = $OutputPath+"\windows-endpoint-windows-agent\gpo\LGPO.exe"
$backupFolder = $OutputPath+"\windows-endpoint-windows-agent\gpo\registry.pol"

# Step 1: Create a backup of current group policy settings
Start-Process -FilePath $lgpoPath -ArgumentList "/m $backupFolder" -Wait
gpupdate /force
#--------------------------------------------------------------------------------
Write-Host "Configuring pGina for LDAP.." -ForegroundColor Yellow 
#Configuring PGina for Local Users and LDAP
$regFilePath = $OutputPath + "\windows-endpoint-windows-agent\gpo\pginaRegistryLDAP.reg"

# Check if the file exists
if (Test-Path $regFilePath) {
    # Import the .reg file using regedit.exe
    Start-Process "regedit.exe" -ArgumentList "/s $regFilePath" -Wait
    Write-Host "LDAP Registry file imported successfully." -ForegroundColor Green
} else {
    Write-Host "LDAP Registry file not found at $regFilePath." -ForegroundColor Red
}
#----------------------------------------------------------------------------

Write-Host "Enter Y to configure for local users or enter N..." -ForegroundColor Green
$options = Read-Host 
if ($options -eq 'Y')
{
#Configuring PGina for Local Users and LDAP
$regFilePath = $OutputPath + "\windows-endpoint-windows-agent\gpo\pginaRegistryLocalUser.reg"

# Check if the file exists
if (Test-Path $regFilePath) {
    # Import the .reg file using regedit.exe
    Start-Process "regedit.exe" -ArgumentList "/s $regFilePath" -Wait
    Write-Host "Local User Registry file imported successfully." -ForegroundColor Green
} else {
    Write-Host "Local User Registry file not found at $regFilePath." -ForegroundColor Red
}

}
else {
Write-Host "Configuring LDAP only..." -ForegroundColor Green

}
#--------------------------------------------------------------------------------------------------
# Start the process again
Start-Process -FilePath "C:\Program Files\pGina\pGina.Configuration.exe" -NoNewWindow

#------------------------------------------------------------------------------------------------------------------------------------
#Restart Computer

#Restart-Computer -Force
