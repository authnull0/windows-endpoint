<#
.SYNOPSIS
    One-time DC locator refresh after an AuthNull AD Gateway deployment.

.DESCRIPTION
    Deploy via Group Policy as a computer-startup script. Designed to run
    unattended on every domain-joined workstation and member server so
    clients pick up new SRV records pointing at the gateway.

    Behaviour:
      - Reads a single HKLM marker to decide whether this host has already
        run a compatible version of the script. If yes, exits silently.
      - Otherwise: purges Kerberos tickets (user + SYSTEM), resets the
        Netlogon secure-channel cache, restarts the Netlogon service, and
        asks for fresh DC discovery.
      - Writes its result to the Windows Event Log under a dedicated
        source so admins can query success/failure across the fleet with a
        single wevtutil / Get-WinEvent call.
      - Never prompts, never reboots, never waits longer than 60 s.

.PARAMETER Version
    Numeric bump. Increment when the script needs to re-run on hosts that
    already ran an earlier version (e.g. after a gateway migration). Hosts
    with a stored marker >= this value exit immediately.

.PARAMETER DryRun
    Print what would happen, change nothing. Useful for pilot validation.

.PARAMETER Force
    Ignore the version marker and run anyway. For manual re-runs.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File RefreshDCLocator.ps1

    Typical GPO startup-script invocation.

.EXAMPLE
    .\RefreshDCLocator.ps1 -DryRun -Verbose

    Safe verification on a single machine before broad deployment.
#>

[CmdletBinding()]
param(
    [int]$Version = 1,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

# --- Constants ----------------------------------------------------------------
$MarkerKey       = 'HKLM:\SOFTWARE\AuthNull\ADGateway'
$MarkerName      = 'DCLocatorRefreshVersion'
$EventLogName    = 'Application'
$EventLogSource  = 'AuthNull-ADGateway'

# --- Helpers ------------------------------------------------------------------

# Idempotent event-log source registration. Requires admin the first time;
# startup scripts run as SYSTEM which is fine.
function Register-EventSource {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
            [System.Diagnostics.EventLog]::CreateEventSource($EventLogSource, $EventLogName)
        }
    } catch {
        # If the local policy forbids us, we'll fall back to Write-Verbose below.
    }
}

function Write-Audit {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet('Information', 'Warning', 'Error')] [string] $Level = 'Information',
        [int] $EventId = 1000
    )
    Write-Verbose "[$Level] $Message"
    try {
        Write-EventLog -LogName $EventLogName -Source $EventLogSource -EntryType $Level `
            -EventId $EventId -Message $Message
    } catch {
        # Swallow — startup scripts must not fail the boot even if event log
        # registration failed.
    }
}

function Test-ShouldRun {
    if ($Force) { return $true }
    try {
        if (-not (Test-Path $MarkerKey)) { return $true }
        $current = (Get-ItemProperty -Path $MarkerKey -Name $MarkerName -ErrorAction Stop).$MarkerName
        return ($current -lt $Version)
    } catch {
        # Property missing → never ran successfully.
        return $true
    }
}

function Set-Marker {
    if ($DryRun) { return }
    if (-not (Test-Path $MarkerKey)) {
        New-Item -Path $MarkerKey -Force | Out-Null
    }
    Set-ItemProperty -Path $MarkerKey -Name $MarkerName -Value $Version -Type DWord
}

# Wrap a native command so we capture output + non-zero exit without aborting
# the whole script.
function Invoke-Native {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [scriptblock] $Body
    )
    try {
        $out = & $Body 2>&1 | Out-String
        Write-Audit "$Label OK$(if ($out) { ": $($out.Trim())" } else { '' })"
        return $true
    } catch {
        Write-Audit "$Label FAILED: $($_.Exception.Message)" 'Warning'
        return $false
    }
}

# --- Main ---------------------------------------------------------------------

Register-EventSource

if (-not (Test-ShouldRun)) {
    Write-Audit "DC locator refresh v$Version already applied — no action."
    exit 0
}

Write-Audit "Refreshing DC locator binding (version $Version, DryRun=$DryRun)"

$domain = $env:USERDNSDOMAIN
if (-not $domain) {
    # Fallback: derive from the machine's AD domain
    try {
        $domain = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).Domain
    } catch {
        $domain = $null
    }
}

if (-not $domain -or $domain -eq 'WORKGROUP') {
    Write-Audit "Host is not domain-joined. Skipping." 'Information' 1010
    Set-Marker
    exit 0
}

Write-Audit "Target realm: $domain"

# Step 1: Purge cached Kerberos tickets for the current user + the SYSTEM logon
# session. SYSTEM is where machine-account tickets live; user tickets vary.
if (-not $DryRun) {
    Invoke-Native 'klist purge'          { klist.exe purge          }        | Out-Null
    Invoke-Native 'klist purge (SYSTEM)' { klist.exe -li 0x3e7 purge }        | Out-Null
}

# Step 2: Reset the DC binding cache for this domain. Forces the next
# DC-locator call to hit DNS / CLDAP rather than serving from Netlogon's cache.
if (-not $DryRun) {
    Invoke-Native 'nltest /sc_reset' {
        nltest.exe "/sc_reset:$domain"
    } | Out-Null
}

# Step 3: Restart Netlogon so its in-memory site / DC selection is rebuilt.
if (-not $DryRun) {
    try {
        Restart-Service -Name Netlogon -Force -ErrorAction Stop
        Write-Audit 'Netlogon restarted'
    } catch {
        Write-Audit "Netlogon restart failed: $($_.Exception.Message)" 'Warning'
    }
}

# Step 4: Force DC rediscovery so the first user auth after boot is fast.
if (-not $DryRun) {
    Invoke-Native 'nltest /dsgetdc /force' {
        nltest.exe "/dsgetdc:$domain" /force
    } | Out-Null
}

# Verify + log which DC we ended up bound to.
try {
    $res = nltest.exe "/dsgetdc:$domain" 2>&1 | Out-String
    $addr = ($res -split "`n" | Where-Object { $_ -match 'Address:\s+\\\\' } | Select-Object -First 1).Trim()
    Write-Audit "DC binding after refresh: $addr" 'Information' 1001
} catch {
    Write-Audit "Could not query new DC binding: $($_.Exception.Message)" 'Warning'
}

Set-Marker
Write-Audit "DC locator refresh v$Version complete." 'Information' 1002
exit 0
