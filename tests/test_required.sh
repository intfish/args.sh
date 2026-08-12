#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
# required args and `--` passthrough
set -u
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

# -- separator: everything after -- is positional (including values starting with -)
out=$(bash -c '. "$1"; arg_pos p1 "" "first" required; args_parse -- -5 >/dev/null; echo "$arg_p1"' _ "$ARGS_LIB" 2>/dev/null)
assert_eq "passthrough value starting with dash" "$out" "-5"

# required check must NOT be fooled by the env var (seen-based)
if bash -c '. "$1"; export arg_pre=env; arg_pos pre "" "p" required; args_parse' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "env var should not satisfy required"
else
    pass "env var does not satisfy required"
fi

# with an actual argument, it must pass
out=$(bash -c '. "$1"; arg_pos pre "" "p" required; args_parse x >/dev/null; echo done' _ "$ARGS_LIB" 2>&1 | tail -1)
assert_eq "provided positional passes required" "$out" "done"

# required check must fail properly
if bash -c '. "$1"; arg_def --need "x" "need" string required; args_parse' _ "$ARGS_LIB" 2>/dev/null; then
    fail "missing required should exit 1"
else
    pass "missing required exits 1"
fi

# min args enforcement after parsing
if bash -c '. "$1"; set_min_args 2; arg_bool --verbose v; args_parse --verbose' _ "$ARGS_LIB" 2>/dev/null; then
    fail "min args should have failed"
else
    pass "min args fails when insufficient"
fi

# no args at all but min>0 shows help and exits non-zero
out=$(bash -c '. "$1"; set_min_args 1; arg_pos p "" "x" optional; args_parse' _ "$ARGS_LIB" 2>&1)
if [[ "$out" == usage:* ]]; then pass "shows usage"; else fail "shows usage ($out)"; fi
if [[ "$out" == *"[p]"* ]]; then pass "lists positional in usage"; else fail "lists positional in usage ($out)"; fi
