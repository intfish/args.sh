#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
# regression tests
set -u
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

# --bool=value must be rejected
if bash -c '. "$1"; arg_bool --v "x"; args_parse --v=oops' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "bool accepts =value"
else
    pass "bool rejects =value"
fi

# multi default is an empty array, not a scalar
out=$(bash -c '. "$1"; arg_multi --d "x"; args_parse; declare -p opt_d' _ "$ARGS_LIB")
assert_eq "multi default is array" "$out" "declare -a opt_d=()"

# user-defined -L is not clobbered and parses normally
out=$(bash -c '. "$1"; arg_def -L "" "l"; args_parse -L val; echo "${opt_L:-}"' _ "$ARGS_LIB")
assert_eq "user -L parsed" "$out" "val"

out=$(bash -c '. "$1"; arg_bool -L "l"; args_parse -L; echo "${opt_L:-}"' _ "$ARGS_LIB")
assert_eq "user -L bool parsed" "$out" "-L"

# auto-registered completions flag still works when user has not defined it
out=$(bash -c '. "$1"; arg_def --zed "z"; args_parse -L' _ "$ARGS_LIB")
assert_eq "builtin completions flag still works" "$out" "--zed"

# completions work on a second parse
out=$(bash -c '. "$1"; set_completions_flag --completions; arg_bool --x "x"; args_parse --x; args_parse --completions' _ "$ARGS_LIB")
assert_eq "completions on repeat parse" "$out" "--x"

# flag must be option-like
out=$(bash -c '. "$1"; set_completions_flag "list"' _ "$ARGS_LIB" 2>&1)
if [[ "$out" == *"set_completions_flag: expected"* ]]; then pass "set_completions_flag validates"; else fail "set_completions_flag validates ($out)"; fi

# empty flag disables completions entirely (no option is reserved)
if bash -c '. "$1"; set_completions_flag ""; arg_def --x ""; args_parse -L' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "empty flag should disable completions"
else
    pass "empty flag disables completions"
fi

# empty positional arg is not swallowed by the (disabled) completions branch
out=$(bash -c '. "$1"; set_completions_flag ""; arg_pos name; args_parse ""; echo "${arg_name:+set}"' _ "$ARGS_LIB")
assert_eq "disabled flag rejects empty arg" "$out" ""

out=$(bash -c '. "$1"; set_completions_flag ""; arg_pos name; args_parse ""; echo "${arg_name-unset}"' _ "$ARGS_LIB")
assert_eq "disabled flag assigns empty positional" "$out" ""

# arg_pos with no args does not trip set -u
out=$(bash -c 'set -u; . "$1"; arg_pos p; args_parse; echo "ok"' _ "$ARGS_LIB" 2>&1 | tail -1)
assert_eq "arg_pos under set -u" "$out" "ok"

# arithmetic injection is validated
out=$(bash -c '. "$1"; set_min_args "a[\$(echo INJECTED >&2)]"' _ "$ARGS_LIB" 2>&1)
if [[ "$out" == *"set_min_args: expected"* ]]; then pass "set_min_args validates"; else fail "set_min_args validates ($out)"; fi

out=$(bash -c '. "$1"; set_limit_args "a[\$(echo INJECTED >&2)]"' _ "$ARGS_LIB" 2>&1)
if [[ "$out" == *"set_limit_args: expected"* ]]; then pass "set_limit_args validates"; else fail "set_limit_args validates ($out)"; fi

# enum validation: typos in type/required are rejected eagerly
out=$(bash -c '. "$1"; arg_def --k "d" "h" string requred' _ "$ARGS_LIB" 2>&1)
if [[ "$out" == *"invalid required flag 'requred'"* ]]; then pass "typo in required flag rejects"; else fail "typo in required flag rejects ($out)"; fi

out=$(bash -c '. "$1"; arg_def --k "d" "h" STRING optional' _ "$ARGS_LIB" 2>&1)
if [[ "$out" == *"invalid type 'STRING'"* ]]; then pass "typo in type rejects"; else fail "typo in type rejects ($out)"; fi

out=$(bash -c '. "$1"; arg_pos p "" "h" positional' _ "$ARGS_LIB" 2>&1)
if [[ "$out" == *"invalid required flag 'positional'"* ]]; then pass "positional as required flag rejects"; else fail "positional as required flag rejects ($out)"; fi

