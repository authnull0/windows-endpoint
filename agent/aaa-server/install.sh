#!/usr/bin/env bash
#
# SOURCE OF TRUTH: authnull-service/onprem/aaa-server. The copy in windows-endpoint branch radius
# is published from there by publish.sh -- edit it there.
#
# Installer for authnull-aaa, AuthNull's RADIUS + TACACS+ server. Runs on the host that will
# take your network devices' logins.
#
#   curl -fsSL https://github.com/authnull0/windows-endpoint/raw/radius/agent/aaa-server/install.sh | sudo bash -s -- ./app.env
#   sudo bash install.sh --check          preflight only, changes nothing
#
# Read it before running it -- it runs as root.
#
# Downloads the binary, config template and systemd unit into a temporary directory, checks them
# against SHA256SUMS, then installs. app.env: write it from app.env.example after registering the server.
# Mirrors: AAA_BASE_URL=https://mirror.example/aaa-server
#
# Safe to run again: the binary and unit are replaced, /etc/authnull/aaa.yml is never overwritten, and a
# different app.env passed in replaces the current one, which is kept as app.env.bak-<time>.
#
# Console-managed servers (app.env has a SERVER_TOKEN, as the console's app.env download does): the
# devices come from the AuthNull console, so aaa.yml is written ready to use (no example devices, no
# upstream) and the service starts. Only an untouched template from an earlier run is replaced.

set -euo pipefail

readonly BASE="${AAA_BASE_URL:-https://github.com/authnull0/windows-endpoint/raw/radius/agent/aaa-server}"
readonly SVC_USER="authnull-aaa"
readonly BIN_DEST="/usr/local/bin/authnull-aaa"
readonly CONF_DIR="/etc/authnull"
readonly ENV_FILE="${CONF_DIR}/app.env"
readonly CFG_FILE="${CONF_DIR}/aaa.yml"
readonly STATE_DIR="/var/lib/authnull-aaa"
readonly LOG_DIR="/var/log/authnull-aaa"
readonly UNIT_FILE="/etc/systemd/system/authnull-aaa.service"
readonly LOGROTATE_FILE="/etc/logrotate.d/authnull-aaa"

die()  { printf '  \033[31mfail\033[0m  %s\n' "$*" >&2; exit 1; }
warn() { printf '  \033[33mwarn\033[0m  %s\n' "$*" >&2; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
say()  { printf '  %s\n' "$*"; }

have_systemd() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }

# Ports 1812/1813 UDP and 49 TCP free, systemd present. Changes nothing.
preflight() {
	local bad=0 out p proto port
	if command -v ss >/dev/null 2>&1; then
		for p in udp:1812 udp:1813 tcp:49; do
			proto="${p%%:*}"; port="${p##*:}"
			if [ "$proto" = udp ]; then out="$(ss -H -lun "sport = :${port}" 2>/dev/null)"; else out="$(ss -H -ltn "sport = :${port}" 2>/dev/null)"; fi
			if [ -n "$out" ]; then
				warn "${port}/${proto} is already in use (another RADIUS or TACACS+ server on this host?)"; bad=1
			else
				ok "${port}/${proto} is free"
			fi
		done
	else
		warn "ss not found; cannot check the ports"
	fi
	if have_systemd; then ok "systemd present"; else warn "no systemd here: the service cannot be installed; run authnull-aaa by hand"; bad=1; fi
	return "$bad"
}

