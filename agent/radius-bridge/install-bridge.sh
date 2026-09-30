#!/usr/bin/env bash
#
# Installs the AuthNull RADIUS bridge on a FreeRADIUS host.
#
# Usage:
#   sudo ./install-bridge.sh ./authnull-radius-mfa-linux-amd64
#   sudo ./install-bridge.sh --check      preflight only, change nothing
#   sudo ./install-bridge.sh --help
#
# Runs on the CUSTOMER'S FreeRADIUS server, which is a different machine from the
# Authnull stack. Nothing here touches docker or the compose deployment.
#
# Idempotent. An existing config file is never overwritten -- it holds ORG_ID and
# TENANT_ID, and replacing those points the bridge at the wrong tenant.
#
# Every step here exists because it was got wrong once during testing. See
# ../docs/RADIUS.md for the failure each one prevents.

set -euo pipefail

readonly BIN_DEST="/usr/local/bin/authnull-radius-mfa"
readonly CONF_DIR="/etc/authnull"
readonly CONF_FILE="${CONF_DIR}/radius-bridge.env"
readonly LOG_DIR="/var/log/authnull"
readonly MODULE_NAME="authnull"

say()  { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*"; }
die()  { printf '  \033[31mfail\033[0m  %s\n' "$*" >&2; exit 1; }

# ── locate FreeRADIUS ────────────────────────────────────────────────────────
#
# The config directory and the service account differ by distribution, and guessing
# wrong installs a module FreeRADIUS never reads -- which looks exactly like the
# bridge not working.
detect_freeradius() {
	for d in /etc/freeradius/3.0 /etc/freeradius /etc/raddb; do
		[ -d "$d" ] && { RADDB="$d"; break; }
	done
	[ -n "${RADDB:-}" ] || die "FreeRADIUS config directory not found (looked in /etc/freeradius/3.0, /etc/freeradius, /etc/raddb)"

	for u in freerad radiusd radius; do
		id "$u" >/dev/null 2>&1 && { RADUSER="$u"; break; }
	done
	[ -n "${RADUSER:-}" ] || die "FreeRADIUS service account not found (looked for freerad, radiusd, radius)"

	# Debian/Ubuntu ship a top-level `users` file that the files module does NOT read;
	# it reads mods-config/files/authorize. An entry in the wrong one is silently
	# ignored and presents as a password failure.
	if [ -f "${RADDB}/mods-config/files/authorize" ]; then
		USERS_FILE="${RADDB}/mods-config/files/authorize"
	else
		USERS_FILE="${RADDB}/users"
	fi

	# The daemon is `freeradius` on Debian/Ubuntu and `radiusd` on RHEL. Pick whichever is
	# actually on PATH -- naming the other one silently produces "command not found" at the
	# validation step, after every file has already been written.
	RADBIN=""
	for b in freeradius radiusd; do
		command -v "$b" >/dev/null 2>&1 && { RADBIN="$b"; break; }
	done

	# Service name, for the restart instruction. Usually matches the binary, but not always.
	RADSVC=""
	for s in freeradius radiusd; do
		systemctl list-unit-files "${s}.service" >/dev/null 2>&1 &&
			systemctl list-unit-files "${s}.service" 2>/dev/null | grep -q "^${s}.service" &&
			{ RADSVC="$s"; break; }
	done
	[ -n "$RADSVC" ] || RADSVC="${RADBIN:-freeradius}"
}

# ── preflight ────────────────────────────────────────────────────────────────
check() {
	echo "Preflight:"
	detect_freeradius
	ok "FreeRADIUS config     ${RADDB}"
	ok "service account       ${RADUSER}"
	ok "users file in use     ${USERS_FILE}"
	if [ -n "$RADBIN" ]; then
		ok "control binary        ${RADBIN}"
	else
		warn "no freeradius/radiusd binary on PATH -- the package is not installed, so the"
		warn "config cannot be validated. Install freeradius (and freeradius-utils for"
		warn "radclient) before running this."
	fi

	[ -f "${RADDB}/radiusd.conf" ] || warn "radiusd.conf missing under ${RADDB}"

	if grep -qs 'max_request_time' "${RADDB}/radiusd.conf"; then
		local mrt
		mrt=$(grep -oE 'max_request_time[[:space:]]*=[[:space:]]*[0-9]+' "${RADDB}/radiusd.conf" | grep -oE '[0-9]+$' | head -1)
		if [ "${mrt:-0}" -lt 90 ]; then
			warn "max_request_time = ${mrt:-unset}; needs 90 (a push takes 10-30s of human time)"
		else
			ok "max_request_time      ${mrt}"
		fi
	fi

	if [ -f "$CONF_FILE" ]; then
		ok "config exists         ${CONF_FILE} (will not be overwritten)"
	else
		say "config will be created at ${CONF_FILE} -- you must edit it"
	fi

	# The BlastRADIUS mitigation refuses packets carrying a Message-Authenticator
	# unless the client entry opts in. Every modern client sends one.
	if ! grep -qs 'require_message_authenticator' "${RADDB}/clients.conf"; then
		warn "no client sets require_message_authenticator; see ../docs/RADIUS.md#blastradius"
	fi
	echo
}

# Fixed text rather than sed over the header: a range of line numbers silently prints the
# wrong thing the first time anyone edits the comment above.
usage() {
	cat <<'EOF'
Installs the AuthNull RADIUS bridge on a FreeRADIUS host.

Usage:
  sudo ./install-bridge.sh ./authnull-radius-mfa-linux-amd64
  sudo ./install-bridge.sh --check      preflight only, change nothing
  sudo ./install-bridge.sh --help

Runs on the FreeRADIUS server, not in the compose stack. Idempotent: an existing
/etc/authnull/radius-bridge.env is never overwritten.

See ../docs/RADIUS.md for what each step prevents.
EOF
}

case "${1:-}" in
	--help|-h) usage; exit 0 ;;
	--check)   check; exit 0 ;;
	"")        usage; die "give the path to the binary, or --check" ;;
