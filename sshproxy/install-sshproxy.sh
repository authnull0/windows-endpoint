#!/usr/bin/env bash
#
# Installs the AuthNull SSH proxy on a jump host.
#
# Usage:
#   sudo ./install-sshproxy.sh ./authnull-sshproxy-linux-amd64
#   sudo ./install-sshproxy.sh --check      preflight only, change nothing
#   sudo ./install-sshproxy.sh --help
#
# Runs on the JUMP HOST, which is a different machine from the Authnull stack.
# Nothing here touches docker or the compose deployment: this process sits on the
# operator-to-target path, which the containers do not.
#
# Idempotent, and deliberately so in two places. An existing config file is never
# overwritten -- it holds ORG_ID and TENANT_ID, and replacing those points the
# proxy at the wrong tenant. An existing host key is never regenerated: the host
# key IS the proxy's identity, and a new one trips every client's known_hosts
# check with the warning that means an active man-in-the-middle. Since this proxy
# IS a man-in-the-middle by design, that warning has to stay meaningful.

set -euo pipefail

readonly BIN_DEST="/usr/local/bin/authnull-sshproxy"
readonly CONF_DIR="/etc/authnull/sshproxy"
readonly CONF_FILE="${CONF_DIR}/sshproxy.env"
readonly REC_DIR="/var/authnull/recordings/sshproxy"
readonly UNIT_DEST="/etc/systemd/system/authnull-sshproxy.service"
readonly SVC_USER="authnull"
readonly HERE="$(cd "$(dirname "$0")" && pwd)"

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
die()  { printf '  \033[31mfail\033[0m  %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

CHECK_ONLY=0
BINARY=""
case "${1:-}" in
	--help|-h) usage ;;
	--check)   CHECK_ONLY=1 ;;
	"")        die "no binary given. Usage: sudo $0 ./authnull-sshproxy-linux-amd64" ;;
	*)         BINARY="$1" ;;
esac

# ── preflight ────────────────────────────────────────────────────────────────

preflight() {
	[ "$(id -u)" -eq 0 ] || die "must run as root"
	ok "running as root"

	command -v systemctl >/dev/null 2>&1 || die "systemd not found; this package installs a systemd unit"
	ok "systemd present"

	command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen not found (install openssh-client)"
	ok "ssh-keygen present"

	# The proxy listens on 2222. Port 22 belongs to the host's own sshd, and
	# taking it would lock the administrator out of the machine they are
	# installing on.
	if ss -ltn 2>/dev/null | grep -q ':2222 '; then
		warn "something is already listening on 2222; the proxy will fail to bind"
	else
		ok "port 2222 is free"
	fi

	if [ -f "$CONF_FILE" ]; then
		warn "config exists and will be LEFT ALONE: ${CONF_FILE}"
	fi
	if [ -f "${CONF_DIR}/host_key" ]; then
		warn "host key exists and will be LEFT ALONE (regenerating it breaks every client's known_hosts)"
	fi
	if [ -f "${CONF_DIR}/ca_key" ]; then
		warn "CA key exists and will be LEFT ALONE (regenerating it invalidates trust on every target carrying the public half)"
	fi
}

echo
say "AuthNull SSH proxy installer"
echo
preflight

if [ "$CHECK_ONLY" -eq 1 ]; then
	echo
	ok "preflight only; nothing changed"
	exit 0
fi

[ -f "$BINARY" ] || die "binary not found: ${BINARY}"
# Checked before anything is installed: a wrong-architecture binary otherwise
# installs cleanly and then fails at start with "Exec format error", which reads
# like a systemd problem rather than a download problem.
file "$BINARY" 2>/dev/null | grep -q 'ELF.*executable' || die "not a Linux executable: ${BINARY}"
ok "binary looks like a Linux executable"

# ── service account ──────────────────────────────────────────────────────────

if id "$SVC_USER" >/dev/null 2>&1; then
	ok "service account exists  ${SVC_USER}"
