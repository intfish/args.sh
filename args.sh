#!/bin/bash

# based on https://github.com/yaacov/argparse-sh
# license: MIT
# authors: intfish <info@int.fish>
#          Yaacov Zamir <kobi.zamir@gmail.com>

# need bash >= 4.3
# shellcheck disable=SC2317 # exit is reached when run as a script
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )) || \
{ echo "args.sh requires bash >= 4.3" >&2; return 1 2>/dev/null || exit 1; }

# const internals
__ARGS_VALUE_SUFFIX=" <value>"

# names whose assignment may clash with bash internals or the current
# environment; set of keys, built programmatically (static list + live env)
declare -gA __ARGS_RESERVED=()
_args_reserved_init() {
    local __args_names=(
        BASHPID BASH_ARGV BASH_ARGV0 BASH_ARGC BASH_COMMAND BASH_LINENO
        BASH_REMATCH BASH_SOURCE BASH_SUBSHELL BASH_VERSION BASH_XTRACEFD
        BASHOPTS COLUMNS COMP_WORDBREAKS DIRSTACK EPOCHREALTIME EPOCHSECONDS
        EUID FUNCNAME GROUPS HISTCMD HISTSIZE HISTFILESIZE HOME HOSTNAME
        HOSTTYPE IFS LINENO MACHTYPE OLDPWD OPTARG OPTERR OPTIND OSTYPE PATH
        PIPESTATUS PPID PROMPT_COMMAND PS1 PS2 PS3 PS4 PWD RANDOM REPLY
        SECONDS SHELL SHELLOPTS SHLVL UID
        BASH_ENV BASH_COMPAT CDPATH ENV FIGNORE GLOBIGNORE HISTCONTROL
        HISTFILE HISTIGNORE HISTTIMEFORMAT INPUTRC
    )
    local __args_n
    for __args_n in "${__args_names[@]}"; do
        __ARGS_RESERVED[$__args_n]=1
    done
    while IFS= read -r __args_n; do
        __ARGS_RESERVED[$__args_n]=1
    done < <(compgen -v)
}
_args_reserved_init

# reset parser state (clears definitions, seen-flags and counters);
# also used for sub-parser support
# process-wide settings (set_error_exit, set_completions, set_completions_flag, set_dump_args) survive args_reset;
args_reset() {
    unset __ARGS_PROPERTIES
    unset __ARGS_POSITIONAL
    unset __ARGS_SEEN
    unset __ARGS_NAMES
    declare -gA __ARGS_PROPERTIES
    declare -ga __ARGS_POSITIONAL
    declare -gA __ARGS_SEEN
    declare -ga __ARGS_NAMES

    __ARGS_OPT_PREFIX="opt"
    __ARGS_POS_PREFIX="arg"
    __ARGS_LIMIT=0
    __ARGS_MIN=0
    __ARGS_CONSUMED=0

    __ARGS_HELP_DESCRIPTION=""
    __ARGS_HELP_COMMAND="$0"
    __ARGS_HELP_USAGE=""
    __ARGS_HELP_PS=""
}

# process-wide settings, initialized once and preserved across args_reset
__ARGS_DUMP_ARGS=false
__ARGS_ERROR_EXIT=true
__ARGS_COMPLETIONS=""
__ARGS_COMPLETIONS_FLAG="-L"

# initialize state
args_reset

set_description() {
    __ARGS_HELP_DESCRIPTION="$1"
}

set_command() {
    __ARGS_HELP_COMMAND="$1"
}

set_usage() {
    __ARGS_HELP_USAGE="$1"
}

set_help_ps() {
    __ARGS_HELP_PS="$1"
}

set_dump_args() {
    __ARGS_DUMP_ARGS="$1"
}

# usage: set_error_exit true|false (default true)
# when false, parse errors, -h/--help and completions return their status to the
# caller instead of exiting (interactive-shell safe; see _args_terminate)
set_error_exit() {
    __ARGS_ERROR_EXIT="$1"
}

