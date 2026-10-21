#!/usr/bin/env bash
#
# SOURCE OF TRUTH: authnull-service/onprem/radius-bridge (RADIUS MFA plan, WS9.1). The copy in
# windows-endpoint branch radius is published from there by publish.sh -- edit it there.
#
# Bootstrap for the AuthNull RADIUS bridge. Runs on your FreeRADIUS server.
#
#   curl -fsSL https://github.com/authnull0/windows-endpoint/raw/radius/agent/radius-bridge/install.sh | sudo bash -s -- ./app.env
#
# Add --ad to also connect FreeRADIUS to Active Directory and test a login (it asks for the
# domain controller and a service account on the terminal):
#
#   curl -fsSL .../install.sh | sudo bash -s -- ./app.env --ad
#
# Read it before running it -- it runs as root.
#
# Fetches the release set into a temporary directory, checks it against SHA256SUMS
# and hands off to install-bridge.sh, the real installer. install-bridge.sh needs its
# config template beside it, so downloading it alone gets you a half-install.
#
# Given app.env (from the console: RADIUS Servers > Add server) it then
# installs that as /etc/authnull/radius-bridge.env. Without it, edit that file by hand.

set -euo pipefail

readonly BASE="${RADIUS_BRIDGE_DOWNLOAD_BASE:-https://github.com/authnull0/windows-endpoint/raw/radius/agent/radius-bridge}"
readonly CONF_FILE="/etc/authnull/radius-bridge.env"

die() { printf '  \033[31mfail\033[0m  %s\n' "$*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

# Everything runs from main, so a download cut off halfway runs nothing at all.
main() {
	[ "$(id -u)" -eq 0 ] || die "must run as root: ... | sudo bash -s -- ./app.env"

	# --ad anywhere: connect to Active Directory after the install (WS9.2).
	local ad=0 a
	local args=()
	for a in "$@"; do
		if [ "$a" = "--ad" ]; then ad=1; else args+=("$a"); fi
	done
	set -- "${args[@]+"${args[@]}"}"

	# Checked before anything is downloaded, so a wrong path fails with nothing changed.
	# The bridge has no defaults for these three and rejects every login without them.
	# DOMAIN is optional: without it authn-service resolves each user's own directory.
	local env_src="${1:-}"
	if [ -n "$env_src" ]; then
		# [ -f "$env_src" ] || die "app.env not found: ${env_src} -- download it from Radius Devices > Connect FreeRADIUS"
		[ -f "$env_src" ] || die "app.env not found: ${env_src} -- download it from RADIUS Servers > Add server"
		local k
		# for k in API_BASE_URL ORG_ID TENANT_ID DOMAIN; do
		for k in API_BASE_URL ORG_ID TENANT_ID; do
			grep -Eq "^${k}=[^[:space:]]+" "$env_src" || die "${env_src} has no value for ${k} -- download it again from the console"
		done
		# Not required -- logins work without it ("unknown server") -- but the heartbeat does.
		grep -Eq "^RADIUS_SERVER_ID=[^[:space:]]+" "$env_src" ||
			say "note: ${env_src} has no RADIUS_SERVER_ID, so the console cannot show this server's health. Download it from RADIUS Servers."
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
	local binary="authnull-radius-mfa-linux-${arch}"

	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT

	echo
	say "AuthNull RADIUS bridge"
	say "downloading from ${BASE}"
	echo

	local f
	for f in "$binary" install-bridge.sh radius-bridge.env.example SHA256SUMS; do
		fetch "${BASE}/${f}" "${TMP}/${f}" || die "could not download ${f} from ${BASE}"
		say "got ${f}"
	done

	# Verified before anything runs as root. Only the files downloaded are checked, and
	# all three must be listed -- a file missing from SHA256SUMS is a failure, not a pass.
	# SHA256SUMS comes from the same place as the files, so this catches a broken or partial
	# download, not a tampered one; that rests on HTTPS to GitHub (review of #132).
	( cd "$TMP" &&
		grep -E "[ *](${binary}|install-bridge\.sh|radius-bridge\.env\.example)\$" SHA256SUMS > want.sums &&
		[ "$(wc -l < want.sums)" -eq 3 ] &&
		sha256sum --quiet --check want.sums ) \
		|| die "checksum mismatch -- the download is incomplete or corrupt; nothing was installed"
	say "checksums verified"

	chmod +x "${TMP}/${binary}" "${TMP}/install-bridge.sh"

	echo
	bash "${TMP}/install-bridge.sh" "${TMP}/${binary}" </dev/null

	if [ -n "$env_src" ]; then
		install_env "$env_src"
	fi
	if [ "$ad" -eq 1 ]; then
		echo
		bash "${TMP}/install-bridge.sh" --ad
	fi
}

# install_env installs the console's app.env as the bridge config.
install_env() {
	local env_src="$1"
	# A file edited on Windows has CRLF endings, and "ORG_ID=2\r" is not a number to the
	# bridge -- every login would be rejected.
	tr -d '\r' < "$env_src" > "${TMP}/app.env"

	# install-bridge.sh never overwrites a config. Here the admin passed one explicitly, so
	# it replaces the current one -- but a config that already had values is kept aside.
	if grep -Eq '^ORG_ID=[^[:space:]]+' "$CONF_FILE" 2>/dev/null && ! cmp -s "${TMP}/app.env" "$CONF_FILE"; then
		local backup
		backup="${CONF_FILE}.bak-$(date +%Y%m%d%H%M%S)"
		cp -p "$CONF_FILE" "$backup"
		say "previous config saved as ${backup}"
	fi
	install -m 0640 -o root -g "$(stat -c %G "$(dirname "$CONF_FILE")")" "${TMP}/app.env" "$CONF_FILE"

	echo
	printf '  \033[32mok\033[0m    %s\n' "config installed from ${env_src} -- step 1 above is done"
	say "Restart FreeRADIUS and test (steps 4 and 5 above)."
}

main "$@"
