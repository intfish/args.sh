#!/usr/bin/env bash
# shellcheck disable=SC2154 # variables assigned dynamically by args.sh
# nested sub-parsers, modeled after a real "command style" tool
set -u
. "$(dirname "${BASH_SOURCE[0]}")/testlib.sh"

out=$(bash -c '
. "$1"; shift # drop lib path
set_command "tool"
set_limit_args 1
set_completions "setup run clear status"
arg_pos command "" "command" required
args_parse "$@"
shift
declare command=$arg_command

setup() {
    args_reset
    set_command "tool setup"
    set_description "sets up"
    arg_pos module "" "module" optional
    args_parse "$@"
    printf "setup module=%s\n" "${arg_module:-}"
}

status() {
    args_reset
    set_command "tool status"
    args_parse "$@"
    printf "status\n"
}

case "$command" in
    setup) setup "$@" ;;
    status) status "$@" ;;
    *) echo "unknown command: $command"; exit 1 ;;
esac
' _ "$ARGS_LIB" setup some_module)
assert_eq "top-level command captured, subcommand parses its own positional" "$out" "setup module=some_module"

out=$(bash -c '
. "$1"; shift # drop lib path
set_limit_args 1
arg_pos command "" "command" required
args_parse "$@"
shift
run() {
    args_reset
    arg_bool -d "enable debug" optional opt_debug
    arg_pos tag "" "tag to run" required
    arg_pos version "" "only on version" optional
    args_parse "$@"
    printf "tag=%s debug=%s version=%s\n" "$arg_tag" "${opt_debug:-default}" "${arg_version:-}"
}
run "$@"
' _ "$ARGS_LIB" run -d my_tag)
assert_eq "sub-parser bool + required positional" "$out" "tag=my_tag debug=-d version="

out=$(bash -c '
. "$1"; shift # drop lib path
set_limit_args 1
arg_pos command "" "command" required
args_parse "$@"
shift
declare command=$arg_command
status() {
    args_reset
    args_parse "$@"
    printf "status\n"
}
clear() {
    args_reset
    args_parse "$@"
    printf "clear\n"
}
case "$command" in
    status) status "$@" ;;
    clear) clear "$@" ;;
    *) exit 1 ;;
esac
' _ "$ARGS_LIB" clear)
assert_eq "dispatch to second subcommand" "$out" "clear"

# args_reset clears internal parser state;
# a user variable from a prior parse is only overwritten when the argument is re-provided
out=$(bash -c '
. "$1"; shift # drop lib path
set_limit_args 1
arg_pos command "" "command" required
args_parse "$@"
shift
declare command=$arg_command
first() {
    args_reset
    arg_def --key "def" "k-v"
    args_parse --key value
    printf "%s " "$opt_key"
}
second() {
    args_reset
    arg_def --key "" "k-v"
    args_parse --key other
    printf "%s\n" "$opt_key"
}
first "$@"
second "$@"
' _ "$ARGS_LIB" any)
assert_eq "re-provided argument wins in sub-parser" "$out" "value other"

# unknown subcommand reports nothing extra, exits 1
out=$(bash -c '
. "$1"; shift # drop lib path
set_limit_args 1
arg_pos command "" "command" required
args_parse "$@"
shift
declare command=$arg_command
case "$command" in
    status) ;;
    clear) ;;
    *) echo "unknown command: $command"; exit 1 ;;
esac
' _ "$ARGS_LIB" bogus)
assert_eq "unknown subcommand" "$out" "unknown command: bogus"

# a string option consumes two tokens; __ARGS_CONSUMED lets the caller shift
# by the true token count instead of one per logical argument
out=$(bash -c '
. "$1"; shift # drop lib path
set_limit_args 1
arg_def --key "" "k-v"
args_parse "$@"
shift "$__ARGS_CONSUMED"
printf "remainder=[%s]\n" "$*"
' _ "$ARGS_LIB" --key val extra)
assert_eq "string option consumes its value token" "$out" "remainder=[extra]"
