# args.sh

Opinionated library for argument parsing for bash scripts.

## Usage

```sh
#!/usr/bin/env bash
SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_ROOT/args.sh"

set -e

set_description "does a thing"

arg_bool --verbose "enable verbose logging"
arg_def --key "default_value" "key-value arg"

arg_pos path . "path/to/someplace" required
arg_pos something "" "optional argument" optional

args_parse "$@"

echo "--verbose: $opt_verbose"
echo "--key:     $opt_key"
echo "path:      $arg_path"
echo "something: $arg_something"
```

Produces the following:

```sh
./test.sh -h
usage: ./test.sh [options] <path> [something]
    does a thing

    <path>          path/to/someplace
    [something]     optional argument
    --key <value>   key-value arg
    -L              list options for auto-complete
    --verbose       enable verbose logging
```

See [demo.sh](./demo.sh) for more

## API

### configuration

- `set_description "text"` - help text under the usage line
- `set_command "name"` - program name shown in usage (defaults to `$0`)
- `set_usage "text"` - replaces the auto-generated usage line
- `set_help_ps "text"` - appended below the options list
- `set_dump_args true` - debug: print the raw property table before parsing
- `set_completions "static text"` - replacement for the completion list
- `set_completions_flag "-L"` - the flag that triggers completions (default `-L`); accepts only option-like names, pass `""` to disable
- `set_limit_args n` - stop parsing after n arguments (sub-parser support)
  - `__ARGS_CONSUMED` holds the exact number of *tokens* consumed by the last `args_parse`; sub-parsers should `shift "$__ARGS_CONSUMED"` rather than `shift n`
- `set_min_args n` - fails with an error if fewer than n arguments were consumed
- `set_error_exit true|false` - when `false`, a parse error returns a non-zero status from the failing call instead of `exit`-ing
  - useful when sourcing `args.sh` from an interactive shell, where calling `exit` would kill the caller's shell
  - default is `true` (exit)
- `args_reset` - clears definitions and per-parser config (`set_limit_args`, `set_min_args`, help text), but preserves process-wide settings (`set_error_exit`, `set_completions`, `set_completions_flag`, `set_dump_args`)

### argument definition

- `arg_def "name" [default] [help] [type] [required] [var_name]`
- `arg_bool "name" [help] [required] [var_name]`
- `arg_pos "name" [default] [help] [required] [var_name]`
- `arg_multi "name" [help] [required] [var_name]` - repeatable flag, values are collected into an array

#### notes

- `required` - one of `required`, `optional` or `hidden`
- `var_name` - defaults to auto-generated from argument name, with non-`[A-Za-z0-9_]` characters mapped to `_`
- `-h` and `--help` are reserved for the builtin help action
- every argument name may be defined only once
- non-multi arguments may be given at most once; repeats are an error (use `arg_multi`)
- short flags must be passed as standalone tokens; combined short flags (`-abc`) and short-option value packing (`-ovalue`) are not supported

### parsing

- `args_parse "$@"` - parses arguments

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).

## Credits

This is based on work originally done by Yaacov Zamir here: [https://github.com/yaacov/argparse-sh](https://github.com/yaacov/argparse-sh).

Due to quite significant modifications and taste-based choices, I elected to fork it rather than open a PR.

## Development

- `./tests/run.sh` - run the test suite
- `./tests/lint.sh` - shellcheck (falls back to `bash -n`)