esac

SRC="$1"
[ -f "$SRC" ] || die "binary not found: $SRC"
[ "$(id -u)" -eq 0 ] || die "run with sudo"

check
detect_freeradius

echo "Installing:"

# ── binary ───────────────────────────────────────────────────────────────────
install -m 0755 -o root -g root "$SRC" "$BIN_DEST"
ok "binary                ${BIN_DEST}"

# ── config ───────────────────────────────────────────────────────────────────
#
# GROUP freerad ON THE DIRECTORY, not just the file. 0750 root:root means the service
# account cannot traverse into it, the bridge exits 1 before it can even log why, and
# FreeRADIUS rejects every login with nothing in the bridge log to explain it.
install -d -m 0750 -o root -g "$RADUSER" "$CONF_DIR"
if [ -f "$CONF_FILE" ]; then
	ok "config kept           ${CONF_FILE} (already present)"
else
	install -m 0640 -o root -g "$RADUSER" "$(dirname "$0")/radius-bridge.env.example" "$CONF_FILE"
	warn "config created        ${CONF_FILE} -- EDIT IT before the first login"
fi

install -d -m 0750 -o "$RADUSER" -g "$RADUSER" "$LOG_DIR"
ok "log directory         ${LOG_DIR}"

# ── the exec module ──────────────────────────────────────────────────────────
#
# Every attribute is passed by NAME. --packet-src-ip matters most: it is the UDP source
# address FreeRADIUS observed, which no client can omit or forge past the shared secret,
# and it is what identifies the device. NAS-IP-Address is client-supplied and can be
# absent or wrong.
cat > "${RADDB}/mods-available/${MODULE_NAME}" <<EOF
# Installed by install-bridge.sh. See onprem/docs/RADIUS.md.
exec authnull_mfa {
    wait    = yes
    program = "${BIN_DEST} --user='%{User-Name}' --nas-ip='%{NAS-IP-Address}' --nas-id='%{NAS-Identifier}' --packet-src-ip='%{Packet-Src-IP-Address}' --station='%{Calling-Station-Id}' --service-type='%{Service-Type}' --session-id='%{Acct-Session-Id}' --nas-port='%{NAS-Port}'"
    timeout = 90
}
EOF
ln -sf "../mods-available/${MODULE_NAME}" "${RADDB}/mods-enabled/${MODULE_NAME}"
ok "module                ${RADDB}/mods-enabled/${MODULE_NAME}"