# num_parsed counts one per logical option (consumed used only for shift)
out=$(bash -c '. "$1"; set_limit_args 2; arg_def --k "v"; arg_pos rest "" "r" optional; args_parse --k val extra; echo "rest=${arg_rest:-unset}"' _ "$ARGS_LIB")
assert_eq "logical counting" "$out" "rest=extra"

# duplicate positional registration (redefinition) is rejected outright
if bash -c '. "$1"; arg_pos a ""; arg_pos b ""; arg_pos a ""; args_parse x y z' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "redefining a positional should be rejected"
else
    pass "redefining a positional is rejected"
fi

# redefining a positional into another type is rejected too (same name)
if bash -c '. "$1"; arg_pos p "" "x" optional; arg_def p "v" "y" string optional' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "redefining positional to option should be rejected"
else
    pass "redefining positional to option rejected"
fi

# help-on-empty invocation exits non-zero
out=$(bash -c '. "$1"; set_min_args 1; arg_pos p "" "x" optional; args_parse' _ "$ARGS_LIB" 2>&1)
if bash -c '. "$1"; set_min_args 1; arg_pos p "" "x" optional; args_parse' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "help-on-empty should exit non-zero"
else
    pass "help-on-empty exits non-zero"
fi
if [[ "$out" == usage:* ]]; then pass "help-on-empty shows usage"; else fail "help-on-empty shows usage ($out)"; fi

# environment variables do not suppress defaults
out=$(bash -c '. "$1"; arg_def --k "def"; export opt_k=env; args_parse; echo "$opt_k"' _ "$ARGS_LIB")
assert_eq "env does not suppress default" "$out" "def"

# multi starts fresh even with an inherited env var
out=$(bash -c '. "$1"; arg_multi --m ""; export opt_m=env; args_parse --m a --m b; echo "${opt_m[@]}"' _ "$ARGS_LIB")
assert_eq "multi ignores inherited env" "$out" "a b"

# parser internals renamed to __args_*; common names are now fine
out=$(bash -c '. "$1"; arg_def --x "d" "h" string optional ref; args_parse --x v >/dev/null; echo "$ref"' _ "$ARGS_LIB")
assert_eq "ref allowed as var_name" "$out" "v"

out=$(bash -c '. "$1"; arg_def --x "d" "h" string optional key_var; args_parse --x val >/dev/null; echo "$key_var"' _ "$ARGS_LIB")
assert_eq "key_var allowed as var_name" "$out" "val"

# names with the __args_ prefix are rejected
for v in __args_key __args_idx __args_ref __args_token; do
    if bash -c ". \"\$1\"; arg_def --x \"d\" \"h\" string optional $v" _ "$ARGS_LIB" >/dev/null 2>&1; then
        fail "var_name '$v' should be rejected"
    else
        pass "var_name '$v' rejected"
    fi
done

# generic positional whose auto-generated name used to collide with an internal variable
out=$(bash -c '. "$1"; arg_pos name; args_parse bob; echo "$arg_name"' _ "$ARGS_LIB")
assert_eq "arg_pos name works" "$out" "bob"

# completions with no options prints nothing, exits 0
out=$(bash -c '. "$1"; args_parse -L' _ "$ARGS_LIB")
assert_eq "empty completions omit blank line" "$out" ""

# usage line has no trailing space before newline
out=$(bash -c '. "$1"; args_show_help' _ "$ARGS_LIB" | head -1)
assert_eq "usage no trailing space" "$out" "usage: _ [options]"

# usage omits [options] when nothing option-like is listed
out=$(bash -c '. "$1"; set_completions_flag ""; args_show_help' _ "$ARGS_LIB" | head -1)
assert_eq "usage omits options when none" "$out" "usage: _"

out=$(bash -c '. "$1"; set_completions_flag ""; arg_pos p "" "x" optional; args_show_help' _ "$ARGS_LIB" | head -1)
assert_eq "usage omits options when only positionals" "$out" "usage: _ [p]"