else
	# No login shell and no home: this account exists to own a socket and some
	# files, and should not be a way onto the box.
	useradd --system --no-create-home --shell /usr/sbin/nologin "$SVC_USER"
	ok "created service account ${SVC_USER}"
fi

# ── directories ──────────────────────────────────────────────────────────────

install -d -o root -g "$SVC_USER" -m 0750 /etc/authnull "$CONF_DIR"
ok "config dir              ${CONF_DIR}"

# 0700 and owned by the service account: a recording is a verbatim transcript of
# a privileged session, including anything the operator typed that was echoed.
install -d -o "$SVC_USER" -g "$SVC_USER" -m 0700 /var/authnull /var/authnull/recordings "$REC_DIR"
ok "recordings dir          ${REC_DIR}"

# ── keys ─────────────────────────────────────────────────────────────────────

# Never regenerated if present. See the header.
if [ -f "${CONF_DIR}/host_key" ]; then
	ok "host key                kept"
else
	ssh-keygen -q -t ed25519 -N '' -C "authnull-sshproxy@$(hostname)" -f "${CONF_DIR}/host_key"
	ok "host key                generated"
fi

if [ -f "${CONF_DIR}/backend_key" ]; then
	ok "backend key             kept"
else
	ssh-keygen -q -t ed25519 -N '' -C "authnull-sshproxy-backend@$(hostname)" -f "${CONF_DIR}/backend_key"
	ok "backend key             generated"
fi

# One CA per proxy, generated here rather than by hand.
#
# By hand it lands 0600 root:root, and the service runs as authnull -- so it
# cannot read it, and until recently that surfaced as a session failing AFTER
# the operator had approved a push. Generating it alongside the other two keys
# is what makes the permissions right by construction.
#
# Regenerating invalidates trust on every target that already carries the
# public half, so like the host key it is never replaced if present.
if [ -f "${CONF_DIR}/ca_key" ]; then
	ok "CA key                  kept"
else
	ssh-keygen -q -t ed25519 -N '' -C "authnull-sshproxy-ca@$(hostname)" -f "${CONF_DIR}/ca_key"
	ok "CA key                  generated"
fi

# Created empty rather than left absent: the proxy creates it anyway, but a file
# that exists is one an administrator can find and inspect.
touch "${CONF_DIR}/known_hosts"

# The known_hosts file is APPENDED TO at runtime when a target is pinned on first
# use, so the service account needs write access to it and to its directory.
chown root:"$SVC_USER" "${CONF_DIR}"/host_key "${CONF_DIR}"/host_key.pub \
	"${CONF_DIR}"/backend_key "${CONF_DIR}"/backend_key.pub \
	"${CONF_DIR}"/ca_key "${CONF_DIR}"/ca_key.pub "${CONF_DIR}"/known_hosts
chmod 0640 "${CONF_DIR}"/host_key "${CONF_DIR}"/backend_key "${CONF_DIR}"/ca_key
chmod 0644 "${CONF_DIR}"/host_key.pub "${CONF_DIR}"/backend_key.pub "${CONF_DIR}"/ca_key.pub
chmod 0660 "${CONF_DIR}"/known_hosts
ok "key permissions         set"

# ── config ───────────────────────────────────────────────────────────────────

if [ -f "$CONF_FILE" ]; then
	ok "config                  kept (${CONF_FILE})"
	NEEDS_EDIT=0
else
	install -o root -g "$SVC_USER" -m 0640 "${HERE}/sshproxy.env.example" "$CONF_FILE"
	# Generated here rather than left to the administrator: an HMAC key that is
	# absent means recordings ship with no integrity sidecar, and "recommended"
	# settings that require work do not get done.
	HMAC="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
	sed -i "s|^SSHPROXY_HMAC_KEY=$|SSHPROXY_HMAC_KEY=${HMAC}|" "$CONF_FILE"
	ok "config                  installed with a generated HMAC key"
	NEEDS_EDIT=1
fi

