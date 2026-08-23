#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
alias_setup="$repo_root/Tools/setup-ubuntu.sh"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf '[FEHLER] %s\n' "$1" >&2; exit 1; }
[[ -x "$alias_setup" ]] || fail 'Ubuntu-Kompatibilitätsalias fehlt oder ist nicht ausführbar.'
bash -n "$alias_setup"

"$alias_setup" --runtime --dry-run --format json >"$test_root/report.json" 2>"$test_root/stderr"
rg -Fq 'Kompatibilitätsalias für setup-linux.sh' "$test_root/stderr" || fail 'Ubuntu-Alias kennzeichnet seine Delegation nicht.'
python3 - "$test_root/report.json" <<'PY'
import json
import pathlib
import sys

report = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["schemaVersion"] == 2
assert report["coreRuntime"]["language"] == "python"
assert report["dryRun"] is True
PY

printf '[OK] setup-ubuntu.sh delegiert unverändert an den Linux-Python-Bootstrap.\n'
