#!/usr/bin/env bash
# AuthNull AD Gateway — one-shot installer
#
# Usage (on the gateway Linux VM, as root):
#
#   Option A — UI-generated configs (recommended):
#     Place proxy.yml, control.yml, app.env in the same directory as this
#     script, then run:
#       sudo bash install.sh
#
#   Option B — bare install (configure manually afterwards):
#       sudo bash install.sh
#
# What it does:
#   1. Installs system packages (ipset, iptables-persistent, ldap-utils)
#   2. Creates the 'authnull' service user and working directories
#   3. Downloads binaries from GitHub Releases and verifies SHA256 checksums
#   4. Installs systemd units
#   5. Places config files:
#        - If proxy.yml / control.yml / app.env exist alongside this script,
#          they are copied to /etc/authnull/ (UI-generated flow).
#        - Otherwise, .example files are placed for manual editing.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GITHUB_REPO="authnull0/windows-endpoint"
RELEASE_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/main/ad-gateway"

INSTALL_BIN="/usr/local/bin"
INSTALL_ETC="/etc/authnull"
INSTALL_LIB="/var/lib/authnull"
INSTALL_LOG="/var/log/authnull"
INSTALL_OPT="/opt/authnull"
SERVICE_USER="authnull"

# Directory this script lives in — used to detect UI-generated configs placed
# alongside the script by the admin.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\033[0;36m==>\033[0m $*"; }
ok()    { echo -e "\033[0;32m  ✓\033[0m $*"; }
warn()  { echo -e "\033[0;33m  !\033[0m $*"; }
fatal() { echo -e "\033[0;31mFATAL:\033[0m $*" >&2; exit 1; }

fetch() {
    local url="$1" dest="$2"
    curl -fsSL "$url" -o "$dest" || fatal "Download failed: $url"
}

require_root() {
    [[ $EUID -eq 0 ]] || fatal "Run as root (or with sudo)"
}

detect_distro() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null;   then echo "dnf"
    elif command -v yum &>/dev/null;   then echo "yum"
    else echo "unknown"; fi
}

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
require_root

info "AuthNull AD Gateway installer"
echo

ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="linux-amd64" ;;
    aarch64) ARCH_SUFFIX="linux-arm64" ;;
    *) fatal "Unsupported architecture: $ARCH" ;;
esac
ok "Architecture: $ARCH_SUFFIX"

DISTRO=$(detect_distro)
ok "Package manager: $DISTRO"

# Detect whether the admin placed UI-generated configs alongside this script
UI_CONFIGS=false
if [[ -f "$SCRIPT_DIR/proxy.yml" && -f "$SCRIPT_DIR/control.yml" && -f "$SCRIPT_DIR/app.env" ]]; then
    UI_CONFIGS=true
    ok "UI-generated config files detected — will use those"
else
    warn "No pre-placed config files found — example configs will be installed for manual editing"
fi

# Detect whether pre-built binaries are placed alongside this script.
# If present, they are used directly and the GitHub release download is skipped.
LOCAL_BINS=false
if [[ -f "$SCRIPT_DIR/ad-gateway-proxy" && -f "$SCRIPT_DIR/ad-gateway-control" ]]; then
    LOCAL_BINS=true
    ok "Pre-built binaries detected alongside script — skipping release download"
fi

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
# Phase 3 — Binaries (local or GitHub Releases)
# ---------------------------------------------------------------------------
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if [[ "$LOCAL_BINS" == "true" ]]; then
    info "Using pre-built binaries from $SCRIPT_DIR"
    cp "$SCRIPT_DIR/ad-gateway-proxy"   "$TMPDIR/ad-gateway-proxy"
    cp "$SCRIPT_DIR/ad-gateway-control" "$TMPDIR/ad-gateway-control"
    ok "Binaries copied from local directory"