# Runs on a FRESH install and an UPGRADE alike, which the branch above does not.
#
# An existing config is left alone wholesale, so a variable added to the example
# after a host was first installed never reaches that host. For the CA that
# would mean an upgraded proxy generating a key it is never told to use, and
# staying on the shared backend key while the release notes said otherwise.
#
# SSHPROXY_CERT_HOSTS is deliberately NOT written. Empty is what makes the
# rollout opt-in: the proxy has a CA and knows where it is, and still uses the
# backend key for every target until an operator names one and has verified the
# target accepts a certificate. Setting it here would switch an entire estate on
# upgrade, which is the failure this design exists to avoid.
if ! grep -q '^SSHPROXY_CA_KEY_PATH=' "$CONF_FILE"; then
	printf '\n# Added by the installer. Sign a per-session certificate for hosts named in\n# SSHPROXY_CERT_HOSTS; every other target keeps using the backend key.\nSSHPROXY_CA_KEY_PATH=%s/ca_key\n' "$CONF_DIR" >> "$CONF_FILE"
	ok "config                  CA key path added"
fi

# ── binary and unit ──────────────────────────────────────────────────────────

install -o root -g root -m 0755 "$BINARY" "$BIN_DEST"
ok "binary                  ${BIN_DEST}"

install -o root -g root -m 0644 "${HERE}/authnull-sshproxy.service" "$UNIT_DEST"
systemctl daemon-reload
ok "unit                    ${UNIT_DEST}"

# ── what is left for the administrator ───────────────────────────────────────

echo
if [ "${NEEDS_EDIT:-0}" -eq 1 ]; then
	say "Before starting, set these in ${CONF_FILE}:"
	say "  SSHPROXY_ORG_ID              the organisation this proxy serves"
	say "  SSHPROXY_TENANT_ID           the tenant push MFA already uses for it"
	say "  SSHPROXY_BACKEND_ALLOWLIST   the targets it may bridge to (empty denies all)"
	say "  SSHPROXY_AUTHN_URL           check the host and port are reachable from here"
	echo
fi
say "Then:"
say "  sudo systemctl enable --now authnull-sshproxy"
say "  systemctl status authnull-sshproxy"
echo
say "This proxy's host key fingerprint, which operators will be asked to trust:"
say "  $(ssh-keygen -lf "${CONF_DIR}/host_key.pub" 2>/dev/null || echo '(unavailable)')"
echo
say "This proxy's CA public key. Put it on a target to let the proxy open any"
say "account there, without touching authorized_keys per account:"
echo
say "  sudo tee /etc/ssh/authnull_ca.pub >/dev/null <<'EOF'"
say "$(cat "${CONF_DIR}/ca_key.pub" 2>/dev/null || echo '(unavailable)')"
say "EOF"
say "  sudo chmod 644 /etc/ssh/authnull_ca.pub"
say "  echo 'TrustedUserCAKeys /etc/ssh/authnull_ca.pub' |"
say "    sudo tee /etc/ssh/sshd_config.d/60-authnull-ca.conf"
say "  sudo sshd -t && sudo systemctl reload ssh"
echo
say "A drop-in rather than an edit, and sshd -t before the reload: a target is"
say "often shared, and a bad sshd_config locks everyone out. Keep a session open."
echo
warn "That line grants this CA EVERY account on the target, including root --"
warn "not just the accounts the backend key was appended to."
warn "This proxy refuses to sign for root by default (SSHPROXY_CERT_DENY_ACCOUNTS),"
warn "but that guard is ours, not the target's: anyone holding this CA key can"
warn "still mint for any account here. Bound it on the target with an"
warn "AuthorizedPrincipalsFile, or with an SSH policy. See docs/HOW-IT-WORKS.md."
echo
say "Then add that host to SSHPROXY_CERT_HOSTS and restart. Until you do, it"
say "keeps using the backend key -- so you can verify one host at a time."
echo
say "Operators then connect as:"
say "  ssh <account>@<target-host>@$(hostname):2222"
echo
