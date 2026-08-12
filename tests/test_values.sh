#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
# --key=value syntax and explicit empty values
set -u
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

arg_def --key "default" "key-value arg" string optional
arg_def --empty "fallback" "may be empty" string optional
arg_def --req "" "required, may be empty" string required

args_parse --key=value --empty= --req=
assert_eq "equals-syntax value" "$opt_key" "value"
assert_eq "explicit empty value wins over default" "$opt_empty" ""
assert_eq "explicit empty satisfies required" "$opt_req" ""

# positional arguments still work
args_reset
out=$(bash -c '. "$1"; arg_pos pos "" "p" optional; args_parse x; echo "$arg_pos"' _ "$ARGS_LIB")
assert_eq "positional" "$out" "x"
