#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
dispatcher="$repo_root/Tools/bewerbung.ps1"
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
  local output_file="$test_root/last-output.txt"
  local code
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
  [[ -f "$required_file" ]] || fail "Erforderliche CLI-Datei fehlt: $required_file"
done

bash -n "$launcher"
bash -n "$compat_launcher"

for shell_file in "$launcher" "$compat_launcher"; do
  if grep -Eq '(^|[^[:alnum:]_])eval([[:space:]]|$)' "$shell_file"; then
    fail "Shell-Einstieg verwendet eval: $shell_file"
  fi
  if grep -Eq '(^|[^[:alnum:]_])(jq|python3?|node|sha256sum|shasum)([[:space:]]|$)' "$shell_file"; then
    fail "Shell-Einstieg enthaelt verbotene Fachlogik-Abhaengigkeiten: $shell_file"
  fi
done

# shellcheck disable=SC2016 # PowerShell variables must remain literal here.
pwsh_version="$(pwsh -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()')"
if [[ ! "$pwsh_version" =~ ^([0-9]+)\.([0-9]+) ]] || ((BASH_REMATCH[1] < 7 || (BASH_REMATCH[1] == 7 && BASH_REMATCH[2] < 6))); then
  fail "Dispatcher-Test erfordert PowerShell 7.6 oder neuer; gefunden wurde $pwsh_version."
fi

dispatch_root="$test_root/dispatcher"
mkdir -p "$dispatch_root/Tools" "$dispatch_root/Tests"
cp -- "$dispatcher" "$dispatch_root/Tools/bewerbung.ps1"

# shellcheck disable=SC2016 # PowerShell variables must remain literal here.
printf '%s\n' \
  '#requires -Version 7.6' \
  '#requires -PSEdition Core' \
  '[CmdletBinding()]' \
  'param([string]$Firma, [string]$Rolle, [string]$UmfangAuswahl, [string[]]$Dokumente, [switch]$Fortsetzen)' \
  '[ordered]@{ firma = $Firma; rolle = $Rolle; umfang = $UmfangAuswahl; dokumente = @($Dokumente); fortsetzen = [bool]$Fortsetzen } | ConvertTo-Json -Compress' \
  > "$dispatch_root/Tools/Neue-Bewerbung.ps1"

# shellcheck disable=SC2016 # PowerShell variables must remain literal here.
printf '%s\n' \
  '#requires -Version 7.6' \
  '#requires -PSEdition Core' \
  '[CmdletBinding()]' \
  'param([string]$Browser, [string]$BrowserExecutablePath, [switch]$AlsJson, [switch]$BrowserErforderlich)' \
  '[ordered]@{ browser = $Browser; executable = $BrowserExecutablePath; json = [bool]$AlsJson; required = [bool]$BrowserErforderlich } | ConvertTo-Json -Compress' \
  > "$dispatch_root/Tools/Pruefe-Umgebung.ps1"

# shellcheck disable=SC2016 # PowerShell variables must remain literal here.
printf '%s\n' \
  '#requires -Version 7.6' \
  '#requires -PSEdition Core' \
  '[CmdletBinding()]' \
  'param([string]$Arbeitsordner)' \
  'if ($Arbeitsordner -eq "validierungsfehler") { exit 2 }' \
  'exit 7' \
  > "$dispatch_root/Tools/Ermittle-Bewerbungsstatus.ps1"

dispatch_output="$(pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" \
  neu \
  --firma '-Ae Firma mit Leerzeichen' \
  --rolle 'Entwicklung fuer Muenchen' \
  --umfang=e \
  --dokumente ' lebenslauf, Anschreiben ' \
  --fortsetzen)"
[[ "$dispatch_output" == *'"firma":"-Ae Firma mit Leerzeichen"'* ]] || fail "Fuehrender Bindestrich oder Leerzeichen gingen bei --firma verloren."
[[ "$dispatch_output" == *'"rolle":"Entwicklung fuer Muenchen"'* ]] || fail "Wert mit Leerzeichen wurde veraendert."
[[ "$dispatch_output" == *'"umfang":"E"'* ]] || fail "Enumwert wurde nicht kanonisch normalisiert."
[[ "$dispatch_output" == *'"dokumente":["lebenslauf","anschreiben"]'* ]] || fail "Dokumente-CSV wurde nicht korrekt normalisiert."
[[ "$dispatch_output" == *'"fortsetzen":true'* ]] || fail "Schalter wurde nicht korrekt gebunden."

diagnose_output="$(pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" \
  diagnose \
  --browser Chromium \
  --browser-executable-path '-browser pfad/mit leerzeichen' \
  --als-json \
  --browser-erforderlich)"
[[ "$diagnose_output" == *'"browser":"chromium"'* ]] || fail "Browserwert wurde nicht kanonisch normalisiert."
[[ "$diagnose_output" == *'"executable":"-browser pfad/mit leerzeichen"'* ]] || fail "Browserpfad wurde veraendert."
[[ "$diagnose_output" == *'"json":true'* && "$diagnose_output" == *'"required":true'* ]] || fail "Diagnose-Schalter wurden nicht korrekt gebunden."

help_output="$(pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" --help)"
for command_name in diagnose neu status stammdaten dialog-pruefen dialog-uebernehmen inhalt pruefen layout pdf ats finalisieren tokenbericht tests; do
  [[ "$help_output" == *"$command_name"* ]] || fail "Subcommand fehlt in der globalen Hilfe: $command_name"
done

assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" unbekannt
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" neu --rolle Test
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" neu --firma Test --unbekannt Wert
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" neu --firma
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" neu --firma Test --fortsetzen=true
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" neu --firma Test --firma Zweitwert
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" neu --firma Test --dokumente lebenslauf,unbekannt
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" neu --firma Test --dokumente lebenslauf,lebenslauf
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" layout --ordner Test --width 319
assert_exit 2 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" status --arbeitsordner validierungsfehler
assert_exit 1 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" status --arbeitsordner laufzeitfehler
assert_exit 1 pwsh -NoLogo -NoProfile -NonInteractive -File "$dispatch_root/Tools/bewerbung.ps1" tests --mit-browser

wrapper_root="$test_root/wrapper/Tools"
fake_bin="$test_root/fake-bin"
mkdir -p "$wrapper_root" "$fake_bin"
cp -- "$launcher" "$compat_launcher" "$wrapper_root/"
printf '%s\n' '# synthetic dispatcher marker' > "$wrapper_root/bewerbung.ps1"
chmod +x "$wrapper_root/bewerbung.sh" "$wrapper_root/neue-bewerbung.sh"

# shellcheck disable=SC2016 # The generated fake launcher must expand these variables later.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'for argument in "$@"; do' \
  '  if [[ "$argument" == "-Command" ]]; then' \
  '    printf "%s\n" "${FAKE_PWSH_VERSION:-7.6.0}"' \
  '    exit "${FAKE_VERSION_EXIT_CODE:-0}"' \
  '  fi' \
  'done' \
  ': "${FAKE_CAPTURE_PATH:?}"' \
  ': > "$FAKE_CAPTURE_PATH"' \
  'printf "%s\0" "$@" > "$FAKE_CAPTURE_PATH"' \
  'exit "${FAKE_PWSH_EXIT_CODE:-0}"' \
  > "$fake_bin/pwsh"
chmod +x "$fake_bin/pwsh"

capture="$test_root/direct.capture"
env PATH="$fake_bin:$PATH" FAKE_CAPTURE_PATH="$capture" \
  "$wrapper_root/bewerbung.sh" neu --firma '-Firma mit Leerzeichen' --rolle 'Rolle fuer Koeln'

captured=()
while IFS= read -r -d '' value; do
  captured+=("$value")
done < "$capture"
[[ ${#captured[@]} -eq 10 ]] || fail "Bash-Launcher veraenderte die Anzahl der Argumente."
[[ "${captured[0]}" == "-NoLogo" && "${captured[1]}" == "-NoProfile" && "${captured[2]}" == "-NonInteractive" && "${captured[3]}" == "-File" ]] || fail "Bash-Launcher verwendet nicht den erwarteten pwsh-Aufruf."
[[ "${captured[4]}" == "$wrapper_root/bewerbung.ps1" ]] || fail "Bash-Launcher adressiert nicht den benachbarten Dispatcher."
[[ "${captured[5]}" == "neu" && "${captured[6]}" == "--firma" && "${captured[7]}" == "-Firma mit Leerzeichen" && "${captured[8]}" == "--rolle" && "${captured[9]}" == "Rolle fuer Koeln" ]] || fail "Bash-Launcher reichte Nutzerargumente nicht unveraendert weiter."

compat_capture="$test_root/compat.capture"
env PATH="$fake_bin:$PATH" FAKE_CAPTURE_PATH="$compat_capture" \
  "$wrapper_root/neue-bewerbung.sh" --firma 'Kompatibel GmbH' --umfang A

compat_args=()
while IFS= read -r -d '' value; do
  compat_args+=("$value")
done < "$compat_capture"
[[ ${#compat_args[@]} -eq 10 ]] || fail "Kompatibilitaetswrapper veraenderte die Anzahl der Argumente."
[[ "${compat_args[5]}" == "neu" && "${compat_args[6]}" == "--firma" && "${compat_args[7]}" == "Kompatibel GmbH" && "${compat_args[8]}" == "--umfang" && "${compat_args[9]}" == "A" ]] || fail "Kompatibilitaetswrapper setzte das Subcommand neu nicht korrekt voran."

old_version_capture="$test_root/old-version.capture"
assert_exit 2 env PATH="$fake_bin:$PATH" FAKE_CAPTURE_PATH="$old_version_capture" FAKE_PWSH_VERSION="7.5.9" "$wrapper_root/bewerbung.sh" diagnose
[[ ! -e "$old_version_capture" ]] || fail "Launcher startete den Dispatcher trotz PowerShell kleiner 7.6."

invalid_version_capture="$test_root/invalid-version.capture"
assert_exit 2 env PATH="$fake_bin:$PATH" FAKE_CAPTURE_PATH="$invalid_version_capture" FAKE_PWSH_VERSION="unbekannt" "$wrapper_root/bewerbung.sh" diagnose
[[ ! -e "$invalid_version_capture" ]] || fail "Launcher startete den Dispatcher trotz ungueltigem Versionsformat."

runtime_failure_capture="$test_root/runtime-failure.capture"
assert_exit 1 env PATH="$fake_bin:$PATH" FAKE_CAPTURE_PATH="$runtime_failure_capture" FAKE_PWSH_EXIT_CODE="1" "$wrapper_root/bewerbung.sh" diagnose
[[ -s "$runtime_failure_capture" ]] || fail "Launcher gab den Laufzeitfehler nicht vom Dispatcher zurueck."

printf '[OK] Einheitliche CLI- und Wrapper-Regressionstests bestanden.\n'
