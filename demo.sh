#!/usr/bin/env bash
# shellcheck disable=SC2154 # args.sh assigns opt_* and arg_* variables
SCRIPT_ROOT="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_ROOT/args.sh"

set -e

# set_dump_args true # uncomment for debug

set_command "my-toolchain subcommand"
set_usage "[ custom usage options ] <path/to/someplace> [optional]"
set_description "does a thing"
set_help_ps "$(cat <<'EOF'

    Additional info at the end.
EOF
)"

# options
arg_bool --verbose "enable verbose logging"
arg_def --key "default_value" "key-value arg"

# short options and option variables
arg_bool -edge "edge version" optional
arg_bool -1   "version 1" optional
arg_bool -2   "version 2" optional
arg_bool -3   "version 3" optional

# multi-args
arg_multi --dir "search paths (repeat for multiple)" optional opt_dirs

# hidden options
arg_bool -3.5   "version 3.5" hidden

arg_pos path . "path/to/someplace" required
arg_pos something "" "optional argument" optional

args_parse "$@"

echo "=== arguments:"
echo "--verbose: $opt_verbose"
echo "--key:     $opt_key"
echo "dirs:      ${opt_dirs[*]}"
echo "path:      $arg_path"
echo "something: $arg_something"

coalesce() {
    for v in "$@"; do
        [[ -n $v ]] && { printf '%s\n' "$v"; return 0; }
    done
}
echo "version:  $(coalesce "$opt_edge" "$opt_1" "$opt_2" "$opt_3" "$opt_3_5")"
