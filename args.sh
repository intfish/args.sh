#!/bin/bash

# based on https://github.com/yaacov/argparse-sh
# license: MIT
# authors: intfish <info@int.fish>
#          Yaacov Zamir <kobi.zamir@gmail.com>

declare -A ARG_PROPERTIES
declare -a POSITIONAL_ARGS

OPT_DUMP_ARGS=false
OPT_PREFIX="opt"
OPT_POS_PREFIX="arg"
OPT_COMPLETIONS_FLAG="-L"

HELP_DESCRIPTION=""
HELP_COMMAND="$0"
HELP_USAGE=""
HELP_PS=""

set_description() {
    HELP_DESCRIPTION="$1"
}

set_command() {
    HELP_COMMAND="$1"
}

set_usage() {
    HELP_USAGE="$1"
}

set_help_ps() {
    HELP_PS="$1"
}

set_dump_args() {
    OPT_DUMP_ARGS="$1"
}

set_completions_flag() {
    OPT_COMPLETIONS_FLAG="$1"
}

# define a command-line argument
# usage: define_arg "arg_name" ["default"] ["help text"] ["type"] ["required"] ["var_name"]
define_arg() {
    local arg_name=$1
    ARG_PROPERTIES["$arg_name,default"]=${2:-""} # Default value
    ARG_PROPERTIES["$arg_name,help"]=${3:-""} # Help text
    ARG_PROPERTIES["$arg_name,type"]=${4:-"string"} # Type [ "string" | "bool" | "positional" | "hidden" ], default is "string".
    ARG_PROPERTIES["$arg_name,required"]=${5:-"optional"} # Required flag ["required" | "optional" | "hidden"], default is "optional"
    ARG_PROPERTIES["$arg_name,var"]=${6:-$(arg_to_var "$arg_name")} # Variable name (optional, auto-generated)

    if [[ "${ARG_PROPERTIES[$arg_name,type]}" == "positional" ]]; then
        POSITIONAL_ARGS+=("$arg_name")
    fi
}

arg_def() {
    define_arg "$@"
}

# define a bool flag
# usage: arg_bool "arg_name" ["help text"] ["required"]
arg_bool() {
    define_arg "$1" "" "${2:-""}" "bool" "${3:-"optional"}" "$4"
}

# define a positional argument
# usage: arg_pos "arg_name" ["defult"] ["help text"] ["required"]
arg_pos() {
    define_arg "$1" "$2" "$3" "positional" "${4:-"optional"}" "$5"
}

# display an error message and exit
# usage: die "message"
die() {
    echo -e "/!\\ error: $1\n"
    exit 1
}

# converts argument to bash variable name
arg_to_var() {
    local arg="$1"
    case $arg in
        --*)
            echo "${OPT_PREFIX}_${arg#--}"
            ;;
        -*)
            echo "${OPT_PREFIX}_${arg#-}"
            ;;
        *)
            echo "${OPT_POS_PREFIX}_${arg}"
            ;;
    esac
}

get_var_name() {
    local arg="$1"
    if [[ -n "${ARG_PROPERTIES[$arg,var]}" ]]; then
        echo "${ARG_PROPERTIES[$arg,var]}"
    else
        echo "$(arg_to_var "$arg")"
    fi
}

# parse command-line arguments
# usage: parse_args "$@"
parse_args() {
    check_builtin "$@"

    if [ "$OPT_DUMP_ARGS" = true ]; then
        echo "----------- arguments -----------"
        for key in "${!ARG_PROPERTIES[@]}"; do
            echo "    ${key} = ${ARG_PROPERTIES[$key]}"
        done | sort
        echo "---------------------------------"
    fi

    positional_idx=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -*|--*)
                key="$1"
                key_var=$(get_var_name "$key")
                if [[ -n "${ARG_PROPERTIES[$key,help]}" ]]; then
                    if [[ "${ARG_PROPERTIES[$key,type]}" == "bool" ]]; then
                        declare -g "$key_var"="$key"
                        shift # past the flag argument
                    else
                        [[ -z "$2" || "$2" == --* ]] && die "missing value for argument $key"
                        declare -g "$key_var"="$2"
                        shift # past argument
                        shift # past value
                    fi
                else
                    die "unknown option: $key"
                fi
                ;;
            *)
                if (( $positional_idx < "${#POSITIONAL_ARGS[@]}" )); then
                    key="${POSITIONAL_ARGS[$positional_idx]}"
                    key_var=$(get_var_name "$key")
                    declare -g "$key_var"="$1"
                    positional_idx=$(( positional_idx + 1 ))
                else
                    die "expected at most ${#POSITIONAL_ARGS[@]} positional arguments"
                fi
                shift
                ;;
        esac
    done

    # Check for required arguments
    for arg in "${!ARG_PROPERTIES[@]}"; do
        arg_name="${arg%%,*}" # Extract argument name
        var_name=$(get_var_name "$arg_name")
        if [[ "${ARG_PROPERTIES[$arg_name,required]}" == "required" && -z "${!var_name}" ]]; then
            die "missing required argument: $arg_name"
        fi
    done

    # Set defaults for any unset arguments
    for arg in "${!ARG_PROPERTIES[@]}"; do
        arg_name="${arg%%,*}" # Extract argument name
        var_name=$(get_var_name "$arg_name")
        if [[ -z "${!var_name}" ]]; then
            declare -g "$var_name"="${ARG_PROPERTIES[$arg_name,default]}"
        fi
    done
}