# aaa.yml for a console-managed server: the console's devices are pulled with the SERVER_TOKEN, so no
# clients or upstreams here (without an upstream, AuthNull checks the passwords). Ready to start.
write_managed_config() {
	cat > "${TMP}/aaa.yml.managed" <<EOF
# authnull-aaa. Devices come from the AuthNull console (SERVER_TOKEN in app.env): add them under
# Network Devices; this server picks them up within a minute. Devices listed under clients: here are
# used too. No upstreams: AuthNull checks the passwords (add an NPS / ISE / ClearPass upstream to use AD).
listen:
  radius_auth: ":1812"   # UDP
  radius_acct: ":1813"   # UDP
  tacacs: ":49"          # TCP
clients: []
spool:
  dir: ${STATE_DIR}/spool
  max_mb: 256
log_path: ${LOG_DIR}/aaa.log
EOF
	install -m 0640 -o root -g "$SVC_USER" "${TMP}/aaa.yml.managed" "$CFG_FILE"
}

# The daemon appends to its log forever and keeps it open: logrotate trims it with copytruncate.
# Rewritten on every run (same content); skipped where logrotate is not installed.
install_logrotate() {
	if ! command -v logrotate >/dev/null 2>&1; then
		warn "logrotate not found: ${LOG_DIR}/aaa.log is never rotated; install logrotate and run this again"
		return 0
	fi
	cat > "$LOGROTATE_FILE" <<EOF
${LOG_DIR}/*.log {
	daily
	rotate 14
	compress
	missingok
	notifempty
	copytruncate
}
EOF
	chmod 0644 "$LOGROTATE_FILE"
	ok "installed         ${LOGROTATE_FILE} (daily, 14 kept)"
}

main() {
	if [ "${1:-}" = "--check" ]; then
		if preflight; then ok "preflight passed"; exit 0; fi
		warn "preflight found problems"; exit 1
	fi
	[ "$(id -u)" -eq 0 ] || die "must run as root: ... | sudo bash -s -- ./app.env"

	# Checked before anything is downloaded, so a wrong path fails with nothing changed.
	local env_src="${1:-}"
	if [ -n "$env_src" ]; then
		[ -f "$env_src" ] || die "app.env not found: ${env_src} -- write it from app.env.example"
		local k
		for k in API_BASE_URL ORG_ID TENANT_ID; do
			grep -Eq "^${k}=[^[:space:]]+" "$env_src" || die "${env_src} has no value for ${k} -- fix it (see app.env.example)"
		done
		grep -Eq "^RADIUS_SERVER_ID=[^[:space:]]+" "$env_src" ||
			say "note: ${env_src} has no RADIUS_SERVER_ID: login events and accounting wait on disk (spool) until it is set and the service restarted, and the console cannot show this server's health."
	fi

	if command -v curl >/dev/null 2>&1; then
		fetch() { curl -fsSL "$1" -o "$2"; }
	elif command -v wget >/dev/null 2>&1; then
		fetch() { wget -q "$1" -O "$2"; }
	else
		die "neither curl nor wget is available"
	fi
	command -v sha256sum >/dev/null 2>&1 || die "sha256sum not found; it is needed to verify the download"

	local arch
	case "$(uname -m)" in
		x86_64|amd64)  arch="amd64" ;;
		aarch64|arm64) arch="arm64" ;;
		*) die "unsupported architecture: $(uname -m)" ;;
	esac
	local binary="authnull-aaa-linux-${arch}"

	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT

	echo
	say "AuthNull AAA server"
	say "downloading from ${BASE}"
	echo
	local f
	for f in "$binary" aaa.yml.example authnull-aaa.service SHA256SUMS; do
		fetch "${BASE}/${f}" "${TMP}/${f}" || die "could not download ${f} from ${BASE}"
		say "got ${f}"
	done

	# Verified before anything runs as root. All three files must be listed -- a file missing from
	# SHA256SUMS is a failure, not a pass. SHA256SUMS comes from the same place as the files, so this
	# catches a broken or partial download, not a tampered one; that rests on HTTPS to GitHub.
	( cd "$TMP" &&
		grep -E "[ *](${binary}|aaa\.yml\.example|authnull-aaa\.service)\$" SHA256SUMS > want.sums &&
		[ "$(wc -l < want.sums)" -eq 3 ] &&
		sha256sum --quiet --check want.sums ) \
		|| die "checksum mismatch -- the download is incomplete or corrupt; nothing was installed"
	ok "checksums verified"

	# The service account: no login, no home.
	if ! id "$SVC_USER" >/dev/null 2>&1; then
		useradd --system --user-group --no-create-home --home-dir "$STATE_DIR" --shell /usr/sbin/nologin "$SVC_USER" \
			|| die "could not create user ${SVC_USER}"
		ok "created user      ${SVC_USER}"
	fi

	install -m 0755 -o root -g root "${TMP}/${binary}" "$BIN_DEST"
	ok "installed         ${BIN_DEST} ($("$BIN_DEST" --version 2>/dev/null || echo unknown))"

	# Holds secrets, so root:authnull-aaa 0750. An existing directory (the RADIUS bridge's, on a
	# host that has both) is left as it is.
	[ -d "$CONF_DIR" ] || install -d -m 0750 -o root -g "$SVC_USER" "$CONF_DIR"
	install -d -m 0750 -o "$SVC_USER" -g "$SVC_USER" "$STATE_DIR"
	# An existing log directory keeps its owner; the daemon falls back to stderr (journald) if it cannot write.
	if [ -d "$LOG_DIR" ]; then
		if command -v runuser >/dev/null 2>&1 && ! runuser -u "$SVC_USER" -- test -w "$LOG_DIR"; then
			warn "${SVC_USER} cannot write ${LOG_DIR} (kept as is): the log goes to journald only"
		fi
	else
		install -d -m 0750 -o "$SVC_USER" -g "$SVC_USER" "$LOG_DIR"
	fi
	install_logrotate

	# Console-managed when the app.env being installed (or, without one, the installed one) has a token.
	local managed=0 env_for_mode="${env_src:-$ENV_FILE}"
	if [ -f "$env_for_mode" ] && tr -d '\r' < "$env_for_mode" | grep -Eq '^SERVER_TOKEN=[^[:space:]]+'; then
		managed=1
	fi

	# was: kept if present, else always the template (add your devices and upstream).
	if [ -f "$CFG_FILE" ] && [ "$managed" -eq 1 ] && cmp -s "$CFG_FILE" "${TMP}/aaa.yml.example"; then
		# The untouched template from an earlier run: nothing of the operator's is in it.
		cp -p "$CFG_FILE" "${CFG_FILE}.template-$(date +%Y%m%d%H%M%S)"
		write_managed_config
		ok "installed         ${CFG_FILE} (devices from the AuthNull console; replaced the unedited template)"
	elif [ -f "$CFG_FILE" ]; then
		ok "kept              ${CFG_FILE} (never overwritten)"
	elif [ "$managed" -eq 1 ]; then
		write_managed_config
		ok "installed         ${CFG_FILE} (devices from the AuthNull console)"
	else
		install -m 0640 -o root -g "$SVC_USER" "${TMP}/aaa.yml.example" "$CFG_FILE"
		ok "installed         ${CFG_FILE} (template: add your devices and upstream)"
	fi

	if [ -n "$env_src" ]; then
		# A file edited on Windows has CRLF endings, and "ORG_ID=2\r" is not a number.
		tr -d '\r' < "$env_src" > "${TMP}/app.env"
		if [ ! -f "$ENV_FILE" ]; then
			install -m 0640 -o root -g "$SVC_USER" "${TMP}/app.env" "$ENV_FILE"
			ok "installed         ${ENV_FILE}"
		elif cmp -s "${TMP}/app.env" "$ENV_FILE"; then
			ok "kept              ${ENV_FILE} (same as ${env_src})"
		else
			# The operator passed this file on purpose, so it replaces the current one, which is kept aside.
			local backup
			backup="${ENV_FILE}.bak-$(date +%Y%m%d%H%M%S)"
			cp -p "$ENV_FILE" "$backup"
			install -m 0640 -o root -g "$SVC_USER" "${TMP}/app.env" "$ENV_FILE"
			ok "installed         ${ENV_FILE} (previous saved as ${backup})"
		fi
	elif [ ! -f "$ENV_FILE" ]; then
		warn "no app.env given and none installed: write ${ENV_FILE} from app.env.example"
	fi

	# The service account must be able to read what it was given.
	if command -v runuser >/dev/null 2>&1 && [ -f "$ENV_FILE" ] &&
		! runuser -u "$SVC_USER" -- test -r "$ENV_FILE"; then
		warn "${SVC_USER} cannot read ${ENV_FILE}: check ${CONF_DIR} and the file are group ${SVC_USER} (a directory shared with the RADIUS bridge is group freerad)"
	fi

	# A console-managed server reaches authnull-service at HEARTBEAT_URL minus its path; with an https
	# API_BASE_URL there is no default, so without it the server never turns Active nor gets its devices.
	if [ "$managed" -eq 1 ] && [ -f "$ENV_FILE" ] && ! grep -Eq '^HEARTBEAT_URL=[^[:space:]]+' "$ENV_FILE" &&
		grep -Eq '^API_BASE_URL=https://' "$ENV_FILE"; then
		warn "${ENV_FILE} has no HEARTBEAT_URL: set HEARTBEAT_URL=<AuthNull address>/api/v1/radius/heartbeat, then  systemctl restart authnull-aaa"
	fi

	local ready=1
	[ -f "$ENV_FILE" ] || ready=0
	# Only uncommented lines count: the template's comments mention CHANGE-ME too.
	if grep -Eq '^[[:space:]]*[^#[:space:]].*CHANGE-ME' "$CFG_FILE"; then
		warn "${CFG_FILE} still has CHANGE-ME placeholders: replace them with your devices' and upstream's real secrets"
		ready=0
	fi
	if [ "$ready" -eq 1 ] && ! "$BIN_DEST" --check --env "$ENV_FILE" --config "$CFG_FILE"; then
		warn "authnull-aaa --check failed (above): fix it, then start the service"
		ready=0
	fi

	if have_systemd; then
		install -m 0644 -o root -g root "${TMP}/authnull-aaa.service" "$UNIT_FILE"
		systemctl daemon-reload
		if systemctl enable authnull-aaa >/dev/null 2>&1; then ok "enabled           authnull-aaa"; else warn "could not enable authnull-aaa"; fi
		if [ "$ready" -eq 1 ]; then
			systemctl restart authnull-aaa || die "authnull-aaa did not start: journalctl -u authnull-aaa"
			sleep 2
			systemctl is-active --quiet authnull-aaa || die "authnull-aaa is not running: journalctl -u authnull-aaa -n 50"
			ok "started           authnull-aaa"
		else
			say "not started yet. When the config is done: systemctl start authnull-aaa"
		fi
	else
		warn "no systemd here: the unit was not installed. Run it as the service account, e.g."
		say "  runuser -u ${SVC_USER} -- ${BIN_DEST} --env ${ENV_FILE} --config ${CFG_FILE}"
		say "(binding ports below 1024 needs CAP_NET_BIND_SERVICE or root)"
	fi

	echo
	if [ "$managed" -eq 1 ]; then
		say "Next: add your devices in the AuthNull console (Network Devices); this server picks them up within a minute."
	elif have_systemd && systemctl is-active --quiet authnull-aaa; then
		say "Next: add your devices and upstream in ${CFG_FILE}, then  systemctl reload authnull-aaa"
	else
		say "Next: add your devices and upstream in ${CFG_FILE}, then  systemctl start authnull-aaa"
	fi
	say "Check a file:  ${BIN_DEST} --check --env ${ENV_FILE} --config ${CFG_FILE}"
	say "Log: ${LOG_DIR}/aaa.log, and journalctl -u authnull-aaa"
}

main "$@"
