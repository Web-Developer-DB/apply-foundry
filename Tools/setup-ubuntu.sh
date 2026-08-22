#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
printf '%s\n' 'Hinweis: setup-ubuntu.sh ist ein Kompatibilitätsalias für setup-linux.sh.' >&2
exec "$script_dir/setup-linux.sh" "$@"
