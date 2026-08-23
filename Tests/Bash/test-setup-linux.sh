#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
setup="$root/Tools/setup.py"
alias="$root/Tools/setup-linux.sh"
[[ -x "$setup" && -x "$alias" ]] || { echo 'Setup-Einstieg fehlt.' >&2; exit 1; }
bash -n "$alias" "$root/Tools/setup.sh" "$root/Tools/setup-ubuntu.sh"
python3 -m py_compile "$setup"

direct="$(python3 "$setup" --runtime --dry-run --format json)"
delegated="$("$alias" --runtime --dry-run --format json)"
DIRECT="$direct" DELEGATED="$delegated" python3 - <<'PY'
import json, os
direct, delegated = json.loads(os.environ['DIRECT']), json.loads(os.environ['DELEGATED'])
assert direct == delegated
assert direct['schemaVersion'] == 3
assert direct['kind'] == 'apply_foundry_setup_plan'
assert direct['coreRuntime']['language'] == 'python'
assert direct['coreRuntime']['minimumVersion'] == '3.11'
assert direct['packageManager'] in {'apt', 'dnf', 'yum', 'pacman', 'zypper'}
assert direct['dryRun'] is True
PY

python3 -m unittest discover -s "$root/Tests/Python" -p 'test_setup_linux.py'
printf '[OK] Plattformneutraler Python-Setupvertrag bestanden.\n'
