#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
# hyphenated arguments sanitized
set -u
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

arg_def --my-arg "def" "has a dash" string optional
args_parse --my-arg hello
assert_eq "hyphen value" "$opt_my_arg" "hello"

# undeclared option should exit 1 via args_die
if bash -c '. "$1"; arg_bool --verbose ""; args_parse --nope' _ "$ARGS_LIB" 2>/dev/null; then
    fail "unknown option should exit 1"
else
    pass "unknown option exits 1"
fi