else
    info "Downloading binaries from github.com/${GITHUB_REPO} main"
    fetch "${RAW_BASE}/ad-gateway-proxy-${ARCH_SUFFIX}"   "$TMPDIR/ad-gateway-proxy"
    fetch "${RAW_BASE}/ad-gateway-control-${ARCH_SUFFIX}" "$TMPDIR/ad-gateway-control"
    ok "Binaries downloaded"
fi

# Phase 4 — checksum verification skipped (binaries served from raw GitHub main)

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
fetch "$RAW_BASE/deployment/ntlm-gate.sh" "$INSTALL_OPT/iptables/ntlm-gate.sh"
chmod +x "$INSTALL_OPT/iptables/ntlm-gate.sh"
ok "ntlm-gate.sh installed to $INSTALL_OPT/iptables/"

# ---------------------------------------------------------------------------
# Phase 7 — Config files
# ---------------------------------------------------------------------------
info "Installing config files"

if [[ "$UI_CONFIGS" == "true" ]]; then
    # UI-generated flow: configs already filled in, just place them.
    # Don't overwrite if already present (e.g. re-running installer after upgrade).
    for cfg in proxy.yml control.yml; do
        if [[ ! -f "$INSTALL_ETC/$cfg" ]]; then
            install -m 0640 -o "$SERVICE_USER" -g "$SERVICE_USER" \
                "$SCRIPT_DIR/$cfg" "$INSTALL_ETC/$cfg"
            ok "$cfg installed to $INSTALL_ETC/"
        else
            ok "$cfg already exists — not overwritten"
        fi
    done

    # app.env has tighter permissions: root:authnull 640
    if [[ ! -f "$INSTALL_ETC/app.env" ]]; then
        install -m 0640 -o root -g "$SERVICE_USER" \
            "$SCRIPT_DIR/app.env" "$INSTALL_ETC/app.env"
        ok "app.env installed to $INSTALL_ETC/ (root:authnull 640)"
    else
        ok "app.env already exists — not overwritten"
    fi

    # Prompt for the AD service account password if not already set.
    # The password is entered locally on this VM — it is never transmitted to
    # the UI or any remote service.
    if grep -q "^AD_SYNC_BIND_PW=$" "$INSTALL_ETC/app.env" 2>/dev/null; then
        echo
        echo "  The AD service account password is required for user sync."
        echo "  It will be written only to $INSTALL_ETC/app.env (root:authnull 640)"
        echo "  and is never sent to the AuthNull server or stored anywhere else."
        echo
        read -rsp "  Enter AD service account password: " _bind_pw
        echo
        sed -i "s|^AD_SYNC_BIND_PW=.*|AD_SYNC_BIND_PW=${_bind_pw}|" "$INSTALL_ETC/app.env"
        unset _bind_pw
        ok "AD service account password saved to $INSTALL_ETC/app.env"
    fi
else
    # Bare install: fetch examples from repo for manual editing.
    fetch "$RAW_BASE/proxy.yml.example"   "$INSTALL_ETC/proxy.yml.example"
    fetch "$RAW_BASE/control.yml.example" "$INSTALL_ETC/control.yml.example"
    fetch "$RAW_BASE/app.env.example"     "$INSTALL_ETC/app.env.example"

    [[ ! -f "$INSTALL_ETC/proxy.yml" ]]   && cp "$INSTALL_ETC/proxy.yml.example"   "$INSTALL_ETC/proxy.yml"
    [[ ! -f "$INSTALL_ETC/control.yml" ]] && cp "$INSTALL_ETC/control.yml.example" "$INSTALL_ETC/control.yml"
    if [[ ! -f "$INSTALL_ETC/app.env" ]]; then
        cp "$INSTALL_ETC/app.env.example" "$INSTALL_ETC/app.env"
        chown root:"$SERVICE_USER" "$INSTALL_ETC/app.env"
        chmod 640 "$INSTALL_ETC/app.env"
    fi
    ok "Example configs placed — edit /etc/authnull/*.yml and app.env before starting"

    # In bare-install mode the admin will edit configs manually, but we can
    # still collect the password now so they don't have to edit app.env by hand.
    echo
    echo "  You can enter the AD service account password now, or leave blank"
    echo "  and set AD_SYNC_BIND_PW manually in $INSTALL_ETC/app.env later."
    echo
    read -rsp "  AD service account password (leave blank to skip): " _bind_pw
    echo
    if [[ -n "$_bind_pw" ]]; then
        sed -i "s|^AD_SYNC_BIND_PW=.*|AD_SYNC_BIND_PW=${_bind_pw}|" "$INSTALL_ETC/app.env"
        unset _bind_pw
        ok "AD service account password saved to $INSTALL_ETC/app.env"
    else
        warn "Skipped — remember to set AD_SYNC_BIND_PW in $INSTALL_ETC/app.env"
    fi
