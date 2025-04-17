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
        
    }
    catch {
        Write-Host "Failed to delete directory: $_" -ForegroundColor Red
        exit
    }

    try {
        Write-Host "Creating a new directory.." -ForegroundColor Yellow
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $OutputPath" -ForegroundColor Green   
    }
    catch {
        Write-Host "Failed to create directory: $_ " -ForegroundColor Red

    }

}

else {
    try {
        Write-Host "Creating a new directory.." -ForegroundColor Yellow
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "Created directory: $OutputPath" -ForegroundColor Green   
    }
    catch {
        Write-Host "Failed to create directory: $_ " -ForegroundColor Red
    }
}
# Check if pGina already installed
$uninstallPath = "C:\Program Files\pGina\unins000.exe"

# Check if the uninstaller executable exists
if (Test-Path $uninstallPath -PathType Leaf) {
    try {
        # Start the uninstaller process
        Write-Host "Uninstalling previously configured pGina" -ForegroundColor Yellow
        Start-Process -FilePath $uninstallPath -ArgumentList "/SILENT" -Wait
        Write-Host "pGina uninstalled successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Uninstalling Pgina Failed: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Uninstaller not found at $uninstallPath." -ForegroundColor Red
}

$pginaPath = "C:\Program Files\pGina"

if (Test-Path $pginaPath) {
    try {
        Remove-Item -Path $pginaPath -Force -Recurse -WarningAction SilentlyContinue
        Write-Host "Pgina folder in C Drive removed sucessfully..." -ForegroundColor Green
    }
    catch {
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
        }
        catch {
            Write-Host "Failed to delete $file" -ForegroundColor Red
        }
    }
    else {
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
        try {
            # Remove the registry key and all its subkeys and values
            Remove-Item -Path $RegistryKeyPath -Recurse -Force
            Write-Host "Registry keys and values deleted successfully." -ForegroundColor Green
        }

        catch {
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

try {
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($url, "$OutputPath\file.zip")
    Write-Host "Download completed successfully." -ForegroundColor Green
}
catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    exit
}

if (Test-Path "$OutputPath\file.zip") {
    # Extract the file
    try {
        Expand-Archive -Path "$OutputPath\file.zip" -DestinationPath $OutputPath -Force
        Write-Host "Extraction completed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Extraction failed: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "Zip file not found at: $OutputPath\file.zip" -ForegroundColor Red

}

#---------------------------------------------------------------------------------
# Define the path where the environment file should be saved
# if (-not (Test-Path -Path "C:\authnull-agent\app.env" -PathType Leaf)) {
#     try {
#         New-Item -Path "C:\authnull-agent\app.env" -ItemType File -Force | Out-Null
#         Write-Host "Created file: C:\authnull-agent\app.env" -ForegroundColor Green
#     } catch {
#         Write-Host "Failed to create app.env: $_" -ForegroundColor Red
#         exit
#     }
# }

# Define the source path in the current working directory
$sourcePath = (Get-Location).Path + "\app.env"
$destinationPath = "C:\authnull-agent\app.env"

# Check if the source file exists
if (Test-Path $sourcePath) {
   
    Copy-Item -Path $sourcePath -Destination $destinationPath -Force
    Write-Host "File app.env has been copied to C:\authnull-agent successfully." -ForegroundColor Green
}
else {
    # If the file doesn't exist, stop the script
    Write-Host "File app.env not found in the current working directory. The script cannot proceed." -ForegroundColor Red
    exit
}
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

$AgentPath = $OutputPath + "\windows-endpoint-main\agent\windows-build.zip"

if (Test-Path $AgentPath) {
    # Extract the file
    try {
        Expand-Archive -Path "$OutputPath\file.zip" -DestinationPath $OutputPath -Force
        Write-Host "Extraction completed successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Extraction failed: $_" -ForegroundColor Red
    }
} 
else {
    Write-Host "Zip file not found at: $zipFilePath" -ForegroundColor Red
}

#reusing agent path
$AgentPath = $OutputPath + "\windows-endpoint-main\agent\windows-build\windows-agent-amd64.exe"
Copy-Item -Path $AgentPath -Destination $OutputPath -Force -Verbose


try {
    New-Service -Name "AuthNullAgent" -BinaryPathName $OutputPath"\windows-agent-amd64.exe" 
    Start-Service AuthNullAgent -WarningAction SilentlyContinue
}
catch {
    Write-Host "Registering AuthNull Agent failed!" -ForegroundColor Red
}
finally {
    # Do this after the try block regardless of whether an exception occurred or not
}
Get-Service AuthNullAgent
Write-Host "The path of the agent is " $OutputPath"\windows-agent-amd64.exe" -ForegroundColor Yellow


#-------------------------------------------------------------------------------------


#-----------------------------------------------------------------------
# Check ADMFA flag in app.env and proceed with domain join or pGina install
$envFilePath = "C:\authnull-agent\app.env"
$envContent = Get-Content -Path $envFilePath
$envDict = @{}

foreach ($line in $envContent) {
    if ($line -match "=") {
        $key, $value = $line -split "=", 2
        $envDict[$key.Trim()] = $value.Trim()
    }
}
# Check if ADMFA key exists and print its value
if ($envDict.ContainsKey("ADMFA")) {
    Write-Host "ADMFA flag value: $($envDict["ADMFA"])"
}
else {
    Write-Host "ADMFA flag not found in app.env" -ForegroundColor Red
    exit
}
#print ADMFA flag value
Write-Host "ADMFA flag value: $($envDict["ADMFA"])" -ForegroundColor Yellow
if ($envDict["ADMFA"] -eq "1") {
    # Domain join logic here...
    Write-Host "ADMFA flag is set. Proceeding with domain join." -ForegroundColor Green
    #get details from env file
    $DomainName = $envDict["DomainName"]
    $DomainAdmin = $envDict["DomainAdmin"]
    #ask user to enter password
    $Password = Read-Host "Enter the password for $DomainAdmin" -AsSecureString
    $Credential = New-Object System.Management.Automation.PSCredential($DomainAdmin, $Password)
    $PreferredDNS = $envDict["PreferredDNS"]


    # Update the IPv4 preferred DNS first
    try {
        $Adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        Set-DnsClientServerAddress -InterfaceAlias $Adapter.Name -ServerAddresses $PreferredDNS
        Write-Host "Successfully updated the IPv4 preferred DNS to $PreferredDNS."
    }
    catch {
        Write-Host "Failed to update the IPv4 preferred DNS. Error: $_"
        exit
    }

    # Get the current domain status
    $ComputerSystem = Get-WmiObject Win32_ComputerSystem
    $CurrentDomain = $ComputerSystem.Domain
    $PartOfDomain = $ComputerSystem.PartOfDomain

    # Check if the computer is already part of any domain
    if ($PartOfDomain) {
        if ($CurrentDomain -eq $DomainName) {
            Write-Host "This machine is already a member of the correct domain ($DomainName)."
        }
        else {
            # Remove from the current domain and join the new domain
            try {
                Write-Host "Removing the machine from the domain ($CurrentDomain) and adding it to $DomainName..."
                Remove-Computer -UnjoinDomainCredential $Credential -WorkgroupName "WORKGROUP" -Force -Restart
                Start-Sleep -Seconds 60  # Allow time for the restart

                # After restart, join the new domain
                Add-Computer -DomainName $DomainName -Credential $Credential -Force -Restart
                Write-Host "The machine was successfully moved to the new domain ($DomainName) and will restart again."
            }
            catch {
                Write-Host "Failed to remove or add the machine to the domain. Error: $_"
            }
        }
    }
    else {
        # The computer is not part of any domain, join the new domain
        try {
            Add-Computer -DomainName $DomainName -Credential $Credential -Force -Restart
            Write-Host "The machine was successfully added to the domain ($DomainName) and will now restart."
        }
        catch {
            Write-Host "Failed to add the machine to the domain. Error: $_"
        }
    }

    # Wait for the machine to restart and come back online
    Start-Sleep -Seconds 120  # Adjust the delay if needed

    # Add Domain Admins group to Remote Desktop Users group
    try {
        #get list of groups from env file
        $groups = $envDict["Groups"]
        $groups = $groups -split ","
        foreach ($group in $groups) {
            $group = $group.Trim()  # Trim any leading or trailing whitespace
            $RemoteDesktopGroup = [ADSI]"WinNT://./Remote Desktop Users,group"
            $DomainGroupPath = "WinNT://$DomainName/$group,group"
            try {
                $RemoteDesktopGroup.Add($DomainGroupPath)
                Write-Host "Successfully added '$group' to the 'Remote Desktop Users' group." -ForegroundColor Green
            }
            catch {
                Write-Host "Failed to add '$group' to the 'Remote Desktop Users' group. Error: $_" -ForegroundColor Red
            }
        }

    }
    catch {
        Write-Host "Failed to add 'Domain Admins' to the 'Remote Desktop Users' group. Error: $_"
    }
}
else {

    #Installing Microsoft Visual C++     
    $InstallPath = $OutputPath + "\windows-endpoint-main\credential-provider\pgina\vcRedist_x64.exe"  

    # Check if Visual C++ Redistributable is installed
    $vcRedistKey = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\11.0\VC\Runtimes\x64" 
    $vcRedistInstalled = Test-Path -Path $vcRedistKey

    if ($vcRedistInstalled) {
        Write-Host "Visual C++ X64 Redistributable is already installed." -ForegroundColor Green
    } 
    else {
        # If not installed, check if the installer exists at the specified path
        if (Test-Path $InstallPath) {
            try {
                # Start the installation process
                $process = Start-Process -FilePath $InstallPath -ArgumentList "/quiet", "/norestart" -PassThru -Wait

                # Check the exit code to determine if the installation was successful
                if ($process.ExitCode -eq 0) {
                    Write-Host "Visual C++ Redistributable X64 Installation completed successfully." -ForegroundColor Green
                }
                else {
                    Write-Host "Installation failed with exit code $($process.ExitCode)." -ForegroundColor Red
                }
            } 
            catch {
                Write-Host "Error occurred during installation: $_" -ForegroundColor Red
            }
        } 
        else {
            Write-Host "Installer not found at: $InstallPath" -ForegroundColor Red
        }
    }



    $InstallPath = $OutputPath + "\windows-endpoint-main\credential-provider\pgina\vcredist_x86.exe"  

    # Check if Visual C++ Redistributable is installed
    $vcRedistKey = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\11.0\VC\Runtimes\x86"  
    $vcRedistInstalled = Test-Path -Path $vcRedistKey

    if ($vcRedistInstalled) {
        Write-Host "Visual C++ X86 Redistributable is already installed." -ForegroundColor Green
    } 
    else {
        # If not installed, check if the installer exists at the specified path
        if (Test-Path $InstallPath) {
            try {
                # Start the installation process
                $process = Start-Process -FilePath $InstallPath -ArgumentList "/quiet", "/norestart" -PassThru -Wait

                # Check the exit code to determine if the installation was successful
                if ($process.ExitCode -eq 0) {
                    Write-Host "Visual C++ Redistributable X86 Installation completed successfully." -ForegroundColor Green
                }
                else {
                    Write-Host "Installation failed with exit code $($process.ExitCode)." -ForegroundColor Red
                }
            } 
            catch {
                Write-Host "Error occurred during installation: $_" -ForegroundColor Red
            }
        } 
        else {
            Write-Host "Installer not found at: $InstallPath" -ForegroundColor Red
        }
    }



    #Installing pGina
    $InstallerPath = $OutputPath + "\windows-endpoint-main\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"

    if (-not $InstallerPath) {
        Write-Host "Installation path does not exist" -ForegroundColor Yellow
        exit
    } 
    # Check if the installer executable exists
    if (Test-Path $InstallerPath) {
        #Installing pGina
        $InstallerPath = $OutputPath + "\windows-endpoint-main\credential-provider\pgina\pGinaSetup-3.1.8.0.exe"
        Write-Host "Please close the pGina after installation.." -ForegroundColor Green
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
                }
                else {
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
    #-----------------------------------------------------------------------------
# Add-Type -AssemblyName System.Windows.Forms
# Add-Type -AssemblyName System.Drawing

# # Function to read environment variables from app.env file
# function Get-EnvVariables {
#     param (
#         [string]$filePath
#     )
#     $envDict = @{}
#     $envContent = Get-Content -Path $filePath
#     foreach ($line in $envContent) {
#         if ($line -match "=") {
#             $key, $value = $line -split "=", 2
#             $envDict[$key.Trim()] = $value.Trim()
#         }
#     }
#     return $envDict
# }

# # Function to show a dialog box to get the LDAP username and password from the user
# function Show-CredentialsDialog {
#     $form = New-Object System.Windows.Forms.Form
#     $form.Text = "Enter LDAP Credentials"
#     $form.Size = New-Object System.Drawing.Size(450, 250)  # Increased form size
#     $form.StartPosition = "CenterScreen"
#     $form.Font = New-Object System.Drawing.Font('Arial', 10)  # Set default font

#     # Label for Username
#     $labelUsername = New-Object System.Windows.Forms.Label
#     $labelUsername.Text = "Username:"
#     $labelUsername.Location = New-Object System.Drawing.Point(10, 20)
#     $labelUsername.Size = New-Object System.Drawing.Size(80, 25)
#     $form.Controls.Add($labelUsername)

#     # TextBox for Username
#     $textBoxUsername = New-Object System.Windows.Forms.TextBox
#     $textBoxUsername.Location = New-Object System.Drawing.Point(100, 20)
#     $textBoxUsername.Width = 300  # Increased width
#     $textBoxUsername.Font = New-Object System.Drawing.Font('Arial', 12)  # Increased font size
#     $form.Controls.Add($textBoxUsername)

#     # Label for Password
#     $labelPassword = New-Object System.Windows.Forms.Label
#     $labelPassword.Text = "Password:"
#     $labelPassword.Location = New-Object System.Drawing.Point(10, 60)
#     $labelPassword.Size = New-Object System.Drawing.Size(80, 25)
#     $form.Controls.Add($labelPassword)

#     # TextBox for Password
#     $textBoxPassword = New-Object System.Windows.Forms.TextBox
#     $textBoxPassword.Location = New-Object System.Drawing.Point(100, 60)
#     $textBoxPassword.Width = 300  # Increased width
#     $textBoxPassword.Font = New-Object System.Drawing.Font('Arial', 12)  # Increased font size
#     $textBoxPassword.UseSystemPasswordChar = $true
#     $form.Controls.Add($textBoxPassword)

#     # OK Button
#     $buttonOk = New-Object System.Windows.Forms.Button
#     $buttonOk.Text = "OK"
#     $buttonOk.Location = New-Object System.Drawing.Point(100, 100)
#     $buttonOk.Size = New-Object System.Drawing.Size(80, 35)
#     $buttonOk.Add_Click({
#         $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
#         $form.Close()
#     })
#     $form.Controls.Add($buttonOk)

#     # Cancel Button
#     $buttonCancel = New-Object System.Windows.Forms.Button
#     $buttonCancel.Text = "Cancel"
#     $buttonCancel.Location = New-Object System.Drawing.Point(200, 100)
#     $buttonCancel.Size = New-Object System.Drawing.Size(80, 35)
#     $buttonCancel.Add_Click({
#         $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
#         $form.Close()
#     })
#     $form.Controls.Add($buttonCancel)

#     $form.AcceptButton = $buttonOk
#     $form.CancelButton = $buttonCancel

#     $result = $form.ShowDialog()

#     if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
#         return @{
#             Username = $textBoxUsername.Text
#             Password = $textBoxPassword.Text
#         }
#     } else {
#         return $null
#     }
# }

# # Read environment variables from app.env file
# $envFilePath = "C:\authnull-agent\app.env"
# $envDict = Get-EnvVariables -filePath $envFilePath

# # Get LDAP details from environment variables
# $ldapHost = $envDict["LDAP_HOST"]
# $ldapPort = $envDict["LDAP_PORT"]
# $searchDn = $envDict["SEARCH_DN"]
# $DomainName = $envDict["DomainName"]

# # Show dialog box to get the LDAP username and password from the user
# $credentials = Show-CredentialsDialog

# if ($credentials -eq $null) {
#     Write-Host "LDAP credentials entry was canceled." -ForegroundColor Red
#     exit
# }

# $ldapUsername = $credentials.Username
# $ldapPassword = $credentials.Password

# #Store the Password in app.env file as PASSWORD
# #$envDict["PASSWORD"] = $ldapPassword
# #$envDict | ForEach-Object { "$($_.Key)=$($_.Value)" } | Set-Content -Path $envFilePath

# Log Username and password just for testing
# Write-Host "LDAP Username: $($credentials.Username)"
# Write-Host "LDAP Password: $($credentials.Password)"

# # Function to display a prompt for selecting AD groups
# function Select-ADGroups {
#     param (
#         [string]$ldapHost,
#         [string]$ldapPort,
#         [string]$searchDn,
#         [string]$username,
#         [string]$password
#     )

#     $ldapPath = "LDAP://${ldapHost}:${ldapPort}/${searchDn}"
#     $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry($ldapPath, $username, $password)
#     $directorySearcher = New-Object System.DirectoryServices.DirectorySearcher($directoryEntry)
#     $directorySearcher.Filter = "(objectClass=group)"
#     $directorySearcher.PageSize = 1000
#     $groups = $directorySearcher.FindAll() | ForEach-Object { $_.Properties["name"] } | Sort-Object

#     if ($groups.Count -eq 0) {
#         Write-Host "No groups found in the LDAP search." -ForegroundColor Yellow
#     }

#     $selectedGroups = $groups | Out-GridView -Title "Select AD Groups" -PassThru
#     return $selectedGroups
# }

# # Prompt user to select AD groups
# $selectedGroups = Select-ADGroups -ldapHost $ldapHost -ldapPort $ldapPort -searchDn $searchDn -username $ldapUsername -password $ldapPassword

# if ($selectedGroups -eq $null) {
#     Write-Host "No groups were selected or found." -ForegroundColor Red
#     exit
# }

# # Store selected groups in a file
# $selectedGroups | Out-File -FilePath "C:\selected_user_groups.conf"

# # Read selected groups from the file
# $groups = Get-Content -Path "C:\selected_user_groups.conf"

# foreach ($group in $groups) {
#     $group = $group.Trim()  # Trim any leading or trailing whitespace
#     $RemoteDesktopGroup = "Remote Desktop Users"

#     # Check if the local group exists
#     try {
#         $localGroupExists = net localgroup $group | Out-Null
#         if ($localGroupExists) {
#             Write-Host "Group '$group' exists locally." -ForegroundColor Green
#             $groupExists = $true
#         } else {
#             $groupExists = $false
#             Write-Host "Group '$group' does not exist locally." -ForegroundColor Yellow
#         }
#     }
#     catch {
#         Write-Host "Error checking local group '$group': $_" -ForegroundColor Red
#         $groupExists = $false
#     }

#     if ($groupExists) {
#         # Add local or domain group to 'Remote Desktop Users' group
#         try {
#             net localgroup "Remote Desktop Users" $group /add
#             Write-Host "Successfully added '$group' to the 'Remote Desktop Users' group." -ForegroundColor Green
#         }
#         catch {
#             Write-Host "Failed to add '$group' to the 'Remote Desktop Users' group. Error: $_" -ForegroundColor Red
#         }
#     }
#     else {
#         # If group doesn't exist, create it
#         Write-Host "Creating the group '$group' locally." -ForegroundColor Yellow
#         try {
#             net localgroup $group /add
#             Write-Host "Successfully created local group '$group'." -ForegroundColor Green
#             # Add the newly created local group to the Remote Desktop Users group
#              net localgroup "Remote Desktop Users" $group /add
#             Write-Host "Successfully added local group '$group' to the 'Remote Desktop Users' group." -ForegroundColor Green
#         }
#         catch {
#             Write-Host "Failed to create or add local group '$group' to the 'Remote Desktop Users' group. Error: $_" -ForegroundColor Red
#         }
#     }
# }
    #-------------------------------------------------------------------------------------
#Make an API call to Store the Machine Name , IP Address and The Group Names Selected
# Function to get the machine name and IP address
# function Get-MachineInfo {
#     $machineName = $env:COMPUTERNAME
#     $ipAddress = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet" | Select-Object -First 1).IPAddress
#     return @{
#         MachineName = $machineName
#         IPAddress = $ipAddress
#     }
# }

# # Function to make an API call to store the machine info and selected groups
# function Store-MachineInfo {
#     param (
#         [string]$apiUrl,
#         [hashtable]$machineInfo,
#         [array]$groups,
#         [int]$orgID,
#         [int]$tenantID
#     )

#     $body = @{
#         endpointName = $machineInfo.MachineName
#         ipAddress = $machineInfo.IPAddress
#         groupNames = $groups
#         orgId = $orgID
#         tenantId = $tenantID
#     } | ConvertTo-Json

#     try {
#         $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json"
#         Write-Host "API call successful. Response: $response" -ForegroundColor Green
#     }
#     catch {
#         Write-Host "API call failed: $_" -ForegroundColor Red
#         exit
#     }
# }

# # Read environment variables from app.env file
# $envFilePath = "C:\authnull-agent\app.env"
# $envDict = Get-EnvVariables -filePath $envFilePath

# # Get OrgID and TenantID from environment variables and convert to integers
# $orgID = [int]$envDict["ORG_ID"]
# $tenantID = [int]$envDict["TENANT_ID"]

# # Get machine info
# $machineInfo = Get-MachineInfo

# # Read selected groups from the file
# $groups = Get-Content -Path "C:\selected_user_groups.conf"

# # Log the groups for testing purposes
# Write-Host "Selected Groups:"
# foreach ($group in $groups) {
#     Write-Host $group
# }

# # Define the API URL
# $apiUrl = "https://prod.tenants.authnull.com/addEndpointGroups" # Need to Update this to get from the app.env file-23/01/2025

# # Make the API call to store the machine info and selected groups
# Store-MachineInfo -apiUrl $apiUrl -machineInfo $machineInfo -groups $groups -orgID $orgID -tenantID $tenantID 
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
            if ($fileContent -match '<runtime>.*?<loadFromRemoteSources enabled="true".*?</runtime>') {
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
            }
            else {
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
        }
        catch {
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

    $lgpoPath = $OutputPath + "\windows-endpoint-main\gpo\LGPO.exe"
    $backupFolder = $OutputPath + "\windows-endpoint-main\gpo\registry.pol"
    #$infFilePath = $OutputPath + "\windows-endpoint-main\gpo\security.inf"
    
    # try {
    #     Start-Process -FilePath $lgpoPath -ArgumentList "/s $infFilePath"
    #     Write-Host "Security settings installed successfully." -ForegroundColor Green
    # } 
    # catch {
    #     Write-Host "Security setting installation failed : $_" -ForegroundColor Red
    # }

    # Define paths
    $BackupDirectory = "C:\Backup\SecurityPolicies"
    $BackupFile = "$BackupDirectory\security.inf"
    $ModifiedFile = "$BackupDirectory\modified_security.inf"
    $LogFile = "$BackupDirectory\secedit.log"

    # Ensure the backup directory exists
    if (-not (Test-Path $BackupDirectory)) {
        New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    }

    try {
        # Step 1: Export the current security policy
        Write-Host "Exporting current security policy..." -ForegroundColor Yellow
        secedit /export /cfg $BackupFile /log $LogFile
        Write-Host "Exported security policy to $BackupFile" -ForegroundColor Green

        # Step 2: Modify the PasswordComplexity setting
        Write-Host "Modifying PasswordComplexity setting to 0..." -ForegroundColor Yellow
        $content = Get-Content $BackupFile
        $content = $content -replace "PasswordComplexity\s*=\s*\d+", "PasswordComplexity = 0"
        $content | Set-Content $ModifiedFile
        Write-Host "PasswordComplexity updated in $ModifiedFile" -ForegroundColor Green

        # Step 3: Reimport the modified security policy
        Write-Host "Importing modified security policy..." -ForegroundColor Yellow
        $seceditPath = Join-Path $env:SystemRoot "security\local.sdb"
        secedit /configure /db $seceditPath /cfg $ModifiedFile /log $LogFile
        Write-Host "Modified security policy applied successfully." -ForegroundColor Green

        # Step 4: Force Group Policy update
        Write-Host "Forcing Group Policy update..." -ForegroundColor Yellow
        gpupdate /force
        Write-Host "Group Policy updated successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "An error occurred: $_" -ForegroundColor Red
    }

    # Check the log file for any issues
    Write-Host "Check the log file at $LogFile for detailed information." -ForegroundColor Yellow


    try {
        Start-Process -FilePath $lgpoPath -ArgumentList "/m $backupFolder" -Wait
        Write-Host "Group policy updated successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Group policy updation failed: $_" -ForegroundColor Red
    }           
    
    #---------------------------------------------------------------------
    Write-Host "Configuring pgina for user authentication" -ForegroundColor Green
    # Define the path to your registry file
    $registryFilePath = $OutputPath + "\windows-endpoint-main\gpo\pgina.reg"

    # Check if the file exists
    try {
        if (Test-Path $registryFilePath) {
            # Import the registry file using regedit
            Start-Process -FilePath "regedit.exe" -ArgumentList "/s `"$registryFilePath`"" -Wait

            # Optionally, check if the import was successful
            Write-Host "Registry file imported successfully." -ForegroundColor Green
        }
        else {
            Write-Output "Registry file not found: $registryFilePath" -ForegroundColor Red
        }
    }

    catch {
        Write-Host "Failed to update registry : $_" -ForegroundColor Red
    }
    #-----------------------------------------------------------------------
    #Setting LocalAdminFallback Registry 
    set-ItemProperty -Path "HKLM:\Software\pGina3\plugins\12fa152d-a2e3-4c8d-9535-5dcd49dfcb6d" -Name "LocalAdminFallBack" -Value "True" -Type String -Force -Verbose
    Write-Host "Local Admin Fallback registry added successfully.." -ForegroundColor Green
    
    #--------------------------------------------------------------------------------
    #Write-Host "LDAP Plugin Settings" -ForegroundColor Green
    $registryFilePath = $OutputPath + "\windows-endpoint-main\gpo\ldap.reg"
    try {
        # Check if the file exists
        if (Test-Path $registryFilePath) {
            # Import the registry file using regedit
            Start-Process -FilePath "regedit.exe" -ArgumentList "/s `"$registryFilePath`"" -Wait
            #Write-Host "Ldap Registry file imported successfully." -ForegroundColor Green
        }
        else {
            Write-Output " ldap Registry file not found: $registryFilePath" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Failed to update LDAP registry : $_" -ForegroundColor Red
    }

    #------------------------------------------------------------------------------  
    #update the LDAP configuration settings
    #Ldap Registry Path
    $registryKeyPath = "HKLM:\SOFTWARE\pGina3\Plugins\0f52390b-c781-43ae-bd62-553c77fa4cf7"
    # Env file Path
    $envFilePath = "C:\authnull-agent\app.env"

    # Read the file content
    $envContent = Get-Content -Path $envFilePath

    # Dictionary to store the key-value pairs
    $envDict = @{}

    foreach ($line in $envContent) {
        if ($line -match "=") {
            # Split only on the first '=' to correctly parse the key-value pair
            $key, $value = $line -split "=", 2
            $key = $key.Trim()
            $value = $value.Trim()
            $envDict[$key] = $value
        }
    }

    #Keys and their corresponding registry names
    $expectedKeys = @{
        "LDAP_HOST"        = "LdapHost"
        "LDAP_PORT"        = "LdapPort"
        "SEARCH_DN"        = "SearchDn"
        "GROUP_DN_PATTERN" = "GroupDnPattern"
        "USER_DN_PATTERN"  = "DnPattern"
    }

    # Loop through the expected keys and update the registry
    foreach ($key in $expectedKeys.Keys) {
        $value = $null  # Clear previous value
        if ($envDict.ContainsKey($key)) {
       
            $value = $envDict[$key]
        }
        # else {
        
        #     $value = Read-Host "Enter value for $key"
        # }
    
        if ($key -eq "LDAP_PORT") {
            # $value = "{0:x}" -f [int]$value
            Set-ItemProperty -Path $registryKeyPath -Name $expectedKeys[$key] -Value $value -Force -Type DWORD 
        }

        Set-ItemProperty -Path $registryKeyPath -Name $expectedKeys[$key] -Value $value -Force 
    }

    # Paths
    $imagePath = "C:\authnull-agent"

    if (-not [string]::IsNullOrWhiteSpace($imageUrl)) {
    # Read IMAGE_URL from app.env
    $imageUrlLine = Get-Content -Path $envFilePath | Where-Object { $_ -match "^IMAGE_URL=" }
    $imageUrl = $imageUrlLine -replace "^IMAGE_URL=", ""
    $imageUrl = $imageUrl.Trim()

    # Continue only if imageUrl is valid
    $tempImagePath = Join-Path $imagePath "temp_tile_image.png"
    $bmpImagePath = Join-Path $imagePath "tile_image.bmp"

    # Download image
    Invoke-WebRequest -Uri $imageUrl -OutFile $tempImagePath

    # Load and convert image with white background
    Add-Type -AssemblyName System.Drawing

    $originalImage = [System.Drawing.Image]::FromFile($tempImagePath)

    # Create new blank bitmap with white background
    $bitmap = New-Object System.Drawing.Bitmap $originalImage.Width, $originalImage.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([System.Drawing.Color]::White)
    $graphics.DrawImage($originalImage, 0, 0, $originalImage.Width, $originalImage.Height)

    # Save as BMP
    $bitmap.Save($bmpImagePath, [System.Drawing.Imaging.ImageFormat]::Bmp)

    # Cleanup
    $graphics.Dispose()
    $originalImage.Dispose()
    $bitmap.Dispose()
    Remove-Item $tempImagePath -Force

    # Set registry key to BMP
    Set-ItemProperty -Path "HKLM:\Software\pGina3" -Name "TileImage" -Value $bmpImagePath -Type String -Force -Verbose
    } else{
        Write-Host "No IMAGE_URL found in app.env. Skipping image processing." -ForegroundColor Green
        Set-ItemProperty -Path "HKLM:\Software\pGina3" -Name "TileImage" -Value "" -Type String -Force -Verbose
        Write-Host "Default PGINA Logo will take over Logon Screen" -ForegroundColor Green
    }

    #------------------------------------------------------------------------------------------------------------------------------------
    #Restart Computer

    try {
        Write-Host "Waiting for 10 seconds before restarting..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    catch {
        Write-Host "Restarting computer failed: $_" -ForegroundColor Red
    }
}
