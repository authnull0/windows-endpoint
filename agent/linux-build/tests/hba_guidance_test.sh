#!/usr/bin/env bash
# Test for print_hba_guidance in run_agent.sh (DB-MFA-HARDENING S1): the pg_hba.conf lines that let
# only this proxy log in as a managed role, with this machine's address on the route to the
# database, and the grants the agent needs to check them.
#
#   bash agent/linux-build/tests/hba_guidance_test.sh
#
# Runs only those functions (extracted from the script). Exits non-zero on any failure.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../run_agent.sh"
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

fns="$(sed -n '/^proxy_source_ip() {/,/^}/p; /^print_hba_guidance() {/,/^}/p' "$script")"
[ -n "$fns" ] || { echo "FAIL: functions not found in run_agent.sh"; exit 1; }

# 1. The address is this machine's source address on the route to the database.
out="$(bash -c "$fns"'
print_hba_guidance 127.0.0.1 db_agent')"
case "$out" in *"+authnull_managed  127.0.0.1/32  scram-sha-256"*) ;; *) fail "loopback route: $out" ;; esac
case "$out" in *"+authnull_managed  0.0.0.0/0  reject"*) ;; *) fail "no IPv4 reject line" ;; esac
case "$out" in *"+authnull_managed  ::/0  reject"*) ;; *) fail "no IPv6 reject line" ;; esac
case "$out" in *'GRANT SELECT ON pg_hba_file_rules TO "db_agent";'*) ;; *) fail "no grant for the agent's user" ;; esac
case "$out" in *'GRANT EXECUTE ON FUNCTION pg_hba_file_rules() TO "db_agent";'*) ;; *) fail "no function grant" ;; esac

# 2. A host name is resolved first.
out="$(bash -c "$fns"'
print_hba_guidance localhost db_agent')"
case "$out" in *"+authnull_managed  127.0.0.1/32"*|*"+authnull_managed  ::1/128"*) ;; *) fail "host name: $out" ;; esac

# 3. Unresolvable: a placeholder, not an empty address that would make a broken line.
out="$(bash -c "$fns"'
print_hba_guidance no-such-host.invalid db_agent')"
case "$out" in *"+authnull_managed  <proxy IP>  scram-sha-256"*) ;; *) fail "unresolvable: $out" ;; esac

if [ "$fails" -ne 0 ]; then echo "$fails failure(s)"; exit 1; fi
echo ok
