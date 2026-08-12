#!/usr/bin/env bash
# run from repo root (.shellcheckrc)
# requires shellcheck, but falls back to bash -n if shellcheck is missing
set -u
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_ROOT/.." && pwd)"
work=0

check() {
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck -x "$@"
    else
        for f in "$@"; do bash -n "$f" || return 1; done
        printf 'shellcheck not installed; bash -n only\n'
    fi
}

check "$ROOT/args.sh" "$ROOT/demo.sh" "$SCRIPT_ROOT"/test_*.sh
work=$?
[ "$work" -eq 0 ] && echo "lint ok"
exit $work
