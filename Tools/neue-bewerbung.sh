#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
entrypoint="$script_dir/bewerbung.sh"

if [[ ! -x "$entrypoint" ]]; then
  printf 'Fehler: Einheitlicher Bash-Einstieg fehlt oder ist nicht ausfuehrbar: %s\n' "$entrypoint" >&2
  exit 1
fi

exec "$entrypoint" neu "$@"
