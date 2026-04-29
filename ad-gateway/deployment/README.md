# AuthNull AD Gateway — Customer Deployment Runbook

## ⚠ Phase 3A prerequisite: NTLM gate via ipset

Before following the DNS/GPO steps below, the gateway VA needs the NTLM
bypass gate installed. This is the ipset-conditional DNAT that prevents
`runas` / `net use` from completing via NTLM fallback when the user hasn't
MFA'd. Without it, the Kerberos MFA flow can be silently sidestepped.

On the gateway VA, as root:

```bash
# 1. install ipset + persistence + the new systemd unit
apt-get install -y ipset iptables-persistent
cp ad-gateway-proxy/packaging/systemd/ad-gateway-proxy.service /etc/systemd/system/
systemctl daemon-reload

# 2. install the kernel set + iptables rules
sudo DC_IP=10.4.0.17 GW_IP=10.4.0.8 bash ntlm-gate.sh

# 3. (re)start the proxy — now picks up the CAP_NET_ADMIN ambient cap
systemctl restart ad-gateway-proxy
```

This:
- creates the `authnull_active` kernel ipset with per-entry TTL matching
  `mfa_session_ttl` in proxy.yml (default 300s)
- replaces the unconditional DC DNAT with a rule that matches only IPs in
  the set
- persists both iptables and ipset state across reboots
- leaves ports 88/389 (and 22/18443/19813) untouched — they're terminated
  by the gateway proxy itself and always reachable

The shipped systemd unit grants both `CAP_NET_BIND_SERVICE` (for ports
88/389/636) and `CAP_NET_ADMIN` (for ipset management) via
`AmbientCapabilities=` so the proxy doesn't need root and `setcap` on the
binary is **not** required — `NoNewPrivileges=true` would defeat file caps
anyway.

After the restart, the proxy's log should include:

```
"msg":"ntlm gate active","ipset":"authnull_active","ttl":"5m0s"
```

Absence of that line means the proxy couldn't reach `ipset`. Most common
causes:
- `ipset` package not installed (`apt-get install ipset`)
- The deployed unit file is the older one without `CAP_NET_ADMIN` —
  re-copy from `packaging/systemd/ad-gateway-proxy.service` and
  `daemon-reload`.

Verify with a non-MFA'd client from inside the VNet:
```bash
nc -w2 <gateway-ip> 445      # should return immediately with RST (closed)
ipset list authnull_active   # shows IPs currently permitted through
```

---



This is the production rollout procedure for a customer-facing deployment of
the AD Gateway. It assumes you already have:

- Two gateway VAs (or one for pilot) installed and healthy
- A control-plane instance reachable from the gateways
- The MFA bridge (authsec) endpoint configured
- Admin rights on at least one Domain Controller

If any of those are not true, stop here and finish the prerequisite install
first — this document deals with the **DNS cutover + client propagation**, not
the gateway installation itself.

---

## Overview

The cutover is a one-time DNS change on the customer's AD DNS zone plus a
Group Policy push of a one-shot refresh script. There is **no manual work on
individual client machines**. Client convergence is automatic over minutes to
hours depending on how patient you want to be.

| Phase | Who | Where | Typical duration |
|---|---|---|---|
| 1. Pre-flight | Site admin | DC, gateway VA | 10 min |
| 2. DNS cutover | Site admin | DC | 5 min |
| 3. DC SRV priority demotion | Site admin | every DC | 5 min |
| 4. GPO script deployment | Site admin | DC → SYSVOL | 10 min |
| 5. Convergence monitoring | Site admin | gateway audit feed | 24 h observation window |
| 6. (Optional) fast-fanout | Site admin | admin workstation | 15 min for 1000 hosts |

Total admin hand-on time: ~30 min. Convergence completes within 24 h even
without the fast-fanout step.

---

## Phase 1 — Pre-flight

Run on the **DC**, PowerShell as Domain Admin.

### 1.1 Gather environment values

```powershell
$Realm        = (Get-ADDomain).DNSRoot.ToUpper()
$DcFqdn       = (Get-ADDomain).PDCEmulator
$DcIpAddress  = (Resolve-DnsName $DcFqdn -Type A).IPAddress
$GatewayFqdn  = 'ad-gateway.{0}' -f $Realm.ToLower()
$GatewayIp    = '<VIP of the gateway VA>'       # FILL IN

"Realm        : $Realm"
"DC FQDN      : $DcFqdn"
"DC IP        : $DcIpAddress"
"Gateway FQDN : $GatewayFqdn"
"Gateway IP   : $GatewayIp"
```

