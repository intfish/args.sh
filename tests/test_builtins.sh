#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
set -u
# shellcheck source=../tests/testlib.sh
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

out=$(bash -c '. "$1"; arg_def --name "" "n"; arg_bool --verbose ""; args_parse --name "-h" >/dev/null; echo "$opt_name"' _ "$ARGS_LIB") 
assert_eq "-h as option value is kept" "$out" "-h"

out=$(bash -c '. "$1"; arg_def --count "" "n"; args_parse --count -5 >/dev/null; echo "$opt_count"' _ "$ARGS_LIB")
assert_eq "single-dash numeric value accepted" "$out" "-5"

# -h in a genuine option position still shows help
out=$(bash -c '. "$1"; arg_pos p "" "x" optional; args_parse -h' _ "$ARGS_LIB" 2>&1)
if [[ "$out" == usage:* ]]; then pass "-h shows help"; else fail "-h shows help ($out)"; fi

# completion flag
out=$(bash -c '. "$1"; arg_def --zed "z"; arg_pos pp "" "x" optional; set_min_args 0; args_parse -L' _ "$ARGS_LIB")
assert_eq "completion lists options" "$out" "--zed"
# -L as a value of another option must not trigger completions
out=$(bash -c '. "$1"; arg_def --wop "" "w"; args_parse --wop -L; echo "$opt_wop"' _ "$ARGS_LIB")
assert_eq "-L as value kept" "$out" "-L"

# custom completion text honored
out=$(bash -c '. "$1"; set_completions "alpha beta"; args_parse -L' _ "$ARGS_LIB")
assert_eq "custom completions honored" "$out" "alpha beta"
