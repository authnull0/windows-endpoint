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

# clients_without_message_authenticator prints the name of every uncommented "client NAME {"
# block in a clients.conf that has no require_message_authenticator line.
clients_without_message_authenticator() {
	[ -f "$1" ] || return 0
	awk '
		/^[[:space:]]*#/ { next }
		/^[[:space:]]*client[[:space:]]+[^[:space:]{]+[[:space:]]*\{/ {
			name = $2; sub(/\{.*/, "", name); inblock = 1; depth = 0; has = 0
		}
		inblock {
			line = $0; sub(/#.*/, "", line)
			if (line ~ /require_message_authenticator/) has = 1
			depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
			if (depth <= 0) { if (!has) print name; inblock = 0 }
		}
	' "$1"
}

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
	# if ! grep -qs 'require_message_authenticator' "${RADDB}/clients.conf"; then
	# 	warn "no client sets require_message_authenticator; see ../docs/RADIUS.md#blastradius"
	# fi
	# Per client (RADIUS MFA plan, WS3.5): one client that sets it no longer hides the others
	# that do not. BlastRADIUS is CVE-2024-3596.
	local unset_clients
	unset_clients=$(clients_without_message_authenticator "${RADDB}/clients.conf")
	for c in $unset_clients; do
		warn "client ${c} does not set require_message_authenticator (BlastRADIUS, CVE-2024-3596); see ../docs/RADIUS.md#blastradius"
	done
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
  sudo ./install-bridge.sh --ad         connect FreeRADIUS to Active Directory (LDAP), then
                                        test a login -- after the install above
  sudo ./install-bridge.sh --help

Runs on the FreeRADIUS server, not in the compose stack. Idempotent: an existing
/etc/authnull/radius-bridge.env is never overwritten.

See ../docs/RADIUS.md for what each step prevents.
EOF
}

# insert_into SECTION LINE [first|last]: LINE right after "SECTION {", or right before its
# closing brace (comments are ignored when counting braces).
insert_into() {
	local section="$1" line="$2" where="$3" tmp
	tmp="$(mktemp)"
	awk -v sec="$section" -v line="$line" -v where="$where" '
		function braces(s,   t) { t = s; sub(/#.*/, "", t); return gsub(/\{/, "{", t) - gsub(/\}/, "}", t) }
		!done && !inside && $0 ~ "^[[:space:]]*" sec "[[:space:]]*\\{" {
			print
			if (where == "first") { print line; done = 1; next }
			inside = 1; depth = braces($0); next
		}
		inside {
			d = braces($0)
			if (depth + d <= 0) { print line; print; inside = 0; done = 1; next }
			depth += d
		}
		{ print }
	' "$SITE" > "$tmp"
	cat "$tmp" > "$SITE"
	rm -f "$tmp"
}

# ── connect to Active Directory (WS9.2) ──────────────────────────────────────
#
# FreeRADIUS checks the password against AD, the bridge adds the second factor. This step does
# the first half the customer otherwise has to work out from FreeRADIUS's docs: the ldap module
# pointed at a domain controller (search for the user by sAMAccountName, then bind as them with
# the password they typed), Auth-Type LDAP for password logins, a restart, and a test login
# through the whole chain -- AD password, then the AuthNull push.
#
# Values come from the config file (AD_SERVER, AD_BASE_DN, AD_BIND_DN; the console's app.env
# fills them from the directory picked), else they are asked for. The service account's password
# is always asked for, never kept in app.env; it goes into the ldap module, root:<radius group>
# 0640, which FreeRADIUS needs to read it.

conf_value() { # KEY -> value from the config file, "" when absent
	[ -f "$CONF_FILE" ] && sed -n "s/^${1}=//p" "$CONF_FILE" | tail -1 | tr -d '\r' || true
}

# have_tty: a terminal can actually be opened -- /dev/tty exists, and looks readable, even when
# there is none (a pipe, a container), and then reading it fails.
have_tty() { { : < /dev/tty; } 2>/dev/null; }

ask() { # VAR "question" [default] [silent]
	local var="$1" q="$2" def="${3:-}" ans=""
	have_tty || die "no terminal to ask '${q}' -- set ${var} in ${CONF_FILE} (or the environment) and re-run"
	if [ -n "${4:-}" ]; then
		printf '  %s: ' "$q" > /dev/tty; IFS= read -rs ans < /dev/tty; printf '\n' > /dev/tty
	else
		printf '  %s%s: ' "$q" "${def:+ [${def}]}" > /dev/tty; IFS= read -r ans < /dev/tty
	fi
	printf -v "$var" '%s' "${ans:-$def}"
}

# A value inside a single-quoted FreeRADIUS string.
fr_quote() { printf "'%s'" "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")"; }

configure_ad() {
	[ "$(id -u)" -eq 0 ] || die "run with sudo"
	detect_freeradius
	[ -n "$RADBIN" ] || die "FreeRADIUS is not installed"
	[ -x "$BIN_DEST" ] || die "install the bridge first: sudo ./install-bridge.sh ./authnull-radius-mfa-linux-amd64"
	local site="${RADDB}/sites-enabled/default"
	[ -f "$site" ] || die "no ${site}"
	echo "Connect FreeRADIUS to Active Directory (LDAP):"

	local server="${AD_SERVER:-$(conf_value AD_SERVER)}" base="${AD_BASE_DN:-$(conf_value AD_BASE_DN)}"
	local binddn="${AD_BIND_DN:-$(conf_value AD_BIND_DN)}" bindpw="${AD_BIND_PASSWORD:-}" domain
	domain="$(conf_value DOMAIN)"
	[ -n "$server" ] || ask server "Domain controller (host, or host:636 for LDAPS)" "$domain"
	[ -n "$server" ] || die "no domain controller given"
	if [ -z "$base" ]; then
		# authnull.lab -> DC=authnull,DC=lab
		local guess=""
		[ -n "$domain" ] && guess="DC=$(printf '%s' "$domain" | sed 's/\./,DC=/g')"
		ask base "Base DN to search for users" "$guess"
	fi
	[ -n "$base" ] || die "no base DN given"
	[ -n "$binddn" ] || ask binddn "Service account to search with (e.g. svc-radius@${domain:-corp.example})"
	[ -n "$binddn" ] || die "no service account given"
	[ -n "$bindpw" ] || ask bindpw "Password of ${binddn}" "" silent
	[ -n "$bindpw" ] || die "no service account password given"

	local host="${server%%:*}" port="389" scheme="ldap" tls=""
	[ "$host" != "$server" ] && port="${server##*:}"
	# LDAPS: needed where the DC enforces LDAP signing, which refuses a plain simple bind. The
	# DC's certificate is checked unless AD_TLS_REQUIRE_CERT=allow (a lab DC, self-signed).
	if [ "$port" = "636" ]; then
		scheme="ldaps"
		local req="${AD_TLS_REQUIRE_CERT:-$(conf_value AD_TLS_REQUIRE_CERT)}"
		[ "$req" = "allow" ] || req="demand"
		tls="	tls {
		require_cert = '${req}'
	}"
	fi

	# The ldap module. Its own copy of the old one, outside mods-enabled so it is not loaded.
	local mod="${RADDB}/mods-available/ldap"
	[ -f "$mod" ] && cp -n "$mod" "${mod}.pre-authnull" 2>/dev/null || true
	umask 027
	cat > "$mod" <<EOF
# Written by install-bridge.sh --ad. See onprem/docs/RADIUS.md. The original, if any, is
# ldap.pre-authnull beside this file.
ldap {
	server = $(fr_quote "${scheme}://${host}")
	port = ${port}
	identity = $(fr_quote "$binddn")
	password = $(fr_quote "$bindpw")
	base_dn = $(fr_quote "$base")
	user {
		base_dn = "\${..base_dn}"
		filter = "(sAMAccountName=%{%{Stripped-User-Name}:-%{User-Name}})"
		scope = 'sub'
	}
	options {
		chase_referrals = yes
		rebind = yes
		net_timeout = 5
		res_timeout = 10
		srv_timelimit = 10
	}
	pool {
		start = 0
		min = 0
		max = \${thread[pool].max_servers}
		spare = 1
		uses = 0
		retry_delay = 30
		lifetime = 0
		idle_timeout = 60
	}
${tls}
}
EOF
	umask 022
	chown root:"$RADUSER" "$mod"
	chmod 0640 "$mod"
	ln -sf ../mods-available/ldap "${RADDB}/mods-enabled/ldap"
	ok "ldap module           ${scheme}://${host}:${port}, base ${base}"

	# Password logins are checked by binding to AD as the user.
	SITE="$site"
	SITE_BACKUP="${RADDB}/sites-available/default.pre-authnull"
	cp -n "$SITE" "$SITE_BACKUP" 2>/dev/null || true
	if ! grep -q 'authnull_ad_auth_type' "$SITE"; then
		local tmp
		tmp="$(mktemp)"
		if awk '/^[[:space:]]*authorize[[:space:]]*\{/ {a=1} a && /^[[:space:]]*-?ldap[[:space:]]*$/ {f=1} END {exit !f}' "$SITE"; then
			# After the site's own ldap call, which now finds the user.
			awk '
				/^[[:space:]]*authorize[[:space:]]*\{/ { a = 1 }
				{ print }
				a && !done && /^[[:space:]]*-?ldap[[:space:]]*$/ { print "\tauthnull_ad_auth_type"; done = 1 }
			' "$SITE" > "$tmp"
		else
			awk '!done && /^[[:space:]]*authnull_code_prepare[[:space:]]*$/ { print "\tldap"; print "\tauthnull_ad_auth_type"; done = 1 } { print }' "$SITE" > "$tmp"
		fi
		cat "$tmp" > "$SITE"
		rm -f "$tmp"
	fi
	grep -Eq '^[[:space:]]*Auth-Type[[:space:]]+LDAP[[:space:]]*\{' "$SITE" ||
		insert_into authenticate "\tAuth-Type LDAP {\n\t\tldap\n\t}" first
	if grep -q 'authnull_ad_auth_type' "$SITE" && grep -Eq '^[[:space:]]*Auth-Type[[:space:]]+LDAP' "$SITE"; then
		ok "site                  password logins checked against AD"
	else
		die "could not add the LDAP hooks to ${SITE}; see ../docs/RADIUS.md"
	fi

	"$RADBIN" -XC >/dev/null 2>&1 || { "$RADBIN" -XC 2>&1 | tail -15; die "configuration does NOT validate"; }
	ok "configuration validates"
	if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
		systemctl restart "$RADSVC" && ok "restarted             ${RADSVC}" || die "${RADSVC} did not restart: journalctl -u ${RADSVC}"
		sleep 2
	else
		warn "restart FreeRADIUS yourself before the test login below"
	fi

	# The test login: through FreeRADIUS on this host, so AD and the AuthNull push both run.
	command -v radclient >/dev/null 2>&1 || { warn "no radclient (package freeradius-utils): skipping the test login"; return 0; }
	local secret user pw out
	secret="$(awk '/^[[:space:]]*client[[:space:]]+localhost[[:space:]]*\{/ {c=1} c && /^[[:space:]]*secret[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/, ""); gsub(/["[:space:]]/, ""); print; exit}' "${RADDB}/clients.conf")"
	[ -n "$secret" ] || { warn "no localhost client in clients.conf: skipping the test login"; return 0; }
	have_tty || { warn "no terminal: skipping the test login"; return 0; }
	echo
	ask user "Test login -- a directory username (empty to skip)"
	[ -n "$user" ] || return 0
	ask pw "Password of ${user}" "" silent
	say "logging in as ${user}; approve the AuthNull push if one arrives (up to 90 s)..."
	out="$(printf 'User-Name = "%s", User-Password = "%s"\n' \
		"$(printf '%s' "$user" | sed 's/[\\"]/\\&/g')" "$(printf '%s' "$pw" | sed 's/[\\"]/\\&/g')" |
		radclient -t 90 -r 1 127.0.0.1:1812 auth "$secret" 2>&1 || true)"
	if printf '%s' "$out" | grep -q 'Access-Accept'; then
		ok "test login            accepted: AD password and AuthNull MFA both passed"
	else
		warn "test login was not accepted:"
		printf '%s\n' "$out" | grep -E 'Access-|Reply-Message' | sed 's/^/        /'
		warn "Login incorrect in the FreeRADIUS log means AD refused the password or the user was not found."
	fi
}

case "${1:-}" in
	--help|-h) usage; exit 0 ;;
	--check)   check; exit 0 ;;
	--ad)      configure_ad; exit 0 ;;
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
# cat > "${RADDB}/mods-available/${MODULE_NAME}" <<EOF
# # Installed by install-bridge.sh. See onprem/docs/RADIUS.md.
# exec authnull_mfa {
#     wait    = yes
#     program = "${BIN_DEST} --user='%{User-Name}' --nas-ip='%{NAS-IP-Address}' --nas-id='%{NAS-Identifier}' --packet-src-ip='%{Packet-Src-IP-Address}' --station='%{Calling-Station-Id}' --service-type='%{Service-Type}' --session-id='%{Acct-Session-Id}' --nas-port='%{NAS-Port}'"
#     output_pairs = reply
#     timeout = 90
# }
# EOF
#
# The typed-code flags (WS7) come from server-side control attributes the policy below sets,
# never from anything a client sends: the code split off the password or typed at the prompt,
# the prompt's State, whether this call may answer with a prompt, and whether the second
# factor was already settled in this request.
cat > "${RADDB}/mods-available/${MODULE_NAME}" <<EOF
# Installed by install-bridge.sh. See onprem/docs/RADIUS.md.
exec authnull_mfa {
    wait    = yes
    program = "${BIN_DEST} --user='%{User-Name}' --nas-ip='%{NAS-IP-Address}' --nas-id='%{NAS-Identifier}' --packet-src-ip='%{Packet-Src-IP-Address}' --station='%{Calling-Station-Id}' --service-type='%{Service-Type}' --session-id='%{Acct-Session-Id}' --nas-port='%{NAS-Port}' --otp='%{control:Tmp-String-9}' --state='%{control:Tmp-String-5}' --challenge-capable='%{control:Tmp-String-7}' --decided='%{control:Tmp-String-8}'"
    output_pairs = reply
    timeout = 90
}
EOF
# output_pairs = reply: what the bridge prints goes into the reply -- the Reply-Message that
# says why a login was refused, and the admin role a device-admin policy returns (WS8.2).
# Without it FreeRADIUS discards the bridge's output.
ln -sf "../mods-available/${MODULE_NAME}" "${RADDB}/mods-enabled/${MODULE_NAME}"
ok "module                ${RADDB}/mods-enabled/${MODULE_NAME}"

