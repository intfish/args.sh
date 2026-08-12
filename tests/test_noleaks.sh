#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
# no global namespace leakage from library internals
set -u
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

out=$(bash -c '
  set -u
  . "$1"
  arg_bool --verbose "verbose"
  arg_def --key "def" "k-v"
  arg_pos path . "p" required
  args_parse --verbose --key v /x
  # after parse, these library-internal names must NOT exist here:
  python3 -c "print(\"unused\")" >/dev/null
  for n in positional_idx num_parsed key_var had_equals in_passthrough max_len len desc idx sorted opts; do
    case $- in *u*) : ;; esac
    if declare -p "$n" >/dev/null 2>&1; then
      printf "LEAK %s\n" "$n"
    fi
  done
  printf "done\n"' _ "$ARGS_LIB")
assert_eq "no leaks (got: $out)" "$out" "done"

# help path
out=$(bash -c '
  set -u
  . "$1"
  set_min_args 1
  arg_pos path . "p" required
  args_show_help >/dev/null
  if declare -p key >/dev/null 2>&1; then
    printf "LEAK key\n"
  fi
  printf "done\n"' _ "$ARGS_LIB")
assert_eq "no leaks from help (got: $out)" "$out" "done"

# reserved-name warning is emitted when user explicitly supplies colliding var
out=$(bash -c '. "$1"; arg_bool --path "x" optional PATH' _ "$ARGS_LIB" 2>&1 >/dev/null)
assert_eq "collision warning silenced" "$out" 'args.sh: warning: variable name "PATH" may collide with a bash special variable'

# and no warning when auto-generated
out=$(bash -c '. "$1"; arg_def --path "x" "p" string optional' _ "$ARGS_LIB" 2>&1 >/dev/null)
assert_eq "auto name does not warn" "$out" ""

# variable collisions
for v in INPUTRC GLOBIGNORE HISTIGNORE BASH_ENV; do
    out=$(bash -c ". \"\$1\"; arg_def --x \"\" \"\" string optional $v" _ "$ARGS_LIB" 2>&1 >/dev/null)
    assert_eq "$v warns" "$out" "args.sh: warning: variable name \"$v\" may collide with a bash special variable"
done

# newly added bash internals warn the same way
out=$(bash -c '. "$1"; arg_def --x "" "" string optional BASH_LINENO' _ "$ARGS_LIB" 2>&1 >/dev/null)
assert_eq "BASH_LINENO warns" "$out" 'args.sh: warning: variable name "BASH_LINENO" may collide with a bash special variable'

# parser globals are reserved too
for v in __ARGS_SEEN __ARGS_PROPERTIES __ARGS_POSITIONAL __ARGS_LIMIT; do
    if bash -c ". \"\$1\"; arg_def --x \"\" \"\" string optional $v" _ "$ARGS_LIB" >/dev/null 2>&1; then
        fail "var_name '$v' should be rejected"
    else
        pass "var_name '$v' rejected"
    fi
done

# redeclaring the same argument name is fine, but vars shared across two
# distinct argument names warn before values can clobber each other
out=$(bash -c '. "$1"; arg_def --foo-bar "" "x"; arg_def --foo_bar "" "y"' _ "$ARGS_LIB" 2>&1 >/dev/null)
if [[ "$out" == *'shares variable "opt_foo_bar"'* ]]; then pass "shared var warns"; else fail "shared var warns ($out)"; fi

# ...unless it's the same argument redefined (no false positive)
if bash -c '. "$1"; arg_def --again "" "x"; arg_def --again "" "y"' _ "$ARGS_LIB" >/dev/null 2>&1; then
    fail "redefining same arg should be rejected"
else
    pass "redefining same arg rejected"
fi

# dashless non-positional definitions warn: they can never be parsed
out=$(bash -c '. "$1"; arg_def deadpool "x" "d" string optional' _ "$ARGS_LIB" 2>&1 >/dev/null)
if [[ "$out" == *'has no leading dash and is not positional'* ]]; then pass "dead arg warns"; else fail "dead arg warns ($out)"; fi

# dashless positional is legitimate and silent
out=$(bash -c '. "$1"; arg_pos path "" "p" optional' _ "$ARGS_LIB" 2>&1 >/dev/null)
assert_eq "dashless positional does not warn" "$out" ""