Verify these values against your gateway config (`/etc/authnull/proxy.yml`).
`upstream_kdc` should contain the DC IP; `realm` should match `$Realm`.

### 1.2 Reachability gate

On the gateway VA:
```bash
nc -zv 10.4.0.17 88
nc -zv 10.4.0.17 389
```

On the DC, test the gateway:
```powershell
Test-NetConnection $GatewayIp -Port 88
Test-NetConnection $GatewayIp -Port 389
```

All four must succeed. If they don't, **stop** — fix NSG / firewall rules
first. The SRV cutover below will break AD auth if clients can see the
gateway record but can't reach it.

### 1.3 Snapshot current SRV state (for rollback)

```powershell
Get-DnsServerResourceRecord -ZoneName $Realm.ToLower() -Name "_kerberos._tcp" -RRType Srv |
    Export-Clixml -Path "$HOME\Desktop\srv-snapshot-kerberos-tcp.xml"
Get-DnsServerResourceRecord -ZoneName $Realm.ToLower() -Name "_kerberos._udp" -RRType Srv |
    Export-Clixml -Path "$HOME\Desktop\srv-snapshot-kerberos-udp.xml"
Get-DnsServerResourceRecord -ZoneName $Realm.ToLower() -Name "_ldap._tcp" -RRType Srv |
    Export-Clixml -Path "$HOME\Desktop\srv-snapshot-ldap-tcp.xml"
```

Keep these files — Phase 7 uses them for rollback.

---

## Phase 2 — DNS cutover

Adds the gateway A record and three SRV records pointing at it. Low TTL so
clients re-resolve quickly if we need to bail.

```powershell
$zone = $Realm.ToLower()

# Gateway A record
Add-DnsServerResourceRecord -ZoneName $zone -A `
    -Name 'ad-gateway' -IPv4Address $GatewayIp -TimeToLive 00:01:00

# Gateway SRV records — priority 0 (beats any DC-registered record once we
# demote those in Phase 3)
Add-DnsServerResourceRecord -ZoneName $zone -Srv `
    -Name '_kerberos._tcp' -DomainName "$GatewayFqdn." `
    -Priority 0 -Weight 100 -Port 88 -TimeToLive 00:01:00

Add-DnsServerResourceRecord -ZoneName $zone -Srv `
    -Name '_kerberos._udp' -DomainName "$GatewayFqdn." `
    -Priority 0 -Weight 100 -Port 88 -TimeToLive 00:01:00

Add-DnsServerResourceRecord -ZoneName $zone -Srv `
    -Name '_ldap._tcp' -DomainName "$GatewayFqdn." `
    -Priority 0 -Weight 100 -Port 389 -TimeToLive 00:01:00
```

Verify — three SRV entries should appear for each name:

```powershell
Resolve-DnsName -Type SRV "_kerberos._tcp.$zone"
# Two answers:
#   priority 0   ad-gateway.<realm>   (new)
#   priority 0   <dc>.<realm>         (still registered by DC; demoted in Phase 3)
```

At this point both gateway and DC have priority 0 — clients will round-robin
between them. That's intentional: if Phase 3 goes wrong you can still reach
AD via the DC. The round-robin window lasts only as long as Phase 3 takes
(~5 min).

---

## Phase 3 — Demote DC-registered SRV priority

On **every** Domain Controller in the forest, run the same block. Netlogon
then re-registers its own SRV records at priority 100, falling behind the
gateway.

```powershell
$p = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
New-ItemProperty -Path $p -Name 'LdapSrvPriority' -Value 100 -PropertyType DWord -Force
New-ItemProperty -Path $p -Name 'KdcSrvPriority'  -Value 100 -PropertyType DWord -Force