# ── typed codes (WS7) ────────────────────────────────────────────────────────
#
# Instead of approving a push, a person can type the 6-digit code from the authenticator app
# they enrolled in AuthNull, two ways. Which one a login gets is up to its policy (push, code, or
# the user's choice), decided by AuthNull.
#
#   "password,123456" in the one password box (WS7.2), for any VPN -- OpenVPN included. The code
#   is taken off BEFORE the password is checked and rides to the bridge in a control attribute.
#   Trade-off: a real password that itself ends in a comma and 6 digits is split too.
#
#   An "Enter code" prompt (WS7.3), for a client with  authnull_prompt = yes  in clients.conf
#   (FortiGate, GlobalProtect, AnyConnect). The first round checks the password the way this
#   server always does, then AuthNull answers with a push or with the prompt. The second round
#   carries only the code, so it skips the password check -- and is accepted only with a State
#   AuthNull itself issued, once, within 2 minutes. AuthNull keeps that State, not this server,
#   so either of two FreeRADIUS servers can finish a login.
#
# Control attributes used (internal, never sent to a client): Tmp-String-9 the code,
# Tmp-String-5 the prompt's State, Tmp-String-6 the password check's Auth-Type, Tmp-String-7
# "the password passed, a prompt is possible", Tmp-String-8 "the second factor is settled".
install -d -m 0755 "${RADDB}/policy.d"
cat > "${RADDB}/policy.d/${MODULE_NAME}" <<'EOF'
# Installed by install-bridge.sh. See onprem/docs/RADIUS.md#typed-codes.