set_completions_flag() {
    [[ "$1" == "-" || "$1" =~ ^--?[A-Za-z0-9][A-Za-z0-9_-]*$ || -z "$1" ]] \
        || args_die "set_completions_flag: expected an option-like name (or '' to disable)" || return 1
    __ARGS_COMPLETIONS_FLAG="$1"
}

set_completions() {
    __ARGS_COMPLETIONS="$1"
}

set_limit_args() {
    [[ "$1" =~ ^[0-9]+$ ]] || args_die "set_limit_args: expected a non-negative integer" || return 1
    __ARGS_LIMIT="$1"
}

set_min_args() {
    [[ "$1" =~ ^[0-9]+$ ]] || args_die "set_min_args: expected a non-negative integer" || return 1
    __ARGS_MIN="$1"
}

# usage: _args_terminate code
# script mode: exit with code
# interactive-safe mode (set_error_exit false): returns code so callers can unwind instead
_args_terminate() {
    if [[ "$__ARGS_ERROR_EXIT" == true || "${BASH_SOURCE[0]}" == "$0" ]]; then
        exit "$1"
    fi
    return "$1"
}

# display an error message on stderr and exit
# usage: args_die "message" [exit code]
args_die() {
    printf '/!\\ error: %s\n' "$1" >&2
    _args_terminate "${2:-1}"
}

# converts an argument name to a bash variable name in the caller's variable (ref)
# sanitizes anything that is not [A-Za-z0-9_] to "_"
# so that generated names are always valid bash identifiers
# usage: args_convert_var_name "arg_name" out_var  (nameref)
args_convert_var_name() {
    local -n __args_ref_out=$2
    local __args_arg=$1 __args_prefix __args_base
    if [[ "$__args_arg" == -* ]]; then
        __args_prefix=$__ARGS_OPT_PREFIX
        __args_base=$__args_arg
        while [[ "$__args_base" == -* ]]; do
            __args_base=${__args_base#-}
        done
    else
        __args_prefix=$__ARGS_POS_PREFIX
        __args_base=$__args_arg
    fi
    __args_base="${__args_base//[^A-Za-z0-9_]/_}"
    __args_ref_out="${__args_prefix}_${__args_base}"
}

# define a command-line argument
# usage: args_define "arg_name" ["default"] ["help text"] ["type"] ["required"] ["var_name"]
args_define() {
    local __args_arg_name=$1

    # commas not allowed due to our "key,property" schema
    case $__args_arg_name in
        *,*)
            args_die "argument '$__args_arg_name' contains a comma; it may not" || return 1
            ;;
    esac

    # arguments cannot be redefined; the existing registration is authoritative
    if [[ -n "${__ARGS_PROPERTIES[$__args_arg_name,type]+set}" ]]; then
        args_die "argument '$__args_arg_name' is already defined; arguments cannot be redefined" || return 1
    fi

    local __args_var_given=false
    [[ -n "${6:-}" ]] && __args_var_given=true
    local __args_var_name
    if $__args_var_given; then
        __args_var_name=$6
    else
        args_convert_var_name "$__args_arg_name" __args_var_name
    fi

    if [[ ! "$__args_var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        args_die "invalid variable name '$__args_var_name' for argument '$__args_arg_name' (must match ^[A-Za-z_][A-Za-z0-9_]*$)" || return 1
    fi

    # -h/--help are reserved for the builtin help action and cannot be overridden
    case $__args_arg_name in
        -h|--help)
            args_die "argument '$__args_arg_name' is reserved for builtin help (remove the definition to use builtin help)" || return 1
            ;;
    esac

    local __args_type=${4:-"string"} __args_required=${5:-"optional"}

    # validate enums
    case $__args_type in
        string|bool|positional|multi) ;;
        *) args_die "argument '$__args_arg_name': invalid type '$__args_type' (expected string|bool|positional|multi)" || return 1 ;;
    esac
    case $__args_required in
        required|optional|hidden) ;;
        *) args_die "argument '$__args_arg_name': invalid required flag '$__args_required' (expected required|optional|hidden)" || return 1 ;;
    esac

    # collisions
    case $__args_var_name in
        __args_*|__ARGS_*)
            args_die "variable name '$__args_var_name' for argument '$__args_arg_name' collides with a parser internal (__args_* / __ARGS_*)" || return 1
            ;;
    esac
    if [[ ${__ARGS_RESERVED[$__args_var_name]+set} == set ]]; then
        printf 'args.sh: warning: variable name "%s" may collide with a bash special variable\n' "$__args_var_name" >&2
    fi

    # an argument without a leading dash and not declared positional can never be set
    case $__args_arg_name in
        -*) ;;
        *)
            if [[ "$__args_type" != "positional" ]]; then
                printf 'args.sh: warning: argument "%s" (type %s) has no leading dash and is not positional; it can never be set\n' "$__args_arg_name" "$__args_type" >&2
            fi
            ;;
    esac

    # two arguments mapping to the same variable can clobber each other's values
    local __args_other
    for __args_other in "${__ARGS_NAMES[@]}"; do
        if [[ "$__args_other" != "$__args_arg_name" \
                && "${__ARGS_PROPERTIES[$__args_other,var]}" == "$__args_var_name" ]]; then
            printf 'args.sh: warning: argument "%s" shares variable "%s" with argument "%s"; values may clobber each other\n' \
                "$__args_arg_name" "$__args_var_name" "$__args_other" >&2
            break
        fi
    done

    __ARGS_PROPERTIES["$__args_arg_name,default"]=${2:-""} # default value
    __ARGS_PROPERTIES["$__args_arg_name,help"]=${3:-""} # help text
    __ARGS_PROPERTIES["$__args_arg_name,type"]=$__args_type # type [ "string" | "bool" | "positional" | "multi" ], default is "string".
    __ARGS_PROPERTIES["$__args_arg_name,required"]=$__args_required # required flag ["required" | "optional" | "hidden"], default is "optional"
    __ARGS_PROPERTIES["$__args_arg_name,var"]=$__args_var_name # variable name (optional, auto-generated)
    __ARGS_NAMES+=("$__args_arg_name")

    if [[ "$__args_type" == "positional" ]]; then
        __ARGS_POSITIONAL+=("$__args_arg_name")
    fi
    return 0
}