# Force re-registration now so clients don't see the old priority-0 records
# any longer than necessary
Restart-Service Netlogon -Force
```

Verify (from anywhere):
```powershell
Resolve-DnsName -Type SRV "_kerberos._tcp.$zone"
# Expected:
#   priority 0   ad-gateway.<realm>       ← gateway, preferred
#   priority 100 master-windows.<realm>   ← DC, fallback
```

Rough order of magnitude: SRV TTL is 1 min, DC re-registers within ~30 s of
Netlogon restart. New clients looking up KDC within ~1 min of Phase 3 will
go through the gateway.

---

## Phase 4 — Deploy the GPO refresh script

Pushes a one-time cache flush to every domain-joined host. Each host runs
it once on next boot, writes a "done" marker in `HKLM`, and never runs it
again (unless you bump the version).

### 4.1 Stage the script on SYSVOL

```powershell
$src = '.\RefreshDCLocator.ps1'
$dst = "\\$Realm\SYSVOL\$($Realm.ToLower())\scripts\RefreshDCLocator.ps1"
Copy-Item -Path $src -Destination $dst -Force
```

### 4.2 Create / edit the GPO

1. Open **Group Policy Management Console** (`gpmc.msc`).
2. Right-click the domain → **Create a GPO in this domain, and Link it here**.
3. Name it `AuthNull - DC Locator Refresh`.
4. Right-click → **Edit**.
5. Navigate: **Computer Configuration → Policies → Windows Settings → Scripts (Startup/Shutdown) → Startup**.
6. **Add** → **Browse** → select `RefreshDCLocator.ps1` from SYSVOL.
7. **Script Parameters** (optional): `-Version 1`. Leave blank for now.
8. OK through, close GPME.

### 4.3 Force propagation

On the DC:
```powershell
# Trigger GPO refresh on all domain-joined machines. Not strictly required —
# machines pick up the policy on their next refresh cycle (90 min default) —
# but speeds up the pilot.
Invoke-Command -ComputerName (Get-ADComputer -Filter *).Name `
    -ScriptBlock { gpupdate.exe /force /target:computer } `
    -ThrottleLimit 50 -ErrorAction SilentlyContinue
```

Skip this if you don't have PSRemoting enabled domain-wide — the policy
will propagate organically anyway.

---

## Phase 5 — Convergence monitoring

Watch the gateway audit feed. Every machine that's migrated will start
showing up as the `client_ip` on Kerberos AS-REQs.

On the gateway VA:
```bash
curl -s http://127.0.0.1:18443/api/v1/auth-events | \
  jq -r '.events[] | .ts_unix_ms, .client_ip, .principal' | paste - - -
```

Or tail the proxy log directly:
```bash
tail -f /var/log/authnull/proxy.log | grep '"kdc request"'
```

Expect to see distinct `client_ip` values fill in over 15 min to 24 h as
machines naturally rediscover. A spike shortly after Phase 2 represents
active clients with warm Netlogon caches; a long tail represents
workstations that reboot on the weekly patch schedule.

### 5.1 Query migration status via Windows Event Log

The refresh script logs to the `AuthNull-ADGateway` source on each host
that runs it. To query fleet-wide:

```powershell
Invoke-Command -ComputerName (Get-ADComputer -Filter *).Name `
    -ScriptBlock {
        Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='AuthNull-ADGateway'} `
            -MaxEvents 1 -ErrorAction SilentlyContinue |
        Select-Object MachineName, TimeCreated, Id, Message
    } -ThrottleLimit 50 -ErrorAction SilentlyContinue |
    Sort-Object MachineName |
    Export-Csv -Path .\migration-status.csv -NoTypeInformation
```

Machines with no rows either haven't rebooted since the GPO arrived or
aren't applying the policy. Inspect individually.

---

## Phase 6 — (Optional) fast fan-out

If the pilot demands same-hour convergence, parallel-invoke the refresh
script against every machine without waiting for natural reboot.

```powershell
$targets = Get-ADComputer -Filter "OperatingSystem -like 'Windows*'" |
    Select-Object -ExpandProperty Name

Invoke-Command -ComputerName $targets -ThrottleLimit 50 -ScriptBlock {
    klist.exe purge
    klist.exe -li 0x3e7 purge
    nltest.exe /sc_reset:$env:USERDNSDOMAIN
    Restart-Service Netlogon -Force
} -ErrorAction Continue 2>&1 |
Tee-Object -FilePath .\fanout.log
```

Scan `fanout.log` for failures. Offline / unreachable machines migrate
naturally when they come back online.

---

## Phase 7 — Rollback

If anything goes wrong, remove the gateway DNS records and un-demote the DC.
Clients re-discover the DC directly within the 1 min SRV TTL + Netlogon
cache cycle (max ~15 min), without any client-side action.

```powershell
$zone = $Realm.ToLower()

# Remove gateway SRV records
'_kerberos._tcp', '_kerberos._udp', '_ldap._tcp' | ForEach-Object {
    Get-DnsServerResourceRecord -ZoneName $zone -Name $_ -RRType Srv |
        Where-Object { $_.RecordData.DomainName -eq "$GatewayFqdn." } |
        Remove-DnsServerResourceRecord -ZoneName $zone -Force
}

