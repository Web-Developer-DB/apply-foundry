#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
setup="$repo_root/Tools/setup-linux.sh"
alias_setup="$repo_root/Tools/setup-ubuntu.sh"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
fail() { printf '[FEHLER] %s\n' "$1" >&2; exit 1; }
assert_exit() { local expected="$1"; shift; set +e; "$@" >"$test_root/out" 2>&1; local code=$?; set -e; [[ "$code" -eq "$expected" ]] || { sed 's/^/  /' "$test_root/out" >&2; fail "Exitcode $expected erwartet, $code erhalten."; }; }
[[ -x "$setup" && -x "$alias_setup" ]] || fail 'Linux-Setup oder Ubuntu-Kompatibilitätsalias fehlt.'
bash -n "$setup" "$alias_setup"
help_output="$(bash "$setup" --help)"
[[ "$help_output" == *'--browser chromium'* && "$help_output" == *'--format text|json'* ]] || fail 'Linux-Setup-Hilfe ist unvollständig.'
assert_exit 2 bash "$setup" --browser firefox
assert_exit 2 bash "$setup" --runtime
if command -v script >/dev/null 2>&1; then
  set +e
  reject_output="$(printf 'n\n' | script -qec "bash '$setup' --runtime" /dev/null 2>&1)"
  reject_code=$?
  set -e
  [[ "$reject_code" -eq 1 && "$reject_output" == *'Setup wurde ohne Änderungen abgebrochen.'* ]] || fail 'Interaktive Ablehnung wurde nicht ohne Änderungen beendet.'
fi
wrong_arch="$test_root/wrong-arch"; mkdir -p "$wrong_arch"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" aarch64' > "$wrong_arch/uname"; chmod +x "$wrong_arch/uname"
assert_exit 2 env PATH="$wrong_arch:$PATH" bash "$setup" --runtime --dry-run
json_output="$(bash "$setup" --runtime --dry-run --format json)"
if command -v apt-get >/dev/null 2>&1; then expected_manager=apt
elif command -v dnf >/dev/null 2>&1; then expected_manager=dnf
elif command -v yum >/dev/null 2>&1; then expected_manager=yum
elif command -v pacman >/dev/null 2>&1; then expected_manager=pacman
else expected_manager=zypper; fi
[[ "$json_output" == *'"schemaVersion":1'* && "$json_output" == *"\"packageManager\":\"$expected_manager\""* && "$json_output" == *'"dryRun":1'* ]] || fail 'JSON-Dry-run enthält nicht den Paketmanager und den unveränderten Status.'
rg -q 'schemaVersion = 2' "$repo_root/Tools/Pruefe-Umgebung.ps1" || fail 'Diagnose verwendet nicht das neue Schema 2.'
rg -q 'dependencies = \$dependencyDetails' "$repo_root/Tools/Pruefe-Umgebung.ps1" || fail 'Diagnose enthält keinen Abhängigkeitsnachweis.'
unknown="$test_root/unknown"; mkdir -p "$unknown"
ln -s "$(command -v uname)" "$unknown/uname"; ln -s "$(command -v sed)" "$unknown/sed"; ln -s "$(command -v head)" "$unknown/head"; ln -s "$(command -v dirname)" "$unknown/dirname"
assert_exit 2 env PATH="$unknown" /bin/bash "$setup" --runtime --dry-run
fake_manager="$test_root/fake-manager"; mkdir -p "$fake_manager"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_manager/dnf"; chmod +x "$fake_manager/dnf"
for tool in uname sed head dirname; do ln -s "$(command -v "$tool")" "$fake_manager/$tool"; done
manager_json="$(env PATH="$fake_manager" /bin/bash "$setup" --runtime --dry-run --format json)"
[[ "$manager_json" == *'"packageManager":"dnf"'* ]] || fail 'DNF-Erkennung wurde nicht im JSON-Installationsplan ausgegeben.'
alias_output="$(bash "$alias_setup" --runtime --dry-run 2>&1)"
[[ "$alias_output" == *'Kompatibilitätsalias'* && "$alias_output" == *'Dry-run abgeschlossen'* ]] || fail 'Ubuntu-Kompatibilitätsalias delegiert nicht korrekt.'
local_runtime="$test_root/local-runtime"; mkdir -p "$local_runtime/data/apply-foundry/runtime/powershell/7.6.4"
printf '%s\n' '#!/usr/bin/env bash' 'if [[ "$*" == *"PSVersionTable.PSVersion.ToString"* ]]; then printf "%s\n" 7.6.4; else printf "%s\n" local-runtime; fi' > "$local_runtime/data/apply-foundry/runtime/powershell/7.6.4/pwsh"; chmod +x "$local_runtime/data/apply-foundry/runtime/powershell/7.6.4/pwsh"
launcher_output="$(env -u PATH XDG_DATA_HOME="$local_runtime/data" HOME="$local_runtime" /bin/bash "$repo_root/Tools/bewerbung.sh" diagnose)"
[[ "$launcher_output" == *'local-runtime'* ]] || fail 'Bash-Launcher verwendet die verifizierte lokale Runtime nicht als Fallback.'
fake="$test_root/fake"; mkdir -p "$fake"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" 7.6.0' > "$fake/pwsh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "Chromium 151.0.0.0"' > "$fake/chromium"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s" "Liberation Sans"' > "$fake/fc-match"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "Version: 0.10.0"' > "$fake/shellcheck"
chmod +x "$fake"/*
idempotent="$(env PATH="$fake:$PATH" bash "$setup" --all --yes)"
[[ "$idempotent" == *'PowerShell: present'* && "$idempotent" == *'Chromium: present'* && "$idempotent" == *'ShellCheck: present'* ]] || fail 'Idempotente Erkennung der vorhandenen Komponenten fehlgeschlagen.'
archive_root="$test_root/archive-case"; mkdir -p "$archive_root/Tools" "$archive_root/bin"
cp "$setup" "$archive_root/Tools/setup-linux.sh"
sed "s/4471B5A36BFE86EC7AF8525D36BB1CACBA0128E7AAC22D05CC064BC00E604721/0000000000000000000000000000000000000000000000000000000000000000/" "$repo_root/Tools/PowerShell-runtime.json" > "$archive_root/Tools/PowerShell-runtime.json"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$archive_root/bin/dnf"
printf '%s\n' '#!/bin/sh' 'while [ "$#" -gt 0 ]; do if [ "$1" = "--output" ]; then shift; printf "%s" invalid-archive > "$1"; exit 0; fi; shift; done' > "$archive_root/bin/curl"
printf '%s\n' '#!/bin/sh' 'if [ "$1" = "--" ]; then shift; fi; exec "$@"' > "$archive_root/bin/sudo"
chmod +x "$archive_root/bin/dnf" "$archive_root/bin/curl" "$archive_root/bin/sudo"
for tool in uname sed head dirname sha256sum awk tr mktemp mkdir chmod rm; do ln -s "$(command -v "$tool")" "$archive_root/bin/$tool"; done
set +e
hash_output="$(env PATH="$archive_root/bin" HOME="$archive_root/home" /bin/bash "$archive_root/Tools/setup-linux.sh" --runtime --yes 2>&1)"
hash_code=$?
set -e
[[ "$hash_code" -eq 1 && "$hash_output" == *'SHA-256-Prüfung'* ]] || fail 'Falscher PowerShell-Archiv-Hash wurde nicht sicher abgewiesen.'
printf '[OK] Plattformneutrale Linux-Setup-Parser-, JSON-, Alias- und Idempotenztests bestanden.\n'
