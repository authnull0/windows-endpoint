#!/usr/bin/env bash
# AuthNull AD Gateway — one-shot installer
#
# Usage (on the gateway Linux VM, as root):
#   curl -fsSL https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-gateway/install.sh | sudo bash
#
# Or with a private-repo token:
#   TOKEN=ghp_... curl -fsSL \
#     -H "Authorization: token $TOKEN" \
#     https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-gateway/install.sh | sudo bash
#
# What it does:
#   1. Installs system packages (ipset, iptables-persistent, ldap-utils, smbclient)
#   2. Creates the 'authnull' service user and working directories
#   3. Downloads binaries + support files from the ad-gateway folder of this repo
#   4. Verifies SHA256 checksums
#   5. Installs systemd units (disabled; you start them after configuring)
#   6. Places /etc/authnull/{proxy,control}.yml.example for you to edit
#
# After install, see /etc/authnull/proxy.yml.example and control.yml.example,
# then: sudo systemctl edit ad-gateway-control   (add secrets)
#       sudo systemctl enable --now ad-gateway-proxy ad-gateway-control

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_RAW="https://raw.githubusercontent.com/authnull0/windows-endpoint/main/ad-gateway"
INSTALL_BIN="/usr/local/bin"
INSTALL_ETC="/etc/authnull"
INSTALL_LIB="/var/lib/authnull"
INSTALL_LOG="/var/log/authnull"
INSTALL_OPT="/opt/authnull"
SERVICE_USER="authnull"

# Optional: set TOKEN in env for private-repo access
GITHUB_AUTH_HEADER=""
if [[ -n "${TOKEN:-}" ]]; then
    GITHUB_AUTH_HEADER="Authorization: token ${TOKEN}"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\033[0;36m==>\033[0m $*"; }
ok()    { echo -e "\033[0;32m  ✓\033[0m $*"; }
warn()  { echo -e "\033[0;33m  !\033[0m $*"; }
fatal() { echo -e "\033[0;31mFATAL:\033[0m $*" >&2; exit 1; }

fetch() {
    local url="$1" dest="$2"
    local args=(-fsSL "$url" -o "$dest")
    [[ -n "$GITHUB_AUTH_HEADER" ]] && args+=(-H "$GITHUB_AUTH_HEADER")
    curl "${args[@]}" || fatal "Download failed: $url"
}

require_root() {
    [[ $EUID -eq 0 ]] || fatal "Run as root (or with sudo)"
}

detect_distro() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    else
        echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
require_root

info "AuthNull AD Gateway installer"
echo

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="linux-amd64" ;;
    aarch64) ARCH_SUFFIX="linux-arm64" ;;
    *) fatal "Unsupported architecture: $ARCH" ;;
esac
ok "Architecture: $ARCH_SUFFIX"

DISTRO=$(detect_distro)
ok "Package manager: $DISTRO"

# ---------------------------------------------------------------------------
# Phase 1 — System packages
# ---------------------------------------------------------------------------
info "Installing system packages"
case "$DISTRO" in
    apt)
        apt-get update -q
        DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
            ipset iptables-persistent ldap-utils smbclient curl jq
        ;;
    dnf|yum)
        "$DISTRO" install -y -q \
            ipset iptables-services openldap-clients samba-client curl jq
        ;;
    *)
        warn "Unknown distro — skipping package install. Ensure ipset, ldap-utils, smbclient are present."
        ;;
esac
ok "System packages ready"

# ---------------------------------------------------------------------------
# Phase 2 — Service user + directories
# ---------------------------------------------------------------------------
info "Creating service user and directories"

if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /sbin/nologin "$SERVICE_USER"
    ok "User '$SERVICE_USER' created"
else
    ok "User '$SERVICE_USER' already exists"
fi

for d in "$INSTALL_ETC" "$INSTALL_ETC/certs" "$INSTALL_LIB" "$INSTALL_LOG"; do
    mkdir -p "$d"
    chown "$SERVICE_USER:$SERVICE_USER" "$d"
done
mkdir -p "$INSTALL_OPT/iptables"
ok "Directories created"

# ---------------------------------------------------------------------------
# Phase 3 — Download binaries
# ---------------------------------------------------------------------------
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading binaries from authnull0/windows-endpoint"

fetch "$REPO_RAW/ad-gateway-proxy-${ARCH_SUFFIX}"    "$TMPDIR/ad-gateway-proxy"
fetch "$REPO_RAW/ad-gateway-control-${ARCH_SUFFIX}"  "$TMPDIR/ad-gateway-control"
fetch "$REPO_RAW/SHA256SUMS"                          "$TMPDIR/SHA256SUMS"
ok "Binaries downloaded"

# ---------------------------------------------------------------------------
# Phase 4 — Verify checksums
# ---------------------------------------------------------------------------
info "Verifying checksums"
pushd "$TMPDIR" >/dev/null

# SHA256SUMS contains entries for both arch variants; filter to ours
grep "$ARCH_SUFFIX" SHA256SUMS > SHA256SUMS.local 2>/dev/null || true
if [[ -s SHA256SUMS.local ]]; then
    # Rename entries to match the bare filenames we downloaded
    sed -i "s/-${ARCH_SUFFIX}//g" SHA256SUMS.local
    sha256sum -c SHA256SUMS.local || fatal "Checksum mismatch — aborting. Re-run to retry."
    ok "Checksums OK"
else
    warn "No arch-specific entries in SHA256SUMS — skipping verification (add them to the release)"
fi

popd >/dev/null