# Top of authorize.
authnull_otp_split {
	if (&State && ("%{client:authnull_prompt}" == "yes")) {
		# The prompt's second round: only the code. AuthNull checks it issued this State.
		update control {
			&Tmp-String-5 := "%{State}"
			&Tmp-String-9 := "%{User-Password}"
		}
		authnull_mfa
		if (ok) {
			update control {
				&Auth-Type := Accept
				&Tmp-String-8 := "yes"
			}
			return
		}
		reject
	}
	elsif (&User-Password && (&User-Password =~ /^(.+),([0-9]{6})$/)) {
		update control {
			&Tmp-String-9 := "%{2}"
		}
		update request {
			&User-Password := "%{1}"
		}
	}
}

# After the ldap module found the user (install-bridge.sh --ad): check the password by binding to
# AD as them.
authnull_ad_auth_type {
	if ((ok || updated) && &User-Password && !&control:Auth-Type) {
		update control {
			&Auth-Type := LDAP
		}
	}
}

# End of authorize: a first round on a client that prompts goes through authnull_code, which
# checks the password by the type authorize chose and then asks AuthNull. Only for the password
# checks it knows; anything else keeps the ordinary post-auth push.
authnull_code_prepare {
	if (!&State && !&control:Tmp-String-9 && ("%{client:authnull_prompt}" == "yes") && ("%{control:Auth-Type}" =~ /^(PAP|LDAP|ntlm_auth)$/)) {
		update control {
			&Tmp-String-6 := "%{control:Auth-Type}"
			&Auth-Type := authnull_code
		}
	}
}

