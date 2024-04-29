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
#Specify the file path where you want to save the content
 
# Define the path where the environment file should be saved

if (-not (Test-Path -Path "C:\authnull-agent" -PathType Container)) {
    try {
        New-Item -Path "C:\authnull-agent" -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: C:\authnull-agent" -ForegroundColor Green
    } catch {
        Write-Host "Failed to create directory: $_" -ForegroundColor Red
        exit
    }
}

$envFilePath = "C:\authnull-agent\app.env"
$envCount=0
$blank="_"
Write-Host "Please enter the content for the text file. Press Enter on a blank line to finish. Ensure the first line is not blank."
$envContent = ""
do {
    $line = Read-Host
    if (-not [string]::IsNullOrEmpty($line)) {
        $envContent += "$line`n" # Append the line to the text blob
    } else {
            $envCount=$envCount+1
            if ($envCount -gt 1) { 
                $blank=""
            }
    }
} while (-not [string]::IsNullOrEmpty($blank))

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
Write-Host "Agent env file saving completed." -ForegroundColor Cyan



 

# Check if the file exists and if it's empty
 
#---------------------------------------------------------------------------
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
    New-Service -Name "AuthNullAgent6" -BinaryPathName $OutputPath"\windows-agent-amd64.exe" 
    Write-Host "The path of the agent is " $OutputPath "\windows-agent-amd64.exe" 
    Start-Service AuthNullAgent6 -WarningAction SilentlyContinue
} catch {
    Write-Host "Registering AuthNull Agent failed!" -ForegroundColor Red
}
finally {
    # Do this after the try block regardless of whether an exception occurred or not
}


#-------------------------------------------------------------------------------------

#Installing pGina
$InstallerPath= $OutputPath + "\windows-endpoint-windows-agent\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"

if (-not $InstallerPath) {
    Write-Host "Installation path does not exist" -ForegroundColor Yellow
    exit
} 
 # Check if the installer executable exists
