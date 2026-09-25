# AuthNull SSH proxy — release files

What the console's onboarding wizard downloads. The proxy runs as a systemd binary on a jump
host, **not** in the compose stack: it sits on the operator-to-target path, which the
containers do not.

## Install

```bash
wget https://raw.githubusercontent.com/authnull0/windows-endpoint/main/sshproxy/install.sh
sudo bash install.sh
```

`install.sh` fetches the set below into a temp directory, verifies it against `SHA256SUMS`,
and hands off to `install-sshproxy.sh`. Read either before running — both run as root.

## What is here

| File | |
|---|---|
| `install.sh` | bootstrap: downloads, verifies, delegates |
| `install-sshproxy.sh` | the real installer — service account, keys, unit, config |
| `authnull-sshproxy-linux-amd64` | the binary |
| `authnull-sshproxy.service` | the systemd unit |
| `sshproxy.env.example` | the config template, with every variable explained inline |
| `SHA256SUMS` | checked by `install.sh` before anything executes |

amd64 only for now. On arm64, build from source with `./deploy/build.sh` in the `sshproxy`
repo; `install.sh` says so rather than failing obscurely.

## It does not start anything

The installer creates the service account, generates the host key, backend key, CA key and an
HMAC key, installs the unit — and stops. The proxy **refuses to start** until it is told
things only the console knows:

```
SSHPROXY_ORG_ID must be set to a positive organisation id
```

Those values, and the env file to put them in (`/etc/authnull/sshproxy/sshproxy.env`), come
from Step 2 of the onboarding wizard. That is deliberate: a proxy that started with defaults
would be a listening SSH service with no idea who is allowed to use it.

## Keys are generated on the box and stay there

The host key, backend key and CA key are created by the installer and never leave. Only their
**public halves** are reported to the console, on the heartbeat, so the wizard can show them
with a copy button instead of asking somebody to SSH back in and `cat` a file.

Re-running the installer never regenerates them. The host key is the proxy's identity — a new
one trips every client's `known_hosts` with the warning that means an active
man-in-the-middle — and a new CA key invalidates trust on every target already carrying the
old public half.

## Updating

Re-run `install.sh`. It replaces the binary and the unit, and leaves the config and all three
keys alone.

Built from the `sshproxy` repository. To produce these files yourself: `./deploy/build.sh`.
