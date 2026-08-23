#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
alias="$root/Tools/setup-ubuntu.sh"
[[ -x "$alias" ]] || { echo 'Ubuntu-Alias fehlt.' >&2; exit 1; }
bash -n "$alias"
"$alias" --runtime --dry-run --format json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schemaVersion"] == 3 and d["coreRuntime"]["language"] == "python"'
printf '[OK] setup-ubuntu.sh delegiert an den gemeinsamen Python-Setupkern.\n'