arg_def() {
    args_define "$@"
}

# define a bool flag
# usage: arg_bool "arg_name" ["help text"] ["required"] ["var_name"]
arg_bool() {
    args_define "$1" "" "${2:-""}" "bool" "${3:-"optional"}" "${4:-}"
}

# define a positional argument
# usage: arg_pos "arg_name" ["default"] ["help text"] ["required"] ["var_name"]
arg_pos() {
    args_define "$1" "${2:-}" "${3:-}" "positional" "${4:-"optional"}" "${5:-}"
}

# define a repeated flag (can be specified multiple times, values collected into array)
# usage: arg_multi "arg_name" ["help text"] ["required"] ["var_name"]
arg_multi() {
    args_define "$1" "" "${2:-""}" "multi" "${3:-"optional"}" "${4:-}"
}

# true if any option-like (non-positional, non-hidden) argument is defined or an
# enabled completions flag is listed, i.e. the option section is non-empty
_args_has_listed_options() {
    local __args_name
    for __args_name in "${__ARGS_NAMES[@]}"; do
        if [[ "${__ARGS_PROPERTIES[$__args_name,required]}" != "hidden" \
                && "${__ARGS_PROPERTIES[$__args_name,type]}" != "positional" ]]; then
            return 0
        fi
    done
    [[ -n "$__ARGS_COMPLETIONS_FLAG" \
        && -z "${__ARGS_PROPERTIES[$__ARGS_COMPLETIONS_FLAG,var]+set}" ]]
}

