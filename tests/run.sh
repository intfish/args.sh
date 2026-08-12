#!/usr/bin/env bash
# tests are bash files in tests/ named test_*.sh
# each test sources tests/testlib.sh which provides pass/fail helpers
set -u

SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_ROOT/.."
export ARGS_LIB="$ROOT/args.sh"

out=$(mktemp)
trap 'rm -f "$out"' EXIT

failures=0
tests=0
failed_names=()

for t in "$SCRIPT_ROOT"/test_*.sh; do
    [ -e "$t" ] || continue
    tests=$(( tests + 1 ))
    if bash "$t" >"$out" 2>&1; then
        printf 'ok   %s\n' "$(basename "$t")"
    else
        printf 'FAIL %s\n' "$(basename "$t")"
        failed_names+=("$(basename "$t")")
        failures=$(( failures + 1 ))
        sed 's/^/      /' "$out" | tail -n 15
    fi
done

printf '\n%d tests, %d failures\n' "$tests" "$failures"
[ "$failures" -eq 0 ]