# ---------------------------------------------------------------------------
# Phase 5 — Install binaries
# ---------------------------------------------------------------------------
info "Installing binaries to $INSTALL_BIN"
install -m 0755 "$TMPDIR/ad-gateway-proxy"   "$INSTALL_BIN/ad-gateway-proxy"
install -m 0755 "$TMPDIR/ad-gateway-control" "$INSTALL_BIN/ad-gateway-control"
ok "Binaries installed"

# ---------------------------------------------------------------------------
# Phase 6 — Support scripts
# ---------------------------------------------------------------------------
info "Installing support scripts"
fetch "$REPO_RAW/deployment/ntlm-gate.sh" "$INSTALL_OPT/iptables/ntlm-gate.sh"
chmod +x "$INSTALL_OPT/iptables/ntlm-gate.sh"
ok "ntlm-gate.sh installed to $INSTALL_OPT/iptables/"
# Note: apply-dns-cutover.ps1 and RefreshDCLocator.ps1 are PowerShell scripts
# for the DC admin — download them from the repo on the Windows DC, not here.

# ---------------------------------------------------------------------------
# Phase 7 — Config examples
# ---------------------------------------------------------------------------
info "Installing config examples"
fetch "$REPO_RAW/proxy.yml.example"   "$INSTALL_ETC/proxy.yml.example"
fetch "$REPO_RAW/control.yml.example" "$INSTALL_ETC/control.yml.example"
fetch "$REPO_RAW/app.env.example"     "$INSTALL_ETC/app.env.example"

# Place real configs only if they don't already exist (don't overwrite on upgrade)
if [[ ! -f "$INSTALL_ETC/proxy.yml" ]]; then
    cp "$INSTALL_ETC/proxy.yml.example"   "$INSTALL_ETC/proxy.yml"
    chown "$SERVICE_USER:$SERVICE_USER"   "$INSTALL_ETC/proxy.yml"
    ok "proxy.yml placed (edit before starting)"
else
    ok "proxy.yml already exists — not overwritten"
fi

if [[ ! -f "$INSTALL_ETC/control.yml" ]]; then
    cp "$INSTALL_ETC/control.yml.example"  "$INSTALL_ETC/control.yml"
    chown "$SERVICE_USER:$SERVICE_USER"    "$INSTALL_ETC/control.yml"
    ok "control.yml placed (edit before starting)"
else
    ok "control.yml already exists — not overwritten"
fi

if [[ ! -f "$INSTALL_ETC/app.env" ]]; then
    cp "$INSTALL_ETC/app.env.example"  "$INSTALL_ETC/app.env"
    chown root:"$SERVICE_USER"         "$INSTALL_ETC/app.env"
    chmod 640                          "$INSTALL_ETC/app.env"
    ok "app.env placed — fill in AUTHNULL_ORG_ID, AUTHNULL_TENANT_ID, tokens, etc."
else
    ok "app.env already exists — not overwritten"
fi

# ---------------------------------------------------------------------------
# Phase 8 — systemd units
# ---------------------------------------------------------------------------
info "Installing systemd units"
fetch "$REPO_RAW/systemd/ad-gateway-proxy.service"   \
    "/etc/systemd/system/ad-gateway-proxy.service"
fetch "$REPO_RAW/systemd/ad-gateway-control.service" \
    "/etc/systemd/system/ad-gateway-control.service"
systemctl daemon-reload
ok "systemd units installed (not started yet)"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
PROXY_VER=$("$INSTALL_BIN/ad-gateway-proxy"   --version 2>/dev/null || echo "installed")
CTRL_VER=$( "$INSTALL_BIN/ad-gateway-control" --version 2>/dev/null || echo "installed")

echo
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  AuthNull AD Gateway — installation complete                   │"
echo "└─────────────────────────────────────────────────────────────────┘"
echo
echo "  ad-gateway-proxy   : $PROXY_VER"
echo "  ad-gateway-control : $CTRL_VER"
echo
echo "Next steps:"
echo
echo "  1. Fill in /etc/authnull/app.env  ← start here"
echo "       AUTHNULL_ORG_ID, AUTHNULL_TENANT_ID  — from your AuthNull tenant dashboard"
echo "       AUTHNULL_EMAIL_DOMAIN  — e.g. your-company.com"
echo "       AD_BIND_PW  — only if you enabled ad.ldap_url in control.yml"
echo
echo "  2. Edit /etc/authnull/proxy.yml"
echo "       Set: realm, upstream_kdc, upstream_ldap, control_plane_url"
echo
echo "  3. Edit /etc/authnull/control.yml  (mfa_bridge.* already reads from app.env)"
echo "       Uncomment ad: block only if you want the optional unlock-account action"
echo
echo "  4. Apply the NTLM-bypass iptables gate:"
echo "       sudo DC_IP=<DC_IP> GW_IP=<GATEWAY_IP> bash $INSTALL_OPT/iptables/ntlm-gate.sh"
echo
echo "  5. Start services:"
echo "       sudo systemctl enable --now ad-gateway-control ad-gateway-proxy"
echo "       sudo journalctl -u ad-gateway-proxy -u ad-gateway-control -n 30 --no-pager"
echo
echo "  Healthy startup shows:"
echo "    kdc proxy listening | ldap proxy listening | smb proxy listening"
echo "    uplink enabled | ad admin enabled | mfa challenge store cooldown_sec=180"
echo
echo "  DNS cutover (run on the DC as Domain Admin — PowerShell, download from repo):"
echo "    https://github.com/authnull0/windows-endpoint/tree/main/ad-gateway/deployment"
echo "    apply-dns-cutover.ps1  — adds SRV records + demotes DC priority"
echo "    RefreshDCLocator.ps1   — run on each Windows client after cutover"
echo
echo "  Full install guide: https://docs.authnull.com/ad-gateway/install"
echo