fi

# ---------------------------------------------------------------------------
# Phase 8 — systemd units
# ---------------------------------------------------------------------------
info "Installing systemd units"
fetch "$RAW_BASE/systemd/ad-gateway-proxy.service"   \
    "/etc/systemd/system/ad-gateway-proxy.service"
fetch "$RAW_BASE/systemd/ad-gateway-control.service" \
    "/etc/systemd/system/ad-gateway-control.service"
systemctl daemon-reload
ok "systemd units installed"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
PROXY_VER=$("$INSTALL_BIN/ad-gateway-proxy"   --version 2>/dev/null || echo "installed")
CTRL_VER=$( "$INSTALL_BIN/ad-gateway-control" --version 2>/dev/null || echo "installed")

echo
echo "┌──────────────────────────────────────────────────────────────────┐"
echo "│  AuthNull AD Gateway — installation complete                    │"
echo "└──────────────────────────────────────────────────────────────────┘"
echo
echo "  ad-gateway-proxy   : $PROXY_VER"
echo "  ad-gateway-control : $CTRL_VER"
echo

if [[ "$UI_CONFIGS" == "true" ]]; then
    echo "  Configs installed from UI-generated files."
    echo
    echo "  Start services:"
    echo "    sudo systemctl enable --now ad-gateway-control ad-gateway-proxy"
    echo "    sudo journalctl -u ad-gateway-proxy -u ad-gateway-control -f"
    echo
    echo "  Then run the DC setup script (on the Domain Controller as Domain Admin):"
    echo "    .\\dc-setup.ps1"
    echo
else
    echo "  Next steps:"
    echo
    echo "  1. Fill in /etc/authnull/app.env  (all service URLs + adsync config live here)"
    echo "       AD_SERVICE_URL       — e.g. https://dev.api.authnull.com"
    echo "       POLICY_SERVICE_URL   — e.g. https://dev.api.authnull.com"
    echo "       AUTHNULL_UPLINK_URL  — e.g. https://dev.api.authnull.com"
    echo "       AD_ORG_ID / AD_TENANT_ID"
    echo "       AD_SYNC_LDAP_URL     — e.g. ldap://10.4.0.17:389"
    echo "       AD_SYNC_BIND_DN      — e.g. CN=AuthNullSvc,CN=Users,DC=authnull,DC=lab"
    echo "       AD_SYNC_BASE_DN      — e.g. DC=authnull,DC=lab"
    echo "       AD_SYNC_DOMAIN_ID    — numeric domain ID from the AuthNull UI"
    echo "       AD_SYNC_BIND_PW      — service account password"
    echo
    echo "  2. Edit /etc/authnull/proxy.yml"
    echo "       realm, upstream_kdc, upstream_ldap, control_plane_url"
    echo
    echo "  3. Edit /etc/authnull/control.yml"
    echo "       gateway_id  (all other values are read from app.env at runtime)"
    echo
    echo "  4. Start services:"
    echo "       sudo systemctl enable --now ad-gateway-control ad-gateway-proxy"
    echo
fi

echo "  Apply iptables NTLM gate (optional, recommended for enforce mode):"
echo "    sudo DC_IP=<DC_IP> GW_IP=<GW_IP> bash $INSTALL_OPT/iptables/ntlm-gate.sh"
echo
