#!/bin/bash

# based on https://github.com/yaacov/argparse-sh
# license: MIT
# authors: intfish <info@int.fish>
#          Yaacov Zamir <kobi.zamir@gmail.com>

declare -A __ARGS_PROPERTIES
declare -a __ARGS_POSITIONAL

__ARGS_DUMP_ARGS=false
__ARGS_OPT_PREFIX="opt"
__ARGS_POS_PREFIX="arg"
__ARGS_COMPLETIONS=""
__ARGS_COMPLETIONS_FLAG="-L"

__ARGS_HELP_DESCRIPTION=""
__ARGS_HELP_COMMAND="$0"
__ARGS_HELP_USAGE=""
__ARGS_HELP_PS=""

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

set_completions_flag() {
    __ARGS_COMPLETIONS_FLAG="$1"
}

set_completions() {
    __ARGS_COMPLETIONS="$1"
}

# define a command-line argument
# usage: define_arg "arg_name" ["default"] ["help text"] ["type"] ["required"] ["var_name"]
define_arg() {
    local arg_name=$1
    __ARGS_PROPERTIES["$arg_name,default"]=${2:-""} # Default value
    __ARGS_PROPERTIES["$arg_name,help"]=${3:-""} # Help text
    __ARGS_PROPERTIES["$arg_name,type"]=${4:-"string"} # Type [ "string" | "bool" | "positional" | "hidden" ], default is "string".
    __ARGS_PROPERTIES["$arg_name,required"]=${5:-"optional"} # Required flag ["required" | "optional" | "hidden"], default is "optional"
    __ARGS_PROPERTIES["$arg_name,var"]=${6:-$(arg_to_var "$arg_name")} # Variable name (optional, auto-generated)

    if [[ "${__ARGS_PROPERTIES[$arg_name,type]}" == "positional" ]]; then
        __ARGS_POSITIONAL+=("$arg_name")
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
            echo "${__ARGS_OPT_PREFIX}_${arg#--}"
            ;;
        -*)
            echo "${__ARGS_OPT_PREFIX}_${arg#-}"
            ;;
        *)
            echo "${__ARGS_POS_PREFIX}_${arg}"
            ;;
    esac
}

get_var_name() {
    local arg="$1"
    if [[ -n "${__ARGS_PROPERTIES[$arg,var]}" ]]; then
        echo "${__ARGS_PROPERTIES[$arg,var]}"
    else
        echo "$(arg_to_var "$arg")"
    fi
}

# parse command-line arguments
# usage: parse_args "$@"
parse_args() {
    check_builtin "$@"

    if [ "$__ARGS_DUMP_ARGS" = true ]; then
        echo "----------- arguments -----------"
        for key in "${!__ARGS_PROPERTIES[@]}"; do
            echo "    ${key} = ${__ARGS_PROPERTIES[$key]}"
        done | sort
        echo "---------------------------------"
    fi

    positional_idx=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                break ;;
            -*|--*)
                key="$1"
                key_var=$(get_var_name "$key")
                if [[ -n "${__ARGS_PROPERTIES[$key,help]}" ]]; then
                    if [[ "${__ARGS_PROPERTIES[$key,type]}" == "bool" ]]; then
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
                if (( $positional_idx < "${#__ARGS_POSITIONAL[@]}" )); then
                    key="${__ARGS_POSITIONAL[$positional_idx]}"
                    key_var=$(get_var_name "$key")
                    declare -g "$key_var"="$1"
                    positional_idx=$(( positional_idx + 1 ))
                else
                    die "expected at most ${#__ARGS_POSITIONAL[@]} positional arguments"
                fi
                shift
                ;;
        esac
    done

    # Check for required arguments
    for arg in "${!__ARGS_PROPERTIES[@]}"; do
        arg_name="${arg%%,*}" # Extract argument name
        var_name=$(get_var_name "$arg_name")
        if [[ "${__ARGS_PROPERTIES[$arg_name,required]}" == "required" && -z "${!var_name}" ]]; then
            die "missing required argument: $arg_name"
        fi
    done

    # Set defaults for any unset arguments
    for arg in "${!__ARGS_PROPERTIES[@]}"; do
        arg_name="${arg%%,*}" # Extract argument name
        var_name=$(get_var_name "$arg_name")
        if [[ -z "${!var_name}" ]]; then
            declare -g "$var_name"="${__ARGS_PROPERTIES[$arg_name,default]}"
        fi
    done
}

