#Agentless configuration script to download SubAuth.dll

$destinationPath = "C:\authnull-ad-agent\agent.conf"

$envFileContent = Get-Content -Path $destinationPath

# Check if the env file exists
if (-not (Test-Path -Path $destinationPath)) {
    Write-Host "The env file does not exist at path: $destinationPath" -ForegroundColor Red
    exit
}

# Read the content of the env file
try {
    $envFileContent = Get-Content -Path $destinationPath
    Write-Host "Successfully read the env file." -ForegroundColor Green
}
catch {
    Write-Host "Failed to read the env file: $_" -ForegroundColor Red
    exit
}

# Process each line in the env file
$envFileContent | ForEach-Object {
    if ($_ -match "ADMFA") {
        $value = $_ -replace "ADMFA=", ""
        if ($value -eq "1") {
            # Variables
            $GitHubURL = "https://raw.githubusercontent.com/authnull0/windows-endpoint/main/SubAuth.dll"  # Corrected URL of the DLL to download
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
            }
            catch {
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
                    }
                    else {
                        Write-Host "$DllName already exists in Kerberos authentication packages."
                    }
                }
                else {
                    # Create the value if it doesn't exist
                    Write-Host "Creating new Kerberos authentication packages registry value..."
                    Set-ItemProperty -Path $RegistryPathKerberos -Name $SubAuthValueName -Value $DllName
                    Write-Host "New Kerberos packages: $DllName" -ForegroundColor Yellow
                }

                Write-Host "Successfully modified the Kerberos registry."
            }
            catch {
                Write-Host "Error modifying the Kerberos registry: $_" -ForegroundColor Red
                exit
            }

            # Final step: Notify the user to restart the machine
            #Write-Host "You may need to restart the system for changes to take effect."
        }
        else {
            Write-Host "ADMFA is set to false. No further action is required."
        }
    }
}

#Restart Computer
try {
    Write-Host "Waiting for 10 seconds before restarting..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}
catch {
    Write-Host "Restarting computer failed: $_" -ForegroundColor Red
}