# but keeps [options] once an option is defined
out=$(bash -c '. "$1"; set_completions_flag ""; arg_pos p "" "x" optional; arg_bool --v ""; args_show_help' _ "$ARGS_LIB" | head -1)
assert_eq "usage keeps options when one exists" "$out" "usage: _ [options] [p]"

# args_reset preserves process-wide settings
out=$(bash -c '
. "$1"
set_error_exit false
set_completions_flag --completions
arg_pos cmd "" "c" optional
args_parse cmd
shift
args_reset
printf "error_exit=%s flag=%s\n" "$__ARGS_ERROR_EXIT" "$__ARGS_COMPLETIONS_FLAG"' _ "$ARGS_LIB")
assert_eq "args_reset preserves settings" "$out" "error_exit=false flag=--completions"

# opt-out mode survives args_reset
out=$(bash -c '
. "$1"
set_error_exit false
arg_bool --v ""
args_reset
arg_bool --v2 ""
if args_parse --nope; then
    echo "args_parse returned 0"
else
    echo "args_parse returned $?"
fi
echo alive' _ "$ARGS_LIB" 2>/dev/null)
assert_eq "opt-out survives args_reset" "$out" "args_parse returned 1
alive"

# lone "-" is accepted as the completions flag
out=$(bash -c '. "$1"; set_completions_flag -; arg_bool --x ""; args_parse -' _ "$ARGS_LIB")
assert_eq "dash completions flag works" "$out" "--x"

out=$(bash -c '. "$1"; set_error_exit true; set_completions_flag -; args_parse --nope' _ "$ARGS_LIB" 2>&1)
assert_eq "dash flag still allows errors" "$out" '/!\ error: unknown option: --nope'

# a lone - is treated as positional (stdin convention)
out=$(bash -c '. "$1"; arg_pos stdin_file "" "?" optional; args_parse -; echo "$arg_stdin_file"' _ "$ARGS_LIB")
assert_eq "lone - treated positional" "$out" "-"

# -h/--help are reserved and rejected when defined as arguments
for flag in -h --help; do
    out=$(bash -c ". \"\$1\"; arg_def $flag \"\" \"custom\"" _ "$ARGS_LIB" 2>&1)
    if [[ "$out" == *"reserved for builtin help"* ]]; then
        pass "arg_def $flag rejected as reserved"
    else
        fail "arg_def $flag should be rejected ($out)"
    fi
done

# --help=x is still help, not an unknown-option error
out=$(bash -c '. "$1"; arg_pos p "" "x" optional; args_parse --help=x' _ "$ARGS_LIB" 2>&1 | head -1)
assert_eq "--help=x shows usage" "$out" "usage: _ [options] [p]"

# -h=x and --help= are also treated as help
out=$(bash -c '. "$1"; args_parse -h=x' _ "$ARGS_LIB" 2>&1 | head -1)
assert_eq "-h=x shows usage" "$out" "usage: _ [options]"

out=$(bash -c '. "$1"; args_parse --help=' _ "$ARGS_LIB" 2>&1 | head -1)
assert_eq "--help= shows usage" "$out" "usage: _ [options]"

# duplicate non-multi options raise an error instead of silently last-wins
out=$(bash -c '. "$1"; arg_def --x "d" "h"; args_parse --x a --x b' _ "$ARGS_LIB" 2>&1 >/dev/null)
assert_eq "duplicate string option errors" "$out" '/!\ error: option --x specified more than once'

if bash -c '. "$1"; arg_def --x "d" "h"; args_parse --x a --x b' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "duplicate string option should fail"
else
    pass "duplicate string option fails"
fi

if bash -c '. "$1"; arg_bool --verbose ""; args_parse --verbose --verbose' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "duplicate bool option should fail"
else
    pass "duplicate bool option fails"
fi

# multi still accepts repeats, and positional defaults are unaffected
out=$(bash -c '. "$1"; arg_multi --dir ""; args_parse --dir a --dir b; printf "%s|%s" "${opt_dir[0]}" "${opt_dir[1]}"' _ "$ARGS_LIB")
assert_eq "multi still allows repeats" "$out" "a|b"

out=$(bash -c '. "$1"; arg_pos p "" "x" optional; args_parse v >/dev/null; echo "$arg_p"' _ "$ARGS_LIB")
assert_eq "positional unaffected" "$out" "v"
