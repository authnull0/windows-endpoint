<#
.SYNOPSIS
    Applies Phases 2 + 3 of the AuthNull AD Gateway rollout in one run.

.DESCRIPTION
    Creates the gateway A record, three SRV records, and demotes the
    DC-registered SRV priority so clients prefer the gateway. Idempotent —
    safe to re-run.

    This is a convenience wrapper around the manual commands in README.md.
    For first-time pilots, prefer running the steps manually so you see
    each one; for repeat deployments or scripting, use this.

.PARAMETER GatewayIp
    The gateway VA's IP address (VIP, for HA pairs).

.PARAMETER GatewayFqdn
    FQDN to register for the gateway. Defaults to ad-gateway.<realm>.

.PARAMETER TtlSeconds
    TTL to set on the gateway records. Short TTL (60s) during rollout so
    rollback is fast. Can be increased after stable operation.

.PARAMETER DcPriority
    New priority for DC-registered SRV records. Must be > the gateway's
    (which is 0). Default 100.

.PARAMETER DryRun
    Print what would happen, change nothing.

.EXAMPLE
    .\apply-dns-cutover.ps1 -GatewayIp 10.4.0.8

    Typical customer rollout.

.EXAMPLE
    .\apply-dns-cutover.ps1 -GatewayIp 10.4.0.8 -DryRun

    Preview the changes without applying.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $GatewayIp,
    [string] $GatewayFqdn,
    [int]    $TtlSeconds = 60,
    [int]    $DcPriority = 100,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'

function Step ($msg) {
    Write-Host "==> $msg" -ForegroundColor Cyan
}

# --- Discover realm / zone ---------------------------------------------------
Step 'Discovering domain'
Import-Module ActiveDirectory
Import-Module DnsServer

$realm = (Get-ADDomain).DNSRoot.ToUpper()
$zone  = $realm.ToLower()
if (-not $GatewayFqdn) { $GatewayFqdn = "ad-gateway.$zone" }

"  realm         : $realm"
"  zone          : $zone"
"  gateway FQDN  : $GatewayFqdn"
"  gateway IP    : $GatewayIp"
"  TTL           : ${TtlSeconds}s"
"  DC priority   : $DcPriority (fallback)"
''

$ttl = New-TimeSpan -Seconds $TtlSeconds

# --- A record ----------------------------------------------------------------
Step 'Ensuring gateway A record'

$gwLabel = $GatewayFqdn.Split('.')[0]
$existingA = Get-DnsServerResourceRecord -ZoneName $zone -Name $gwLabel -RRType A -ErrorAction SilentlyContinue