if (Test-Path $InstallerPath) {
#Installing pGina
$InstallerPath= $OutputPath + "\windows-endpoint-windows-agent\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"
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
$sourceDirectory = $OutputPath + "\windows-endpoint-windows-agent\credential-provider\plugins" 

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
$sourceDirectory = $OutputPath + "\windows-endpoint-windows-agent\credential-provider\dll-dependencies" 
$destinationDirectory = "C:\program files\system32" 

Copy-Item -Path "$sourceDirectory\*" -Destination $destinationDirectory -Recurse -Force -Verbose
Write-Host "Copied dependencies successfully." -ForegroundColor Green

#--------------------------------------------------------------------------
#updating group policy to enable and disable respective credential providers

$lgpoPath = $OutputPath+"\windows-endpoint-windows-agent\gpo\LGPO.exe"
$backupFolder = $OutputPath+"\windows-endpoint-windows-agent\gpo\registry.pol"
try{
    Start-Process -FilePath $lgpoPath -ArgumentList "/m $backupFolder" -Wait
    Write-Host "Group policy updated sucessfully." -ForegroundColor Green
}
catch{
    Write-Host "Group policy updation failed: $_" -ForegroundColor Red
}



#---------------------------------------------------------------------
#Configuring pGina
Write-Host "Do you want to configure Authnull to manage local users? Press Y/N" -ForegroundColor Green
$choice = Read-Host 
if($choice -eq 'Y'){
$registryKeyPath =  "HKLM:\Software\Pgina3"

# Define the name of the multi-string value
$valueName = "PluginDirectories"
$destinationDirectory = "C:\program files\pGina\plugins\authnull-plugins"
Set-ItemProperty -Path $registryKeyPath -Name $valueName -Value $destinationDirectory -Force -Verbose -Type MultiString 
    
$value = "0x000000e"
Set-ItemProperty -Path $registryKeyPath -Name "0f52390b-c781-43ae-bd62-553c77fa4cf7" -Value $value -Force -Verbose -Type DWORD 
Set-ItemProperty -Path $registryKeyPath -Name "12fa152d-a2e3-4c8d-9535-5dcd49dfcb6d" -Value $value -Force -Verbose -Type DWORD 

#Configuring PGina for LDAP
#$regFilePath  = $OutputPath+"\windows-endpoint-windows-agent\gpo\ldap.reg"
try{

# Check if the file exists
if (Test-Path $regFilePath) {
    # Import the .reg file using regedit.exe
    Start-Process "regedit.exe" -ArgumentList "/s $regFilePath" -Wait
    Write-Host "LDAP Registry file imported successfully." -ForegroundColor Green
} else {
    #Write-Host "LDAP Registry file not found at $regFilePath." -ForegroundColor Red
}
}
catch{
   # Write-Host "Failed to configure LDAP Registry values: $_"  -ForegroundColor Red
}

#plugin order
$multiLineContent = @"
12fa152d-a2e3-4c8d-9535-5dcd49dfcb6d
0f52390b-c781-43ae-bd62-553c77fa4cf7
"@

Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthentication_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthenticationGateway_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthorization_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
Set-ItemProperty -Path $registryKeyPath -Name "IPluginGateway_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 

<#disabling the credential provider
# Define an array of key-value pairs
$keyValuePairs = @"
{1b283861-754f-4022-ad47-a5eaaa618894}	3
{1ee7337f-85ac-45e2-a23c-37c753209769}	3
{2135f72a-90b5-4ed3-a7f1-8bb705ac276a}	3
{25cbb996-92ed-457e-b28c-4774084bd562}	3
{27fbdb57-b613-4af2-9d7e-4fa7a66c21ad}	3
{3dd6bec0-8193-4ffe-ae25-e08e39ea4063}	3
{48b4e58d-2791-456c-9091-d524c6c706f2}	3
{600e7adb-da3e-41a4-9225-3c0399e88c0c}	3
{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}	3
{8fd7e19c-3bf7-489b-a72c-846ab3678c96}	3
{94596c7e-3744-41ce-893e-bbf09122f76a}	3
{bec09223-b018-416d-a0ac-523971b639f5}	3
{c5d7540a-cd51-453b-b22b-05305ba03f07}	3
{cb82ea12-9f71-446d-89e1-8d0924e1256e}	3
{d6886603-9d2f-4eb2-b667-1971041fa96b}	3
{e74e57b0-6c6d-44d5-9cda-fb2df5ed7435}	3
{f64945df-4fa9-4068-a2fb-61af319edd33}	3
{f8a0b131-5f68-486c-8040-7e8fc3c85bb6}	3
{f8a1793b-7873-4046-b2a7-1f318747f427}	3

"@
Write-Host "Registry values have been set successfully."
#>
}
elseif($choice -eq 'N'){

$registryKeyPath =  "HKLM:\Software\Pgina3"

# Define the name of the multi-string value
$valueName = "PluginDirectories"
$destinationDirectory = "C:\program files\pGina\plugins\authnull-plugins"
Set-ItemProperty -Path $registryKeyPath -Name $valueName -Value $destinationDirectory -Force -Verbose -Type MultiString 
    
#$value = "0x000000e"
Set-ItemProperty -Path $registryKeyPath -Name "0f52390b-c781-43ae-bd62-553c77fa4cf7" -Value "0x000000e" -Force -Verbose -Type DWORD 
Set-ItemProperty -Path $registryKeyPath -Name "12fa152d-a2e3-4c8d-9535-5dcd49dfcb6d" -Value "0x0000000" -Force -Verbose -Type DWORD 

#configuring LDAP
$regFilePath  = $OutputPath+"\windows-endpoint-windows-agent\gpo\ldap.reg"
try{

# Check if the file exists
if (Test-Path $regFilePath) {
    # Import the .reg file using regedit.exe
    Start-Process "regedit.exe" -ArgumentList "/s $regFilePath" -Wait
    Write-Host "LDAP Registry file imported successfully." -ForegroundColor Green
} else {
    Write-Host "LDAP Registry file not found at $regFilePath." -ForegroundColor Red
}
}
catch{
    Write-Host "Failed to configure LDAP Registry values: $_"  -ForegroundColor Red
}#>
#plugin order
$multiLineContent = "0f52390b-c781-43ae-bd62-553c77fa4cf7"

Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthentication_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthenticationGateway_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
Set-ItemProperty -Path $registryKeyPath -Name "IPluginAuthorization_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 
Set-ItemProperty -Path $registryKeyPath -Name "IPluginGateway_Order" -Value $multiLineContent -Force -Verbose -Type MultiString 




<#disabling the credential provider
# Define an array of key-value pairs

$keyValuePairs = @"
{1b283861-754f-4022-ad47-a5eaaa618894}	3
{1ee7337f-85ac-45e2-a23c-37c753209769}	3
{2135f72a-90b5-4ed3-a7f1-8bb705ac276a}	3
{25cbb996-92ed-457e-b28c-4774084bd562}	3
{27fbdb57-b613-4af2-9d7e-4fa7a66c21ad}	3
{3dd6bec0-8193-4ffe-ae25-e08e39ea4063}	3
{48b4e58d-2791-456c-9091-d524c6c706f2}	3
{600e7adb-da3e-41a4-9225-3c0399e88c0c}	3
{60b78e88-ead8-445c-9cfd-0b87f74ea6cd}	3
{8fd7e19c-3bf7-489b-a72c-846ab3678c96}	3
{94596c7e-3744-41ce-893e-bbf09122f76a}	3
{bec09223-b018-416d-a0ac-523971b639f5}	3
{c5d7540a-cd51-453b-b22b-05305ba03f07}	3
{cb82ea12-9f71-446d-89e1-8d0924e1256e}	3
{d6886603-9d2f-4eb2-b667-1971041fa96b}	3
{e74e57b0-6c6d-44d5-9cda-fb2df5ed7435}	3
{f64945df-4fa9-4068-a2fb-61af319edd33}	3
{f8a0b131-5f68-486c-8040-7e8fc3c85bb6}	3
{f8a1793b-7873-4046-b2a7-1f318747f427}	3

"@

Set-ItemProperty -Path $registryKeyPath -Name "CredentialProviderFilters" -Value $keyValuePairs -Force -Verbose -Type MultiString 
#>
Write-Host "Registry values have been set successfully."

}
else{
    Write-Host "Please provide the right choice" -ForegroundColor Red
}
#---------------------------------------------------------------------------------------------
#updating group policy to update seucrity settings
Write-Host "Do you want to enable local policy configuration for LDAP users to login locally(Optional)? Press Y/N" -ForegroundColor Green
$securityLocalPolicy = Read-Host 
$lgpoPath = $OutputPath+"\windows-endpoint-windows-agent\gpo\LGPO.exe"
$backupFolder = $OutputPath + "\windows-endpoint-windows-agent\gpo\securitySettings.inf"
    if($securityLocalPolicy -eq 'Y'){
        try{
        Start-Process -FilePath $lgpoPath -ArgumentList "/s $backupFolder" -Wait
        gpupdate /force -ForegroundColor Green
        Write-Host "Security settings installed successfully." -ForegroundColor Green
        } 
        catch{
            Write-Host "Security Setting installation failed : $_" -ForegroundColor Red
        }
}
#--------------------------------------------------------------------------------------------------
# Start the process again
try{
Start-Process -FilePath "C:\Program Files\pGina\pGina.Configuration.exe" -NoNewWindow
Write-Host "Restarting pGina" -ForegroundColor Green

}
catch{
    Write-Host "Restarting pGina failed: $_" -ForegroundColor Red
}
#------------------------------------------------------------------------------------------------------------------------------------
<#Restart Computer
try{
    Restart-Computer -Force
}
catch{
    Write-Host "Restarting computer failed: $_" -ForegroundColor Red
}
#>