# displays help
show_help() {
    if [[ -n "$__ARGS_HELP_USAGE" ]]; then
        echo -e "usage: ${__ARGS_HELP_COMMAND} ${__ARGS_HELP_USAGE}\n"
    else
        printf "usage: %s [options] " "$__ARGS_HELP_COMMAND"
        for arg_name in "${__ARGS_POSITIONAL[@]}"; do
            if [[ "${__ARGS_PROPERTIES[$arg_name,required]}" == "required" ]]; then
                arg_name="<${arg_name}>"
            else
                arg_name="[${arg_name}]"
            fi
            printf "%s " "$arg_name"
        done
        printf '\n\n'
    fi

    if [[ -n "$__ARGS_HELP_DESCRIPTION" ]]; then
        echo -e "    $__ARGS_HELP_DESCRIPTION\n"
    fi

    max_len=0
    for key in "${!__ARGS_PROPERTIES[@]}"; do
        arg_name="${key%%,*}"
        len="${#arg_name}"
        if [[ "${__ARGS_PROPERTIES[$arg_name,type]}" == "string" ]]; then
            len=$(( len + 8 )) # len(" <value>")
        fi
        max_len=$(( len > max_len ? len : max_len ))
    done
    max_len=$(( max_len + 3 )) # padding for <> and [] + 1

    for arg_name in "${__ARGS_POSITIONAL[@]}"; do
        desc="${__ARGS_PROPERTIES[$arg_name,help]}"
        if [[ "${__ARGS_PROPERTIES[$arg_name,required]}" == "required" ]]; then
            arg_name="<${arg_name}>"
        else
            arg_name="[${arg_name}]"
        fi
        printf "    %-*s%s\n" "$max_len" "$arg_name" "$desc"
    done

    for arg in "${!__ARGS_PROPERTIES[@]}"; do
        if [[ "${arg##*,}" != "help" ]]; then
            continue
        fi

        arg_name="${arg%%,*}"
        desc="${__ARGS_PROPERTIES[$arg]}"

        if [[ "${__ARGS_PROPERTIES[$arg_name,required]}" == "hidden" ]]; then
            continue
        fi

        if [[ "${__ARGS_PROPERTIES[$arg_name,type]}" == "bool" ]]; then
            printf "    %-*s%s\n" "$max_len" "$arg_name" "$desc"
        elif [[ "${__ARGS_PROPERTIES[$arg_name,type]}" == "positional" ]]; then
            continue
        else
            printf "    %-*s%s\n" "$max_len" "$arg_name <value>" "$desc"
        fi
    done | sort

    if [[ -n "$__ARGS_HELP_PS" ]]; then
        echo -e "$__ARGS_HELP_PS\n"
    fi
}

# checks for built-in options (help, completions)
# usage: check_builtin "$@"
check_builtin() {
    if [[ -z "${__ARGS_PROPERTIES["$__ARGS_COMPLETIONS_FLAG",help]}" ]]; then
        arg_bool "$__ARGS_COMPLETIONS_FLAG" "list options for auto-complete"
    fi

    for arg in "$@"; do
        case "$arg" in
            -h|--help)
                show_help; exit 0;
                ;;
            "$__ARGS_COMPLETIONS_FLAG")
                if [[ -n "$__ARGS_COMPLETIONS" ]]; then
                    echo "$__ARGS_COMPLETIONS"
                    exit 0
                fi

                opts=()
                for key in "${!__ARGS_PROPERTIES[@]}"; do
                    if [[ "${key##*,}" != "help" ]]; then
                        continue
                    fi
                    arg_name="${key%%,*}"
                    if [[ "$arg_name" == "$__ARGS_COMPLETIONS_FLAG" ]]; then
                        continue
                    fi
                    if [[ "${__ARGS_PROPERTIES[$arg_name,required]}" == "hidden" ]]; then
                        continue
                    fi
                    if [[ "${__ARGS_PROPERTIES[$arg_name,type]}" == "positional" ]]; then
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
