#!/usr/bin/env bash
SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)
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
arg_bool -edge "edge version" optional opt_version
arg_bool -1   "version 1" optional opt_version
arg_bool -2   "version 2" optional opt_version
arg_bool -3   "version 3" optional opt_version

# hidden options
arg_bool -3.5   "version 3.5" hidden opt_version

arg_pos path . "path/to/someplace" required
arg_pos something "" "optional argument" optional

parse_args "$@"

echo "--verbose: $opt_verbose"
echo "--key:     $opt_key"
echo "version:   $opt_version"
echo "path:      $arg_path"
echo "something: $arg_something"