# displays help
show_help() {
    if [[ -n "$HELP_USAGE" ]]; then
        echo -e "usage: ${HELP_COMMAND} ${HELP_USAGE}\n"
    else
        printf "usage: %s [options] " "$HELP_COMMAND"
        for arg_name in "${POSITIONAL_ARGS[@]}"; do
            if [[ "${ARG_PROPERTIES[$arg_name,required]}" == "required" ]]; then
                arg_name="<${arg_name}>"
            else
                arg_name="[${arg_name}]"
            fi
            printf "%s " "$arg_name"
        done
        printf '\n\n'
    fi

    if [[ -n "$HELP_DESCRIPTION" ]]; then
        echo -e "    $HELP_DESCRIPTION\n"
    fi

    max_len=0
    for key in "${!ARG_PROPERTIES[@]}"; do
        arg_name="${key%%,*}"
        len="${#arg_name}"
        if [[ "${ARG_PROPERTIES[$arg_name,type]}" == "string" ]]; then
            len=$(( len + 8 )) # len(" <value>")
        fi
        max_len=$(( len > max_len ? len : max_len ))
    done
    max_len=$(( max_len + 3 )) # padding for <> and [] + 1

    for arg_name in "${POSITIONAL_ARGS[@]}"; do
        desc="${ARG_PROPERTIES[$arg_name,help]}"
        if [[ "${ARG_PROPERTIES[$arg_name,required]}" == "required" ]]; then
            arg_name="<${arg_name}>"
        else
            arg_name="[${arg_name}]"
        fi
        printf "    %-*s%s\n" "$max_len" "$arg_name" "$desc"
    done

    for arg in "${!ARG_PROPERTIES[@]}"; do
        if [[ "${arg##*,}" != "help" ]]; then
            continue
        fi

        arg_name="${arg%%,*}"
        desc="${ARG_PROPERTIES[$arg]}"

        if [[ "${ARG_PROPERTIES[$arg_name,required]}" == "hidden" ]]; then
            continue
        fi

        if [[ "${ARG_PROPERTIES[$arg_name,type]}" == "bool" ]]; then
            printf "    %-*s%s\n" "$max_len" "$arg_name" "$desc"
        elif [[ "${ARG_PROPERTIES[$arg_name,type]}" == "positional" ]]; then
            continue
        else
            printf "    %-*s%s\n" "$max_len" "$arg_name <value>" "$desc"
        fi
    done | sort

    if [[ -n "$HELP_PS" ]]; then
        echo -e "$HELP_PS\n"
    fi
}

# checks for built-in options (help, completions)
# usage: check_builtin "$@"
check_builtin() {
    if [[ -z "${ARG_PROPERTIES["$OPT_COMPLETIONS_FLAG",help]}" ]]; then
        arg_bool "$OPT_COMPLETIONS_FLAG" "list options for auto-complete"
    fi

    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                show_help; exit 0;
                ;;
            "$OPT_COMPLETIONS_FLAG")
                opts=()
                for key in "${!ARG_PROPERTIES[@]}"; do
                    if [[ "${key##*,}" != "help" ]]; then
                        continue
                    fi
                    arg_name="${key%%,*}"
                    if [[ "$arg_name" == "$OPT_COMPLETIONS_FLAG" ]]; then
                        continue
                    fi
                    if [[ "${ARG_PROPERTIES[$arg_name,required]}" == "hidden" ]]; then
                        continue
                    fi
                    if [[ "${ARG_PROPERTIES[$arg_name,type]}" == "positional" ]]; then
                        continue
                    fi
                    opts+=("$arg_name")
                done
                IFS=$'\n' sorted=($(sort <<<"${opts[*]}"))
                unset IFS
                echo "${sorted[@]}"
                exit 0
                ;;
        esac
    done
}