# Auth-Type authnull_code: the password, then AuthNull -- a push or the prompt.
authnull_code_check {
	switch "%{control:Tmp-String-6}" {
		case "PAP" {
			pap
		}
		case "LDAP" {
			-ldap
		}
		case "ntlm_auth" {
			-ntlm_auth
		}
		case {
			reject
		}
	}
	if (ok) {
		update control {
			&Tmp-String-7 := "yes"
		}
		# "handled" (the prompt) would end the section by default; carry on to turn it into
		# an Access-Challenge.
		authnull_mfa {
			handled = 1
		}
		if (handled) {
			update control {
				&Response-Packet-Type := Access-Challenge
				&Tmp-String-8 := "yes"
			}
			handled
		}
		elsif (ok) {
			update control {
				&Tmp-String-8 := "yes"
			}
			ok
		}
		else {
			reject
		}
	}
}
EOF
ok "code policy           ${RADDB}/policy.d/${MODULE_NAME}"

# ── heartbeat timer (WS2.3) ──────────────────────────────────────────────────
#
# Every 60 s the bridge checks this VM (FreeRADIUS running, UDP 1812 bound, config valid, AD
# reachable) and sends one heartbeat, so the console can say Healthy, Degraded or Down and
# email the admins when it goes Down. Runs as root: the config check reads FreeRADIUS's own
# files. Needs RADIUS_SERVER_ID in the config (the console's app.env has it).
HB_UNIT=authnull-radius-heartbeat
# Only where systemd is: without /etc/systemd/system the write failed and set -e stopped the
# whole install here.
if [ -d /etc/systemd/system ]; then
cat > "/etc/systemd/system/${HB_UNIT}.service" <<EOF
# Installed by install-bridge.sh. See onprem/docs/RADIUS.md.
[Unit]
Description=AuthNull RADIUS bridge heartbeat
After=network-online.target

