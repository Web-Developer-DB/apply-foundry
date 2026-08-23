#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
dispatcher="$repo_root/Tools/bewerbung.py"
launcher="$repo_root/Tools/bewerbung.sh"
compat_launcher="$repo_root/Tools/neue-bewerbung.sh"
test_root="$(mktemp -d)"

case "$test_root" in
  /tmp/*|/private/tmp/*) ;;
  *) printf 'Unsicherer Testpfad: %s\n' "$test_root" >&2; exit 99 ;;
esac
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf '[FEHLER] %s\n' "$1" >&2
  exit 1
}

assert_exit() {
  local expected="$1"
  shift
  local output_file="$test_root/last-output.txt" code
  set +e
  "$@" >"$output_file" 2>&1
  code=$?
  set -e
  if [[ $code -ne $expected ]]; then
    printf '[FEHLER] Erwarteter Exitcode %s, erhalten %s. Ausgabe:\n' "$expected" "$code" >&2
    sed 's/^/  /' "$output_file" >&2
    exit 1
  fi
}

for required_file in "$dispatcher" "$launcher" "$compat_launcher"; do
  [[ -f "$required_file" ]] || fail "Erforderliche Linux-CLI-Datei fehlt: $required_file"
done
for executable_file in "$dispatcher" "$launcher" "$compat_launcher"; do
  [[ -x "$executable_file" ]] || fail "Linux-Einstieg besitzt nicht den Git-Ausführungsmodus 100755: $executable_file"
done

bash -n "$launcher"
bash -n "$compat_launcher"
for shell_file in "$launcher" "$compat_launcher"; do
  grep -Eq '(^|[^[:alnum:]_])eval([[:space:]]|$)' "$shell_file" && fail "Shell-Einstieg verwendet eval: $shell_file"
  grep -Fq 'pwsh' "$shell_file" && fail "Linux-Alias hängt weiterhin von PowerShell ab: $shell_file"
done

python3 -I -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' || fail 'Python 3.9 oder neuer ist für den Linux-Vertragstest erforderlich.'

help_output="$(python3 -B "$dispatcher" --help)"
for command_name in diagnose neu universal-neu universal-status universal-finalisieren status checkpoint migrieren stammdaten dialog-pruefen dialog-uebernehmen passfoto kontext inhalt pruefen layout pdf ats finalisieren freigabe tokenbericht test-baseline tests; do
  [[ "$help_output" == *"$command_name"* ]] || fail "Subcommand fehlt in der globalen Python-Hilfe: $command_name"
done

alias_help="$("$launcher" --help)"
[[ "$alias_help" == "$help_output" ]] || fail 'bewerbung.sh delegiert nicht unverändert an den Python-Dispatcher.'
compat_help="$("$compat_launcher" --help)"
[[ "$compat_help" == *'Aufruf: neu [optionen]'* ]] || fail 'neue-bewerbung.sh setzt das Subcommand neu nicht voran.'

assert_exit 2 python3 -B "$dispatcher" unbekannt
assert_exit 2 python3 -B "$dispatcher" neu --rolle Test
assert_exit 2 python3 -B "$dispatcher" neu --firma Test --unbekannt Wert
assert_exit 2 python3 -B "$dispatcher" neu --firma
assert_exit 2 python3 -B "$dispatcher" neu --firma Test --fortsetzen=true
assert_exit 2 python3 -B "$dispatcher" neu --firma Test --firma Zweitwert
assert_exit 2 python3 -B "$dispatcher" neu --firma Test --dokumente lebenslauf,unbekannt
assert_exit 2 python3 -B "$dispatcher" neu --firma Test --dokumente lebenslauf,lebenslauf
assert_exit 2 python3 -B "$dispatcher" layout --ordner Test --width 319

wrapper_root="$test_root/wrapper/Tools"
mkdir -p "$wrapper_root"
cp -- "$launcher" "$compat_launcher" "$wrapper_root/"
chmod +x "$wrapper_root/bewerbung.sh" "$wrapper_root/neue-bewerbung.sh"

printf '%s\n' \
  '#!/usr/bin/env python3' \
  'import os, sys' \
  'target = os.environ["FAKE_CAPTURE_PATH"]' \
  'with open(target, "wb") as stream:' \
  '    for value in sys.argv[1:]:' \
  '        stream.write(value.encode("utf-8") + b"\0")' \
  'raise SystemExit(int(os.environ.get("FAKE_EXIT_CODE", "0")))' \
  '# synthetic Python dispatcher used only by the Bash adapter contract' \
  > "$wrapper_root/bewerbung.py"
chmod +x "$wrapper_root/bewerbung.py"

capture="$test_root/direct.capture"
env FAKE_CAPTURE_PATH="$capture" \
  "$wrapper_root/bewerbung.sh" neu --firma '-Firma mit Leerzeichen' --rolle 'Rolle für Köln'
captured=()
while IFS= read -r -d '' value; do captured+=("$value"); done < "$capture"
[[ ${#captured[@]} -eq 5 ]] || fail 'Bash-Launcher veränderte die Anzahl der Nutzerargumente.'
[[ "${captured[0]}" == neu && "${captured[1]}" == --firma && "${captured[2]}" == '-Firma mit Leerzeichen' && "${captured[3]}" == --rolle && "${captured[4]}" == 'Rolle für Köln' ]] || fail 'Bash-Launcher reichte Nutzerargumente nicht bytegetreu weiter.'

compat_capture="$test_root/compat.capture"
env FAKE_CAPTURE_PATH="$compat_capture" \
  "$wrapper_root/neue-bewerbung.sh" --firma 'Kompatibel GmbH' --umfang A
compat_args=()
while IFS= read -r -d '' value; do compat_args+=("$value"); done < "$compat_capture"
[[ ${#compat_args[@]} -eq 5 ]] || fail 'Kompatibilitätsalias veränderte die Anzahl der Nutzerargumente.'
[[ "${compat_args[0]}" == neu && "${compat_args[1]}" == --firma && "${compat_args[2]}" == 'Kompatibel GmbH' && "${compat_args[3]}" == --umfang && "${compat_args[4]}" == A ]] || fail 'Kompatibilitätsalias setzte neu nicht korrekt voran.'

failure_capture="$test_root/failure.capture"
assert_exit 1 env FAKE_CAPTURE_PATH="$failure_capture" FAKE_EXIT_CODE=1 "$wrapper_root/bewerbung.sh" diagnose
[[ -s "$failure_capture" ]] || fail 'Launcher gab den Laufzeitfehler des Python-Dispatchers nicht zurück.'

printf '[OK] Python-CLI- und Linux-Alias-Regressionstests bestanden.\n'