# ── post-auth hook ───────────────────────────────────────────────────────────
#
# post-auth, NOT authorize: the password must already have succeeded. A reject goes to
# Post-Auth-Type REJECT instead, which is why a wrong password never reaches the bridge
# and an approved push cannot rescue one.
SITE="${RADDB}/sites-enabled/default"
# The backup goes in sites-available, NOT beside the site: FreeRADIUS loads every file in
# sites-enabled, so a copy there is a second "default" server and the config no longer
# validates -- which failed every fresh install.
SITE_BACKUP="${RADDB}/sites-available/default.pre-authnull"
if [ ! -f "$SITE" ]; then
	warn "no ${SITE}; add the hook manually (see ../docs/RADIUS.md)"
elif grep -q 'authnull_mfa' "$SITE"; then
	ok "post-auth hook        already present"
else
	# cp -n "$SITE" "${SITE}.pre-authnull" 2>/dev/null || true
	cp -n "$SITE" "$SITE_BACKUP" 2>/dev/null || true
	python3 - "$SITE" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
hook = '''
\tauthnull_mfa
\tif (fail) {
\t\tupdate reply { Reply-Message := "MFA denied or not approved in time" }
\t\treject
\t}
'''
i = s.index('post-auth {') + len('post-auth {')
open(p, 'w').write(s[:i] + hook + s[i:])
PY
	# ok "post-auth hook        inserted (backup at ${SITE}.pre-authnull)"
	ok "post-auth hook        inserted (backup at ${SITE_BACKUP})"
fi

# ── timeouts ─────────────────────────────────────────────────────────────────
if grep -qs 'max_request_time' "${RADDB}/radiusd.conf"; then
	sed -i 's/^[[:space:]]*max_request_time[[:space:]]*=.*/max_request_time = 90/' "${RADDB}/radiusd.conf"
	ok "max_request_time      90"
fi

# ── validate ─────────────────────────────────────────────────────────────────
echo
if [ -z "$RADBIN" ]; then
	warn "cannot validate: no freeradius/radiusd on PATH. Install FreeRADIUS, then re-run"
	warn "this script -- it is idempotent and will keep the config you edited."
elif "$RADBIN" -XC >/dev/null 2>&1; then
	ok "configuration validates"
else
	echo
	"$RADBIN" -XC 2>&1 | tail -15
	die "configuration does NOT validate -- nothing was started"
fi

cat <<EOF

Next:
  1. edit ${CONF_FILE}
       API_BASE_URL, ORG_ID, TENANT_ID and DOMAIN are required and have no defaults
  2. add your VPN or switch as a RADIUS client in ${RADDB}/clients.conf
       set require_message_authenticator per ../docs/RADIUS.md#blastradius
  3. raise the RADIUS timeout ON THE APPLIANCE to 60s+ with 1 retry
       without this the request dies while the user is still reaching for their phone
  4. systemctl restart ${RADSVC}
  5. test:
       echo "User-Name=alice,User-Password=..." | radclient -t 90 -r 1 127.0.0.1:1812 auth <secret>

     Use radclient, NOT radtest: radtest's timeout is fixed at ~3s x 3 and it gives up
     mid-approval, which looks like a failure and is not one.

  logs: tail -f ${LOG_DIR}/radius-bridge.log
EOF
