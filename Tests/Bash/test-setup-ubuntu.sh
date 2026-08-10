#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
setup="$repo_root/Tools/setup-ubuntu.sh"
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
  local expected=$1
  shift
  local code
  set +e
  "$@" >"$test_root/output.txt" 2>&1
  code=$?
  set -e
  if [[ $code -ne $expected ]]; then
    printf '[FEHLER] Erwarteter Exitcode %s, erhalten %s.\n' "$expected" "$code" >&2
    sed 's/^/  /' "$test_root/output.txt" >&2
    exit 1
  fi
}

[[ -f "$setup" ]] || fail "Ubuntu-Setup fehlt: $setup"
[[ -x "$setup" ]] || fail "Ubuntu-Setup besitzt nicht den Git-Ausführungsmodus 100755."
bash -n "$setup"

grep -Fq "readonly GOOGLE_SIGNING_KEY_FINGERPRINT='EB4C1BFD4F042F6DDDCCEC917721F63BD38B4796'" "$setup" ||
  fail 'Ubuntu-Setup bindet den Google-Schlüssel nicht an den erwarteten Fingerprint.'
grep -Fq "readonly MICROSOFT_POWERSHELL_APT_SOURCE='https://packages.microsoft.com/ubuntu/24.04/prod noble/main amd64 Packages'" "$setup" ||
  fail 'Ubuntu-Setup bindet PowerShell nicht an die exakte offizielle Microsoft-Quelle.'
grep -Fq 'package_source == expected_source' "$setup" ||
  fail 'Ubuntu-Setup filtert apt-cache-Ergebnisse nicht auf die erwartete Microsoft-Quelle.'

help_output="$(bash "$setup")"
[[ "$help_output" == *'Ohne Auswahl wird nichts verändert.'* ]] || fail 'Aufruf ohne Auswahl zeigt nicht ausschließlich die sichere Hilfe.'
assert_exit 2 bash "$setup" --unbekannt
assert_exit 2 bash "$setup" --browser firefox

wrong_os_release="$test_root/wrong-os-release"
wrong_os_setup="$test_root/setup-wrong-os.sh"
printf '%s\n' 'ID=debian' 'VERSION_ID="12"' >"$wrong_os_release"
sed "s#/etc/os-release#$wrong_os_release#g" "$setup" >"$wrong_os_setup"
assert_exit 2 bash "$wrong_os_setup" --all --dry-run
grep -Fq 'Nicht unterstützte Plattform' "$test_root/output.txt" ||
  fail 'Falsches Betriebssystem wurde nicht mit einer eindeutigen Plattformmeldung abgewiesen.'

if [[ ! -r /etc/os-release ]]; then
  printf '[INFO] Host stellt /etc/os-release nicht bereit; Ubuntu-spezifische Laufzeitprüfungen entfallen.\n'
  printf '[OK] Ubuntu-Setup-Parser-, Herkunfts- und OS-Abweisungstests bestanden.\n'
  exit 0
fi

distribution_id="$(sed -n 's/^ID=//p' /etc/os-release | head -n 1 | tr -d '"')"
distribution_version="$(sed -n 's/^VERSION_ID=//p' /etc/os-release | head -n 1 | tr -d '"')"
if [[ "$distribution_id" != ubuntu || "$distribution_version" != 24.04 ]]; then
  printf '[INFO] Host ist nicht Ubuntu 24.04; plattformspezifische Setup-Tests sind hier nicht ausführbar.\n'
  exit 0
fi

wrong_arch_bin="$test_root/wrong-arch-bin"
mkdir -p "$wrong_arch_bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" aarch64' >"$wrong_arch_bin/uname"
chmod +x "$wrong_arch_bin/uname"
assert_exit 2 env PATH="$wrong_arch_bin:$PATH" bash "$setup" --all --dry-run

missing_bin="$test_root/missing-bin"
mkdir -p "$missing_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 99' >"$missing_bin/apt-get"
chmod +x "$missing_bin/apt-get"
dry_run_output="$(env PATH="$missing_bin:$PATH" bash "$setup" --all --dry-run)"
[[ "$dry_run_output" == *'Dry-run abgeschlossen; es wurde nichts verändert.'* || "$dry_run_output" == *'Alle ausgewählten Komponenten sind bereits passend installiert.'* ]] || fail 'Dry-run meldet keinen sicheren unveränderten Abschluss.'

fake_bin="$test_root/idempotent-bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/pwsh"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "Google Chrome 151.0.0.0"' >"$fake_bin/google-chrome-stable"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s" "Liberation Sans"' >"$fake_bin/fc-match"
chmod +x "$fake_bin/pwsh" "$fake_bin/google-chrome-stable" "$fake_bin/fc-match"
idempotent_output="$(env PATH="$fake_bin:$PATH" bash "$setup" --all --yes)"
[[ "$idempotent_output" == *'Alle ausgewählten Komponenten sind bereits passend installiert.'* ]] || fail 'Passende Installationen werden nicht idempotent akzeptiert.'

printf '[OK] Ubuntu-Setup-Parser-, Abweisungs-, Dry-run- und Idempotenztests bestanden.\n'
