#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
# set_error_exit false makes parse errors return instead of exit (interactive-shell safe)
set -u
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

# default behavior: parse error exits (status 1) rather than returning into the shell
if bash -c '. "$1"; args_parse --nope' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "default exit mode should exit non-zero"
else
    pass "default exit mode exits non-zero"
fi

# opt-in mode: same error must not kill the shell; args_parse returns 1 and the shell lives on
out=$(bash -c '
. "$1"
set_error_exit false
arg_bool --verbose ""
if args_parse --nope; then
    echo "args_parse returned 0"
else
    echo "args_parse returned $?"
fi
echo "shell still alive"
' _ "$ARGS_LIB" 2>/dev/null)
assert_eq "opt-in returns instead of exiting" "$out" "args_parse returned 1
shell still alive"

# error message is still printed to stderr
err=$(bash -c '. "$1"; set_error_exit false; args_parse --nope' _ "$ARGS_LIB" 2>&1 >/dev/null)
assert_eq "error message printed" "$err" '/!\ error: unknown option: --nope'

# definition-time errors also return instead of exiting
if bash -c '. "$1"; set_error_exit false; arg_bool --help ""' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "arg_bool --help should fail in opt-in mode"
else
    pass "definition error returns non-zero in opt-in mode"
fi

# -h/--help return 0 instead of exiting in opt-in mode
out=$(bash -c '. "$1"; set_error_exit false; arg_bool --verbose ""; args_parse --help; echo "alive"' _ "$ARGS_LIB" 2>/dev/null)
if [[ "$out" == *"alive" && "$out" == *"usage"* ]]; then
    pass "-h returns 0 in opt-in mode"
else
    fail "-h returns 0 in opt-in mode (got: $out)"
fi

# completions return 0 instead of exiting in opt-in mode
out=$(bash -c '. "$1"; set_error_exit false; arg_bool --verbose ""; args_parse -L; echo "alive"' _ "$ARGS_LIB" 2>/dev/null)
if [[ "$out" == *"alive" && "$out" == *"--verbose"* ]]; then
    pass "completions return 0 in opt-in mode"
else
    fail "completions return 0 in opt-in mode (got: $out)"
fi
