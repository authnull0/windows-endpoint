# AuthNull RADIUS bridge

Adds AuthNull MFA to an existing FreeRADIUS server. FreeRADIUS checks the password
first; the bridge then asks AuthNull whether the login is allowed, needs a push
approval, or is blocked.

## Install

1. In the AuthNull console go to **RADIUS Servers > Add server > FreeRADIUS** and download `app.env`.
2. Copy `app.env` to your FreeRADIUS server and run, in the same folder:

   ```
   curl -fsSL https://github.com/authnull0/windows-endpoint/raw/radius/agent/radius-bridge/install.sh | sudo bash -s -- ./app.env
   ```

3. Restart FreeRADIUS: `sudo systemctl restart freeradius`
4. Set the RADIUS timeout on each VPN or switch to at least 60 seconds with 1 retry.

`install.sh` downloads the bridge for your CPU (amd64 or arm64), checks it against
`SHA256SUMS`, and runs `install-bridge.sh`. Run `sudo bash install-bridge.sh --check`
for a preflight that changes nothing.

Logs: `/var/log/authnull/radius-bridge.log`

Health: the installer adds `authnull-radius-heartbeat.timer`, which reports this server's
status to the console every 60 seconds (RADIUS Servers). Run
`sudo /usr/local/bin/authnull-radius-mfa --heartbeat` to see each check.

## Files

| File | What it is |
|---|---|
| `install.sh` | One-command installer |
| `install-bridge.sh` | Installs the bridge into FreeRADIUS |
| `authnull-radius-mfa-linux-*` | The bridge |
| `radius-bridge.env.example` | Config template, used when no `app.env` is given |
| `SHA256SUMS` | Checksums `install.sh` verifies |
| `BUILD-INFO` | Source commit the bridge was built from |

Published from `authnull-service/onprem/radius-bridge` by `publish.sh`. Do not edit
these files here: the next publish overwrites them.
