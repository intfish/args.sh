#!/usr/bin/env bash
# fail()/pass() helpers
set -u

ARGS_LIB="${ARGS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/args.sh}"
# shellcheck source=../args.sh
. "$ARGS_LIB"

__test_count=0
__test_failed=0

pass() {
    __test_count=$(( __test_count + 1 ))
    printf '  pass %s\n' "$1"
}

fail() {
    __test_count=$(( __test_count + 1 ))
    __test_failed=$(( __test_failed + 1 ))
    printf '  FAIL %s\n' "$1"
}

assert_eq() {
    if [[ "$2" == "$3" ]]; then
        pass "$1"
    else
        fail "$1 (got [$2] want [$3])"
    fi
}

assert_exit() { # expected_code expected_out... -> runs remaining args as cmd
    local expected=$1; shift
    local _out
    # shellcheck disable=SC2034
    _out=$( "$@" 2>&1 )
    local code=$?
    if [[ $code -ne $expected ]]; then
        fail "exit code $code, wanted $expected"
    else
        pass "exit code $code"
    fi
}

_end_test() {
    if [[ $__test_failed -ne 0 ]]; then
        printf 'test suite error: %d/%d assertions failed\n' "$__test_failed" "$__test_count"
        exit 1
    fi
    printf '%d assertions passed\n' "$__test_count"
    exit 0
}

trap _end_test EXIT