# displays help
args_show_help() {
    local __args_max_len=0 __args_len __args_name __args_desc __args_key
    local __args_required __args_type

    if [[ -n "$__ARGS_HELP_USAGE" ]]; then
        printf 'usage: %s %s\n\n' "$__ARGS_HELP_COMMAND" "$__ARGS_HELP_USAGE"
    else
        printf 'usage: %s' "$__ARGS_HELP_COMMAND"
        _args_has_listed_options && printf ' [options]'
        for __args_name in "${__ARGS_POSITIONAL[@]}"; do
            __args_required="${__ARGS_PROPERTIES[$__args_name,required]}"
            if [[ "$__args_required" == "hidden" ]]; then
                continue
            fi
            if [[ "$__args_required" == "required" ]]; then
                printf ' <%s>' "$__args_name"
            else
                printf ' [%s]' "$__args_name"
            fi
        done
        printf '\n\n'
    fi

    if [[ -n "$__ARGS_HELP_DESCRIPTION" ]]; then
        printf '    %s\n\n' "$__ARGS_HELP_DESCRIPTION"
    fi

    __args_max_len=0
    for __args_name in "${__ARGS_NAMES[@]}"; do
        __args_len="${#__args_name}"
        __args_type="${__ARGS_PROPERTIES[$__args_name,type]}"
        if [[ "$__args_type" == "string" || "$__args_type" == "multi" ]]; then
            __args_len=$(( __args_len + ${#__ARGS_VALUE_SUFFIX} ))
        fi
        if (( __args_len > __args_max_len )); then
            __args_max_len=$__args_len
        fi
    done
    __args_max_len=$(( __args_max_len + 3 )) # padding for <> and [] + 1

    for __args_name in "${__ARGS_POSITIONAL[@]}"; do
        __args_required="${__ARGS_PROPERTIES[$__args_name,required]}"
        __args_desc="${__ARGS_PROPERTIES[$__args_name,help]}"
        if [[ "$__args_required" == "hidden" ]]; then
            continue
        fi
        if [[ "$__args_required" == "required" ]]; then
            __args_name="<${__args_name}>"
        else
            __args_name="[${__args_name}]"
        fi
        printf '    %-*s%s\n' "$__args_max_len" "$__args_name" "$__args_desc"
    done

    {
        for __args_key in "${__ARGS_NAMES[@]}"; do
            __args_required="${__ARGS_PROPERTIES[$__args_key,required]}"
            __args_type="${__ARGS_PROPERTIES[$__args_key,type]}"
            __args_desc="${__ARGS_PROPERTIES[$__args_key,help]}"

            if [[ "$__args_required" == "hidden" ]]; then
                continue
            fi

            if [[ "$__args_type" == "bool" ]]; then
                printf '    %-*s%s\n' "$__args_max_len" "$__args_key" "$__args_desc"
            elif [[ "$__args_type" == "positional" ]]; then
                continue
            else
                printf '    %-*s%s\n' "$__args_max_len" "$__args_key${__ARGS_VALUE_SUFFIX}" "$__args_desc"
            fi
        done

        if [[ -n "$__ARGS_COMPLETIONS_FLAG" \
                && -z "${__ARGS_PROPERTIES[$__ARGS_COMPLETIONS_FLAG,var]+set}" ]]; then
            printf '    %-*s%s\n' "$__args_max_len" "$__ARGS_COMPLETIONS_FLAG" "list options for auto-complete"
        fi
    } | sort

    if [[ -n "$__ARGS_HELP_PS" ]]; then
        printf '%s\n\n' "$__ARGS_HELP_PS"
    fi
}

# when invoked with no arguments and min_args > 0, print help and exit (or return) non-zero
_args_show_help_if_empty() {
    if (( $1 == 0 && __ARGS_MIN > 0 )); then
        args_show_help
        _args_terminate 1 || return 1
    fi
    return 0
}

# print all defined argument properties when set_dump_args is enabled
_args_dump_args() {
    local __args_key
    if [[ "$__ARGS_DUMP_ARGS" == true ]]; then
        printf -- '----------- arguments -----------\n'
        for __args_key in "${!__ARGS_PROPERTIES[@]}"; do
            printf '    %s = %s\n' "$__args_key" "${__ARGS_PROPERTIES[$__args_key]}"
        done | sort
        printf -- '---------------------------------\n'
    fi
}

# stop parsing once the configured limit is reached (returns 0 when reached)
_args_break_if_limit() {
    local __args_parsed=$1
    (( __ARGS_LIMIT > 0 && __args_parsed >= __ARGS_LIMIT ))
}

# validate the stored variable name and assign value, marking the argument as seen
# non-multi arguments may be given at most once; repeats are an error
_args_set_arg_value() {
    local __args_key=$1 __args_value=$2 __args_key_var
    if [[ ${__ARGS_SEEN[$__args_key]+set} == set ]]; then
        args_die "option $__args_key specified more than once" || return 1
    fi
    __args_key_var="${__ARGS_PROPERTIES[$__args_key,var]}"
    if [[ ! "$__args_key_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        args_die "invalid variable name: '$__args_key_var'" || return 1
    fi
    declare -g "$__args_key_var"="$__args_value"
    __ARGS_SEEN[$__args_key]=1
}

# append value to a multi argument's array, initializing it first
_args_append_value() {
    local __args_key=$1 __args_value=$2 __args_key_var __args_ref
    __args_key_var="${__ARGS_PROPERTIES[$__args_key,var]}"
    if [[ ${__ARGS_SEEN[$__args_key]+set} != set ]]; then
        declare -g -a "$__args_key_var=()"
    fi
    declare -n __args_ref="$__args_key_var"
    __args_ref+=("$__args_value")
    __ARGS_SEEN[$__args_key]=1
}

# assign value to the next positional argument, advancing idx
# usage: _args_assign_positional value idx
_args_assign_positional() {
    local -n __args_idx=$2
    if (( __args_idx < ${#__ARGS_POSITIONAL[@]} )); then
        local __args_key=${__ARGS_POSITIONAL[$__args_idx]}
        _args_set_arg_value "$__args_key" "$1" || return 1
        __args_idx=$(( __args_idx + 1 ))
    else
        args_die "expected at most ${#__ARGS_POSITIONAL[@]} positional arguments" || return 1
    fi
}

# handle one option token; sets consumed (nameref) to the number of tokens used
# usage: _args_handle_option token next argc consumed
_args_handle_option() {
    local __args_token=$1 __args_next=$2 __args_argc=$3
    local -n __args_ref_consumed=$4
    local __args_key __args_value="" __args_had_equals=false __args_type

    __args_ref_consumed=1
    if [[ "$__args_token" == *=* ]]; then
        __args_key="${__args_token%%=*}"
        __args_value="${__args_token#*=}"
        __args_had_equals=true
    else
        __args_key="$__args_token"
    fi

    if [[ -z "${__ARGS_PROPERTIES[$__args_key,var]:-}" ]]; then
        args_die "unknown option: $__args_key" || return 1
    fi

    __args_type="${__ARGS_PROPERTIES[$__args_key,type]}"
    case $__args_type in
        bool)
            if [[ "$__args_had_equals" == true ]]; then
                args_die "option $__args_key does not take a value" || return 1
            fi
            _args_set_arg_value "$__args_key" "$__args_key" || return 1
            ;;
        multi|string)
            if [[ "$__args_had_equals" == false ]]; then
                if (( __args_argc < 2 )); then
                    args_die "missing value for argument $__args_key" || return 1
                fi
                __args_value="$__args_next"
                # shellcheck disable=SC2034 # __args_ref_consumed is a nameref
                __args_ref_consumed=2
            fi
            if [[ $__args_type == "multi" ]]; then
                _args_append_value "$__args_key" "$__args_value" || return 1
            else
                _args_set_arg_value "$__args_key" "$__args_value" || return 1
            fi
            ;;
        *)
            args_die "internal error: unknown type '$__args_type' for argument $__args_key" || return 1
            ;;
    esac
}

# print auto-complete suggestions for non-positional, non-hidden options
_args_print_completions() {
    local __args_opts=() __args_name
    if [[ -n "$__ARGS_COMPLETIONS" ]]; then
        printf '%s\n' "$__ARGS_COMPLETIONS"
        return 0
    fi
    for __args_name in "${__ARGS_NAMES[@]}"; do
        if [[ "${__ARGS_PROPERTIES[$__args_name,required]}" == "hidden" ]]; then
            continue
        fi
        if [[ "${__ARGS_PROPERTIES[$__args_name,type]}" == "positional" ]]; then
            continue
        fi
        __args_opts+=("$__args_name")
    done
    if (( ${#__args_opts[@]} )); then
        printf '%s\n' "${__args_opts[@]}" | sort
    fi
}

# fail if any required argument was not provided
_args_check_required() {
    local __args_name
    for __args_name in "${__ARGS_NAMES[@]}"; do
        if [[ "${__ARGS_PROPERTIES[$__args_name,required]}" == "required" && ${__ARGS_SEEN[$__args_name]+set} != set ]]; then
            args_die "missing required argument: $__args_name" || return 1
        fi
    done
}

# fail if fewer than the configured minimum of arguments was parsed
# num_parsed counts logical arguments (one per option, regardless of spellings like "--key value" vs "--key=value");
# do not conflate it with token counts
_args_check_min_args() {
    local __args_parsed=$1
    if (( __ARGS_MIN > 0 && __args_parsed < __ARGS_MIN )); then
        args_die "expected at least $__ARGS_MIN argument(s), got $__args_parsed" || return 1
    fi
}

# set defaults for any argument that was never provided
_args_set_defaults() {
    local __args_name __args_var_name
    for __args_name in "${__ARGS_NAMES[@]}"; do
        __args_var_name="${__ARGS_PROPERTIES[$__args_name,var]}"
        if [[ ${__ARGS_SEEN[$__args_name]+set} != set ]]; then
            if [[ "${__ARGS_PROPERTIES[$__args_name,type]}" == "multi" ]]; then
                declare -g -a "$__args_var_name=()"
            else
                declare -g "$__args_var_name"="${__ARGS_PROPERTIES[$__args_name,default]}"
            fi
        fi
    done
}

# true if the token should be dispatched as an option rather than a positional;
# a lone "-" only counts as an option if "-" was registered as a property
# usage: _args_is_option token
_args_is_option() {
    [[ "$1" == -* && ( "$1" != "-" || -n "${__ARGS_PROPERTIES[-,var]:-}" ) ]]
}

_args_consume() {
    __ARGS_CONSUMED=$(( __ARGS_CONSUMED + $1 ))
}

# parse command-line arguments
# usage: args_parse "$@"
args_parse() {
    local __args_positional_idx=0 __args_num_parsed=0 __args_in_passthrough=false __args_consumed

    __ARGS_CONSUMED=0

    _args_show_help_if_empty "$#" || return 1
    _args_dump_args

    while (( $# > 0 )); do
        if [[ "$1" == "--" && $__args_in_passthrough == false ]]; then
            __args_in_passthrough=true
            shift
            _args_consume 1
            continue
        fi

        if [[ $__args_in_passthrough == true ]]; then
            _args_assign_positional "$1" __args_positional_idx || return 1
            __args_num_parsed=$(( __args_num_parsed + 1 ))
            shift
            _args_consume 1
            _args_break_if_limit "$__args_num_parsed" && break
            continue
        fi

        if [[ -n "$__ARGS_COMPLETIONS_FLAG" && "$1" == "$__ARGS_COMPLETIONS_FLAG" \
                && -z "${__ARGS_PROPERTIES[$__ARGS_COMPLETIONS_FLAG,var]+set}" ]]; then
            _args_print_completions
            _args_consume 1
            _args_terminate 0
            return 0
        fi

        case "$1" in
            -h|--help|-h=*|--help=*)
                args_show_help
                _args_consume 1
                _args_terminate 0
                return 0
                ;;
        esac

        # single dispatch: every remaining token is either an option or a positional
        __args_consumed=1
        if _args_is_option "$1"; then
            _args_handle_option "$1" "${2:-}" "$#" __args_consumed || return 1
        else
            _args_assign_positional "$1" __args_positional_idx || return 1
        fi
        shift "$__args_consumed"
        _args_consume "$__args_consumed"
        __args_num_parsed=$(( __args_num_parsed + 1 ))
        _args_break_if_limit "$__args_num_parsed" && break
    done

    _args_check_required || return 1
    _args_check_min_args "$__args_num_parsed" || return 1
    _args_set_defaults
}

# backwards compat
parse_args() {
    args_parse "$@"
}
