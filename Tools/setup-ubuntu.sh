#!/usr/bin/env bash

set -euo pipefail

script_source="${BASH_SOURCE[0]}"
if [[ "$script_source" == */* ]]; then script_parent="${script_source%/*}"; else script_parent=.; fi
script_dir="$(cd -- "$script_parent" && pwd -P)"
printf '%s\n' 'Hinweis: setup-ubuntu.sh ist ein Kompatibilitätsalias für setup-linux.sh.' >&2
exec "$script_dir/setup-linux.sh" "$@"