# Remove gateway A record
Remove-DnsServerResourceRecord -ZoneName $zone -Name 'ad-gateway' -RRType A -Force

# Un-demote DC priority
$p = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
Remove-ItemProperty -Path $p -Name 'LdapSrvPriority','KdcSrvPriority' -Force -ErrorAction SilentlyContinue
Restart-Service Netlogon -Force
```

The GPO startup script left markers in `HKLM:\SOFTWARE\AuthNull\ADGateway`
on every host. They're harmless but you can strip them during clean-up:

```powershell
Invoke-Command -ComputerName (Get-ADComputer -Filter *).Name `
    -ScriptBlock { Remove-Item -Path 'HKLM:\SOFTWARE\AuthNull' -Recurse -Force -ErrorAction SilentlyContinue } `
    -ThrottleLimit 50 -ErrorAction SilentlyContinue
```

And delete the GPO + script from SYSVOL.

---

## Operational notes

### Adding a new client after cutover
**None needed.** New domain-joined machines run DC-locator on first boot,
read SRVs, prefer the gateway. The startup script is a no-op on machines
that never had a cached DC binding.

### Gateway failure
If both gateway VAs are unreachable (VIP down, maintenance, outage), clients
still have the priority-100 DC SRV as fallback. They'll re-locate to the DC
on the next Netlogon refresh cycle (15 min default) and auth resumes
unprotected. This is the intentional degrade path.

To **force immediate fallback** during an outage:
```powershell
# Remove the gateway SRV records temporarily
'_kerberos._tcp', '_kerberos._udp', '_ldap._tcp' | ForEach-Object {
    Get-DnsServerResourceRecord -ZoneName $zone -Name $_ -RRType Srv |
        Where-Object { $_.RecordData.DomainName -eq "$GatewayFqdn." } |
        Remove-DnsServerResourceRecord -ZoneName $zone -Force
}
```

Restore them when the gateway is back up.

### Upgrading the gateway
Same binaries, restart. SRV records don't change. Clients don't notice.

### Moving to a new gateway VIP
1. Update `ad-gateway` A record to new VIP.
2. Wait 1 min for TTL to expire.
3. Clients pick up new IP on next KDC lookup.

No SRV changes, no client-side work.

### Decommissioning
Phase 7 rollback is also the decommission procedure. ~15 min for clients
to fully fall back to the DC.

---

## Checklist (print, tick as you go)

```
Phase 1 Pre-flight
  [ ] Values captured ($Realm, $DcFqdn, $GatewayIp)
  [ ] Reachability: proxy -> DC (88, 389) succeeds
  [ ] Reachability: DC -> gateway (88, 389) succeeds
  [ ] SRV state snapshotted

Phase 2 DNS cutover
  [ ] ad-gateway A record added
  [ ] _kerberos._tcp SRV added
  [ ] _kerberos._udp SRV added
  [ ] _ldap._tcp SRV added

Phase 3 DC SRV demotion (repeat per DC)
  [ ] LdapSrvPriority = 100
  [ ] KdcSrvPriority  = 100
  [ ] Netlogon restarted
  [ ] Resolve-DnsName confirms priority 0 gateway + priority 100 DC

Phase 4 GPO deployment
  [ ] RefreshDCLocator.ps1 copied to SYSVOL
  [ ] GPO "AuthNull - DC Locator Refresh" created + linked at domain root
  [ ] Script added to Computer Configuration > Startup Scripts

Phase 5 Convergence
  [ ] Gateway audit feed shows migrations from multiple client IPs
  [ ] Migration status CSV reviewed after 24h
  [ ] No unexpected auth failures in DC event log

Phase 6 (optional)
  [ ] Fast fanout script executed
  [ ] fanout.log reviewed for failures
```

---

## Escalation

- **Auth failures during rollout**: run Phase 7 rollback. Takes 15 min to
  restore baseline.
- **Gateway OOM / crash loop**: log in to the VA, `journalctl -xeu ad-gateway-proxy`,
  attach to support ticket.
- **MFA bridge timing out**: verify dev.api.authnull.com reachable from the
  VA; check the `mfa_timeout` in proxy.yml covers typical authsec response
  times (see `packaging/proxy.yml.example`).
- **Some clients never migrate**: check they have GPO applied
  (`gpresult /r`), then fall back to Phase 6 fast-fanout for those hosts
  specifically.
