#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
shell_setup="$repo_root/Tools/setup-linux.sh"
python_setup="$repo_root/Tools/setup-linux.py"
manifest="$repo_root/Tools/Linux-dependencies.json"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT

fail() { printf '[FEHLER] %s\n' "$1" >&2; exit 1; }
assert_exit() {
  local expected="$1"
  shift
  set +e
  "$@" >"$test_root/out" 2>"$test_root/err"
  local code=$?
  set -e
  [[ "$code" -eq "$expected" ]] || {
    sed 's/^/  stdout: /' "$test_root/out" >&2
    sed 's/^/  stderr: /' "$test_root/err" >&2
    fail "Exitcode $expected erwartet, $code erhalten."
  }
}

[[ -x "$shell_setup" && -x "$python_setup" ]] || fail 'Linux-Setup-Einstiege fehlen oder sind nicht ausführbar.'
[[ -r "$manifest" ]] || fail 'Versioniertes Linux-Abhängigkeitsmanifest fehlt.'
bash -n "$shell_setup" "$repo_root/Tools/setup-ubuntu.sh"
python3 -B -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), feature_version=(3, 9))' "$python_setup"

help_output="$("$shell_setup" --help)"
[[ "$help_output" == *'System-Python 3.9'* && "$help_output" == *'--browser {chromium}'* && "$help_output" == *'--format {text,json}'* ]] || fail 'Linux-Setup-Hilfe ist unvollständig.'
assert_exit 2 "$shell_setup" --browser firefox
assert_exit 2 "$shell_setup" --format yaml --runtime --dry-run
assert_exit 0 "$shell_setup"

python_json="$(python3 "$python_setup" --runtime --dry-run --format json)"
shell_json="$("$shell_setup" --runtime --dry-run --format json)"
PYTHON_JSON="$python_json" SHELL_JSON="$shell_json" python3 - <<'PY'
import json
import os

direct = json.loads(os.environ["PYTHON_JSON"])
delegated = json.loads(os.environ["SHELL_JSON"])
assert direct["schemaVersion"] == 2
assert direct["kind"] == "linux_setup_plan"
assert direct["coreRuntime"]["platform"] == "linux"
assert direct["coreRuntime"]["language"] == "python"
assert direct["coreRuntime"]["minimumVersion"] == "3.9"
assert "--runtime --dry-run --format json" in direct["coreRuntime"]["setupCommand"]
assert direct["packageManager"] in {"apt", "dnf", "yum", "pacman", "zypper"}
assert direct["dryRun"] is True
assert direct == delegated
PY

# Der minimale Bash-Sonderpfad muss auch ohne vorhandenes Python einen
# maschinenlesbaren, nicht mutierenden Runtime-Plan liefern. Für dieses
# synthetische Fixture wird ausschließlich die frühe Runtime-Erkennung
# deaktiviert; es wird kein Paketbefehl ausgeführt.
bootstrap_fixture="$test_root/setup-linux-without-python.sh"
python3 - "$shell_setup" "$bootstrap_fixture" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
needle = 'if system_python="$(find_system_python)"; then\n'
if source.count(needle) != 1:
    raise SystemExit("Runtime-Erkennungsgrenze im Bash-Bootstrap fehlt")
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, "if false; then\n", 1), encoding="utf-8")
PY
chmod +x "$bootstrap_fixture"
bootstrap_json="$("$bootstrap_fixture" --all --dry-run --format json)"
BOOTSTRAP_JSON="$bootstrap_json" python3 - <<'PY'
import json
import os

report = json.loads(os.environ["BOOTSTRAP_JSON"])
assert report["schemaVersion"] == 2
assert report["coreRuntime"]["platform"] == "linux"
assert report["coreRuntime"]["status"] == "missing"
assert report["coreRuntime"]["minimumVersion"] == "3.9"
assert "--runtime --dry-run --format json" in report["coreRuntime"]["setupCommand"]
assert report["dryRun"] is True
assert report["applyCommand"].startswith("./Tools/setup-linux.sh --all --yes")
assert all(report["dependencies"][name]["selected"] for name in ("browser", "fonts", "shellcheck"))
assert all(report["dependencies"][name]["plannedAction"] == "deferred" for name in ("browser", "fonts", "shellcheck"))
PY

all_json="$(python3 "$python_setup" --all --dry-run --format json)"
ALL_JSON="$all_json" python3 - <<'PY'
import json
import os

report = json.loads(os.environ["ALL_JSON"])
assert report["coreRuntime"]["selected"] is True
assert all(report["dependencies"][name]["selected"] for name in ("browser", "fonts", "shellcheck"))
if report["platform"]["id"] == "ubuntu" and report["dependencies"]["browser"]["status"] == "missing":
    assert report["dependencies"]["browser"]["blocked"] is True
    assert report["dependencies"]["browser"]["plannedAction"] == "manual"
PY

# Regression für den beobachteten APT-Lockfehler: Update und Installation
# müssen beide durch denselben Root-/sudo-Wrapper laufen.
rg -Fq 'run_root "$manager_executable" update' "$shell_setup" || fail 'Bash-Python-Bootstrap führt apt-get update nicht privilegiert aus.'
rg -Fq 'self.privilege.run((executable, "update"))' "$python_setup" || fail 'Python-Setup führt apt-get update nicht privilegiert aus.'
rg -Fq '"-Syu" if not self.metadata_refreshed else "-S"' "$python_setup" || fail 'Python-Setup darf auf Arch kein unsicheres Partial-Upgrade mit pacman -Sy ausführen.'
rg -Fq 'run_root "$manager_executable" -Syu --noconfirm --needed' "$shell_setup" || fail 'Bash-Bootstrap muss den sicheren vollständigen Pacman-Upgradepfad verwenden.'

python3 -B -m unittest discover -s "$repo_root/Tests/Python" -p 'test_setup_linux.py'
printf '[OK] Linux-Python-Setup, JSON-Vertrag, Delegation und Paketmanagerregeln bestanden.\n'
