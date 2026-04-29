# ad-gateway folder in authnull0/windows-endpoint

The `install.sh` script fetches every file below from
`https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-gateway/`.

## Required layout

```
ad-gateway/
├── install.sh                          ← this installer (entry point)
│
├── ad-gateway-proxy-linux-amd64        ← compiled binary (amd64)
├── ad-gateway-proxy-linux-arm64        ← compiled binary (arm64, optional)
├── ad-gateway-control-linux-amd64
├── ad-gateway-control-linux-arm64      ← optional
│
├── SHA256SUMS                          ← sha256sum output for all binaries
│                                         format: <hash>  <filename>
│
├── proxy.yml.example                   ← from ad-gateway-proxy/packaging/
├── control.yml.example                 ← from ad-gateway-control/packaging/
│
├── systemd/
│   ├── ad-gateway-proxy.service        ← from ad-gateway-proxy/packaging/systemd/
│   └── ad-gateway-control.service      ← from ad-gateway-control/packaging/systemd/
│
├── ntlm-gate.sh                        ← from packaging/deployment/
├── apply-dns-cutover.ps1               ← from packaging/deployment/
└── RefreshDCLocator.ps1                ← from packaging/deployment/
```

## Building the binaries

From the repo root, on a Linux machine (or via CI):

```bash
# amd64
GOOS=linux GOARCH=amd64 go build -o ad-gateway-proxy-linux-amd64    ./ad-gateway-proxy/cmd/proxy
GOOS=linux GOARCH=amd64 go build -o ad-gateway-control-linux-amd64  ./ad-gateway-control/cmd/server

# arm64 (optional)
GOOS=linux GOARCH=arm64 go build -o ad-gateway-proxy-linux-arm64    ./ad-gateway-proxy/cmd/proxy
GOOS=linux GOARCH=arm64 go build -o ad-gateway-control-linux-arm64  ./ad-gateway-control/cmd/server

# checksums
sha256sum ad-gateway-*-linux-* > SHA256SUMS
```

Then copy everything into `ad-gateway/` in the windows-endpoint repo and commit.

## Quick publish checklist

- [ ] Binaries built with `CGO_ENABLED=0` (static, no libc dependency)
- [ ] SHA256SUMS generated and committed alongside binaries
- [ ] Both `.service` files copied from `packaging/systemd/`
- [ ] `proxy.yml.example` and `control.yml.example` reflect latest config schema
- [ ] `ntlm-gate.sh`, `apply-dns-cutover.ps1`, `RefreshDCLocator.ps1` copied from `packaging/deployment/`
- [ ] Test the installer on a fresh Ubuntu 22.04 or Rocky 9 VM before sharing with customer
