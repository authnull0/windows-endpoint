#!/usr/bin/env bash
# Test for read_db_env in run_agent.sh: the db.env the installer is given is saved, not echoed,
# and reading stops at the empty line the prompt asks for.
#
#   bash agent/linux-build/tests/db_env_input_test.sh
#
# Runs only that function (extracted from the script), in a temporary directory. Exits non-zero
# on any failure.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../run_agent.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

fn="$(sed -n '/^read_db_env() {/,/^}/p' "$script")"
[ -n "$fn" ] || { echo "FAIL: read_db_env() not found in run_agent.sh"; exit 1; }

key="m461-test-key-9c2e"
# What a person pastes, then the empty line, then the answers to the prompts that follow.
input="ORG_ID=2
TENANT_ID=1
KEY=$key
MACHINE_KEY=DATAB1234

y
db-host-answer"

out="$(cd "$work" && printf '%s\n' "$input" | bash -c "$fn"'
read_db_env db.env
IFS= read -r next; echo "NEXT=$next"' 2>&1)"

# 1. The key is not echoed to the terminal (or the installer log that captures it).
case "$out" in *"$key"*) fail "the key was echoed: $out" ;; esac

# 2. The file holds exactly what was pasted, nothing after the empty line.
want="ORG_ID=2
TENANT_ID=1
KEY=$key
MACHINE_KEY=DATAB1234"
got="$(cat "$work/db.env" 2>/dev/null)"
[ "$got" = "$want" ] || fail "db.env is not what was pasted: [$got]"

# 3. Reading stopped at the empty line: the next prompt's answer is still unread.
case "$out" in *"NEXT=y"*) ;; *) fail "answers after the empty line were swallowed: $out" ;; esac

# 4. Only the owner can read it.
perm="$(stat -c %a "$work/db.env" 2>/dev/null)"
[ "$perm" = "600" ] || fail "db.env mode is $perm, want 600"

# 5. Running again replaces the file instead of appending to it.
(cd "$work" && printf 'ORG_ID=3\n\n' | bash -c "$fn"'
read_db_env db.env' >/dev/null 2>&1)
[ "$(cat "$work/db.env")" = "ORG_ID=3" ] || fail "a second run appended: [$(cat "$work/db.env")]"

if [ "$fails" -ne 0 ]; then echo "$fails failure(s)"; exit 1; fi
echo ok
