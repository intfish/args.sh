#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
# multi flags, limit_args (sub-parser), dump_args, help_ps, hidden
set -u
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

# multi collects into array
out=$(bash -c '. "$1"; arg_multi --dir ""; args_parse --dir a --dir b; printf "%s|%s" "${opt_dir[0]}" "${opt_dir[1]}"' _ "$ARGS_LIB")
assert_eq "multi collects values" "$out" "a|b"

# multi with = syntax
out=$(bash -c '. "$1"; arg_multi --dir ""; args_parse --dir a --dir=b; printf "%s|%s" "${opt_dir[0]}" "${opt_dir[1]}"' _ "$ARGS_LIB")
assert_eq "multi with equals" "$out" "a|b"

# limit_args: subparse only consumes requested amount
out=$(bash -c '
. "$1"
set_limit_args 1
arg_bool --foo ""
arg_pos rest "" "rest" optional
args_parse --foo bar
echo "opt_foo=$opt_foo arg_rest=$arg_rest"
' _ "$ARGS_LIB")
assert_eq "limit stops parsing" "$out" "opt_foo=--foo arg_rest="

# dump args
out=$(bash -c '. "$1"; set_dump_args true; arg_def --k "v"; args_parse --k z' _ "$ARGS_LIB")
if [[ "$out" == *arguments* ]]; then pass "dump works"; else fail "dump works ($out)"; fi

# help_ps shown literally (no backslash interpretation)
out=$(bash -c '. "$1"; set_help_ps "a \\n b"; args_show_help' _ "$ARGS_LIB")
if [[ "$out" == *"a \\n b"* ]]; then pass "help_ps literal"; else fail "help_ps literal ($out)"; fi

# hidden option absent from help
out=$(bash -c '. "$1"; arg_bool --hopt "x" hidden; args_show_help' _ "$ARGS_LIB")
if [[ "$out" != *"--hopt"* ]]; then pass "hidden option not listed"; else fail "hidden (got: $out)"; fi