if ($existingA) {
    $current = $existingA.RecordData.IPv4Address.IPAddressToString
    if ($current -eq $GatewayIp) {
        "  up-to-date: $gwLabel -> $current"
    } else {
        "  replacing $gwLabel $current -> $GatewayIp"
        if (-not $DryRun) {
            Remove-DnsServerResourceRecord -ZoneName $zone -Name $gwLabel -RRType A -Force
            Add-DnsServerResourceRecord -ZoneName $zone -A -Name $gwLabel `
                -IPv4Address $GatewayIp -TimeToLive $ttl
        }
    }
} else {
    "  creating $gwLabel -> $GatewayIp"
    if (-not $DryRun) {
        Add-DnsServerResourceRecord -ZoneName $zone -A -Name $gwLabel `
            -IPv4Address $GatewayIp -TimeToLive $ttl
    }
}

# --- SRV records -------------------------------------------------------------
$srvs = @(
    @{ Name = '_kerberos._tcp'; Port = 88  },
    @{ Name = '_kerberos._udp'; Port = 88  },
    @{ Name = '_ldap._tcp';     Port = 389 }
)

foreach ($s in $srvs) {
    Step "Ensuring SRV $($s.Name) -> ${GatewayFqdn}:$($s.Port) priority 0"

    $existing = Get-DnsServerResourceRecord -ZoneName $zone -Name $s.Name -RRType Srv -ErrorAction SilentlyContinue |
        Where-Object { $_.RecordData.DomainName -like "$GatewayFqdn*" }

    if ($existing) {
        "  already present"
        continue
    }

    if (-not $DryRun) {
        Add-DnsServerResourceRecord -ZoneName $zone -Srv `
            -Name $s.Name -DomainName "$GatewayFqdn." `
            -Priority 0 -Weight 100 -Port $s.Port -TimeToLive $ttl
    }
    "  created"
}

# --- Site-specific SRV records ----------------------------------------------
# Critical: the DC locator prefers _<site>._sites records over generic ones.
# Without these, clients in any AD site keep finding the real DC even after
# the generic records above are in place.
Step 'Ensuring site-specific SRV records'

$msdcsZone = "_msdcs.$zone"
$siteSrvs = @(
    @{ NameTpl = '_kerberos._tcp.{0}._sites';    Port = 88;  Zone = $zone     },
    @{ NameTpl = '_kerberos._udp.{0}._sites';    Port = 88;  Zone = $zone     },
    @{ NameTpl = '_ldap._tcp.{0}._sites';        Port = 389; Zone = $zone     },
    @{ NameTpl = '_kerberos._tcp.{0}._sites.dc'; Port = 88;  Zone = $msdcsZone },
    @{ NameTpl = '_ldap._tcp.{0}._sites.dc';     Port = 389; Zone = $msdcsZone }
)

$sites = (Get-ADReplicationSite -Filter *).Name
"  sites discovered: $($sites -join ', ')"

foreach ($site in $sites) {
    foreach ($t in $siteSrvs) {
        $name = [string]::Format($t.NameTpl, $site)

        $existing = Get-DnsServerResourceRecord -ZoneName $t.Zone -Name $name -RRType Srv -ErrorAction SilentlyContinue |
            Where-Object { $_.RecordData.DomainName -like "$GatewayFqdn*" }

        if ($existing) {
            "  [$site] $name : already present"
            continue
        }

        if (-not $DryRun) {
            Add-DnsServerResourceRecord -ZoneName $t.Zone -Srv `
                -Name $name -DomainName "$GatewayFqdn." `
                -Priority 0 -Weight 100 -Port $t.Port -TimeToLive $ttl
        }
        "  [$site] $name : created"
    }
}

# --- Demote DC priority ------------------------------------------------------
Step "Demoting DC-registered SRV priority to $DcPriority"

$p = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
$currentLdap = (Get-ItemProperty -Path $p -Name 'LdapSrvPriority' -ErrorAction SilentlyContinue).LdapSrvPriority
$currentKdc  = (Get-ItemProperty -Path $p -Name 'KdcSrvPriority'  -ErrorAction SilentlyContinue).KdcSrvPriority

if ($currentLdap -eq $DcPriority -and $currentKdc -eq $DcPriority) {
    '  already demoted'
} else {
    "  setting LdapSrvPriority + KdcSrvPriority to $DcPriority"
    if (-not $DryRun) {
        New-ItemProperty -Path $p -Name 'LdapSrvPriority' -Value $DcPriority -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $p -Name 'KdcSrvPriority'  -Value $DcPriority -PropertyType DWord -Force | Out-Null
    }

    Step 'Restarting Netlogon to force SRV re-registration'
    if (-not $DryRun) {
        Restart-Service -Name Netlogon -Force
    }
}

# --- Verify ------------------------------------------------------------------
Step 'Verification'

try {
    $results = Resolve-DnsName -Type SRV "_kerberos._tcp.$zone" -DnsOnly -ErrorAction Stop
    $results | Where-Object Type -eq 'SRV' | Format-Table Name, Priority, Weight, Port, NameTarget -AutoSize
} catch {
    "  DNS lookup failed (DNS propagation may take a few seconds): $($_.Exception.Message)"
}

Write-Host ''
if ($DryRun) {
    Write-Host 'DRY RUN — no changes were applied.' -ForegroundColor Yellow
} else {
    Write-Host 'Cutover complete. Proceed to Phase 4 (GPO deployment) in README.md.' -ForegroundColor Green
}
