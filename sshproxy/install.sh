#!/usr/bin/env bash
#
# Bootstrap for the AuthNull SSH proxy.
#
# Read it before running it -- it runs as root:
#
#   wget https://raw.githubusercontent.com/authnull0/windows-endpoint/main/sshproxy/install.sh
#   less install.sh
#   sudo bash install.sh
#
# WHAT THIS DOES
#
# Fetches the release set into a temporary directory, checks it against
# SHA256SUMS, and hands off to install-sshproxy.sh -- which is the real
# installer, and the thing to read if you want to know what lands on the box.
#
# WHY A BOOTSTRAP AT ALL
#
# install-sshproxy.sh needs three files beside it: the binary, the systemd unit
# and the config template. It installs them with `install "${HERE}/..."`, so
# downloading it alone gets you a script that fails partway through, having
# already created a service account. One command that fetches the whole set is
# the difference between an install and a half-install.
#
# It does NOT start anything. The proxy refuses to run until it is told its
# organisation, tenant, jump-server row and decision endpoint, and those values
# come from the console.

set -euo pipefail

readonly BASE="${SSHPROXY_DOWNLOAD_BASE:-https://raw.githubusercontent.com/authnull0/windows-endpoint/main/sshproxy}"

die() { printf '  \033[31mfail\033[0m  %s\n' "$*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "must run as root: sudo bash install.sh"

# Checked before anything is downloaded. A box without systemd is not one this
# package can install onto, and finding that out after writing files is worse.
command -v systemctl >/dev/null 2>&1 || die "systemd not found; this package installs a systemd unit"

if command -v curl >/dev/null 2>&1; then
	fetch() { curl -fsSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
	fetch() { wget -q "$1" -O "$2"; }
else
	die "neither curl nor wget is available"
fi

# The binary is per-architecture and only one is published today. Naming the
# architecture in the error matters: "unsupported" with no value sends somebody
# to open a ticket, and the answer is usually that they are on arm64.
case "$(uname -m)" in
	x86_64|amd64) ARCH="amd64" ;;
	aarch64|arm64)
		die "arm64 is not published yet -- build from source with ./deploy/build.sh in the sshproxy repo" ;;
	*) die "unsupported architecture: $(uname -m)" ;;
esac
readonly BINARY="authnull-sshproxy-linux-${ARCH}"

TMP="$(mktemp -d)"
# Cleared on every exit path, success or not. The binary is ~7 MB, and a failed
# install should not leave it in /tmp to be found months later and wondered at.
trap 'rm -rf "$TMP"' EXIT

echo
say "AuthNull SSH proxy"
say "downloading from ${BASE}"
echo

for f in "$BINARY" install-sshproxy.sh authnull-sshproxy.service sshproxy.env.example SHA256SUMS; do
	fetch "${BASE}/${f}" "${TMP}/${f}" || die "could not download ${f} from ${BASE}"
	say "got ${f}"
done

# Verified before anything is executed. This script runs as root, so "the
# download was truncated or altered" has to be caught here rather than
# discovered later by a service that will not start.
if command -v sha256sum >/dev/null 2>&1; then
	( cd "$TMP" && sha256sum --quiet --check SHA256SUMS ) \
		|| die "checksum mismatch -- the download is corrupt or has been altered; nothing was installed"
	say "checksums verified"
else
	say "WARNING: sha256sum not found, skipping verification"
fi

chmod +x "${TMP}/${BINARY}" "${TMP}/install-sshproxy.sh"

echo
exec bash "${TMP}/install-sshproxy.sh" "${TMP}/${BINARY}"
