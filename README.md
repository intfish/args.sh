# args.sh

Opinionated library for argument parsing for bash scripts.

## Usage

```sh
#!/usr/bin/env bash
SCRIPT_ROOT=$(cd "$(dirname "$0")"; pwd)
. "$SCRIPT_ROOT/lib/args.sh"

set -e

set_description "does a thing"

arg_bool --verbose "enable verbose logging"
arg_def --key "default_value" "key-value arg"

arg_pos path . "path/to/someplace" required
arg_pos something "" "optional argument" optional

parse_args "$@"

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


## License

This project is licensed under the [MIT License](https://github.com/licenses/MIT).


## Credits

This is based on work originally done by Yaacov Zamir here: https://github.com/yaacov/argparse-sh
Due to quite significant modifications and taste-based choices I elected to fork it rather than open a PR.