[Service]
Type=oneshot
ExecStart=${BIN_DEST} --heartbeat
EOF
cat > "/etc/systemd/system/${HB_UNIT}.timer" <<EOF
# Installed by install-bridge.sh. See onprem/docs/RADIUS.md.
[Unit]
Description=AuthNull RADIUS bridge heartbeat, every 60 seconds

[Timer]
OnActiveSec=10s
OnUnitActiveSec=60s
AccuracySec=5s

[Install]
WantedBy=timers.target
EOF
fi
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
	systemctl daemon-reload
	systemctl enable --now "${HB_UNIT}.timer" >/dev/null 2>&1 &&
		ok "heartbeat timer       ${HB_UNIT}.timer (every 60 s)" ||
		warn "could not enable ${HB_UNIT}.timer; run: systemctl enable --now ${HB_UNIT}.timer"
else
	warn "no systemd here: run '${BIN_DEST} --heartbeat' every minute some other way (cron: * * * * *)"
fi

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
	# python3 is not on a minimal Debian / RHEL server, and set -e stopped the install
	# here -- before app.env was applied. awk is on every server and does the same insert.
	# python3 - "$SITE" <<'PY'
	# import sys
	# p = sys.argv[1]
	# s = open(p).read()
	# hook = '''
	# \tauthnull_mfa
	# \tif (fail) {
	# \t\tupdate reply { Reply-Message := "MFA denied or not approved in time" }
	# \t\treject
	# \t}
	# '''
	# i = s.index('post-auth {') + len('post-auth {')
	# open(p, 'w').write(s[:i] + hook + s[i:])
	# PY
	#
	# The hook goes straight after the first uncommented "post-auth {". Written back with
	# cat, not mv: sites-enabled/default is a symlink and must stay one.
	hook_tmp="$(mktemp)"
	awk '
		!done && /^[[:space:]]*post-auth[[:space:]]*\{/ {
			print
			print "\tauthnull_mfa"
			print "\tif (fail) {"
			print "\t\tupdate reply { Reply-Message := \"MFA denied or not approved in time\" }"
			print "\t\treject"
			print "\t}"
			done = 1
			next
		}
		{ print }
	' "$SITE" > "$hook_tmp"
	cat "$hook_tmp" > "$SITE"
	rm -f "$hook_tmp"
	if grep -q 'authnull_mfa' "$SITE"; then
		# ok "post-auth hook        inserted (backup at ${SITE}.pre-authnull)"
		ok "post-auth hook        inserted (backup at ${SITE_BACKUP})"
	else
		warn "no post-auth section in ${SITE}; add the hook manually (see ../docs/RADIUS.md)"
	fi
fi

# ── typed-code hooks (WS7) ───────────────────────────────────────────────────
#
# Three inserts, each only once: authnull_otp_split first in authorize, ahead of files/ldap/pap,
# so the password they check is the one without the code; authnull_code_prepare last in
# authorize, after the module that chose the Auth-Type; and the authnull_code Auth-Type in
# authenticate. Same backup and write-back as the post-auth hook (insert_into is above, with
# the AD step that uses it too).
if [ -f "$SITE" ]; then
	cp -n "$SITE" "$SITE_BACKUP" 2>/dev/null || true
	grep -q 'authnull_otp_split' "$SITE" || insert_into authorize "\tauthnull_otp_split" first
	grep -q 'authnull_code_prepare' "$SITE" || insert_into authorize "\tauthnull_code_prepare" last
	grep -q 'Auth-Type authnull_code' "$SITE" ||
		insert_into authenticate "\tAuth-Type authnull_code {\n\t\tauthnull_code_check\n\t}" first
	if grep -q 'authnull_otp_split' "$SITE" && grep -q 'authnull_code_prepare' "$SITE" && grep -q 'Auth-Type authnull_code' "$SITE"; then
		ok "typed-code hooks      authorize + authenticate"
	else
		warn "could not add the typed-code hooks to ${SITE}; typed codes will not work (see ../docs/RADIUS.md#typed-codes)"
	fi
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
       API_BASE_URL, ORG_ID and TENANT_ID are required and have no defaults;
       RADIUS_SERVER_ID comes from the console (RADIUS Servers -> Add server) and turns
       on the heartbeat; DOMAIN is optional
  2. add your VPN or switch as a RADIUS client in ${RADDB}/clients.conf
       set require_message_authenticator per ../docs/RADIUS.md#blastradius
       add  authnull_prompt = yes  to a client that can show an "Enter code" box
       (FortiGate, Palo Alto, Cisco) -- NOT to OpenVPN; see ../docs/RADIUS.md#typed-codes
  3. raise the RADIUS timeout ON THE APPLIANCE to 60s+ with 1 retry
       without this the request dies while the user is still reaching for their phone
  4. systemctl restart ${RADSVC}
  5. test:
       echo "User-Name=alice,User-Password=..." | radclient -t 90 -r 1 127.0.0.1:1812 auth <secret>

     Use radclient, NOT radtest: radtest's timeout is fixed at ~3s x 3 and it gives up
     mid-approval, which looks like a failure and is not one.

  logs: tail -f ${LOG_DIR}/radius-bridge.log
EOF
