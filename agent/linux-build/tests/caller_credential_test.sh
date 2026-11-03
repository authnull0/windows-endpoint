#!/usr/bin/env bash
# Test for authnull_caller_lines in run_agent.sh: ProxySQL's caller credential (DB-MFA-HARDENING
# S3) goes from db.env into the [authnull] section, a missing or malformed one is reported and not
# written, and the secret is never printed to the terminal.
#
#   bash agent/linux-build/tests/caller_credential_test.sh
#
# Runs only that function (extracted from the script). Exits non-zero on any failure.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../run_agent.sh"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

fn="$(sed -n '/^authnull_caller_lines() {/,/^}/p' "$script")"
[ -n "$fn" ] || { echo "FAIL: authnull_caller_lines() not found in run_agent.sh"; exit 1; }

secret="dps_Zx9-test_secret_value"
run() { # run ID SECRET API -> stdout in $out, stderr in $err
  local tmp; tmp="$(mktemp)"
  out="$(PROXY_CLIENT_ID="$1" PROXY_CLIENT_SECRET="$2" API="$3" bash -c "$fn"'
authnull_caller_lines' 2>"$tmp")"
  err="$(cat "$tmp")"; rm -f "$tmp"
}

# 1. A credential: three lines, token_url from the API host (trailing slash or not).
run "dpc-2-0a1b2c3d4e5f60718293a4b5c6d7e8f9" "$secret" "https://onprem.dev.authnull.com/"
want='    client_id = "dpc-2-0a1b2c3d4e5f60718293a4b5c6d7e8f9"
    client_secret = "dps_Zx9-test_secret_value"
    token_url = "https://onprem.dev.authnull.com/api/v1/database/proxy/token"'
[ "$out" = "$want" ] || fail "credential lines: [$out]"
[ -z "$err" ] || fail "unexpected warning: $err"

# 2. No credential (an older console's db.env): nothing written, and a warning that says so.
run "" "" "https://h"
[ -z "$out" ] || fail "lines written without a credential: [$out]"
case "$err" in *"PROXY_CLIENT_ID"*) ;; *) fail "no warning for a missing credential: [$err]" ;; esac

# 3. Malformed values never reach proxysql.cnf: a quote would end the string and add settings.
for pair in 'dpc-2-abc"; tls_verify = false; x="|'"$secret" "dpc-2-abc|dps_bad\"secret" "gwc-2-abc|$secret" "dpc-2-abc|"; do
  run "${pair%%|*}" "${pair#*|}" "https://h"
  [ -z "$out" ] || fail "malformed credential written: [$out]"
  case "$err" in *"$secret"*) fail "the secret was printed: $err" ;; esac
  [ -n "$err" ] || fail "no warning for a malformed credential (${pair%%|*})"
done

# 4. The function prints the secret only into what goes to proxysql.cnf (stdout), never to the
#    terminal (stderr) -- and the installer prints only the client id.
run "dpc-2-abc" "$secret" "https://h"
case "$err" in *"$secret"*) fail "the secret reached stderr" ;; esac
grep -q 'caller credential $PROXY_CLIENT_ID written to /etc/proxysql.cnf (secret not shown)' "$script" \
  || fail "the installer's status line changed; check it does not print the secret"

if [ "$fails" -ne 0 ]; then echo "$fails failure(s)"; exit 1; fi
echo ok
