#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd -P)"
readonly ROOT
MANIFEST="$ROOT/PowerShell-runtime.json"
readonly MANIFEST
readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_OR_PLATFORM=2
runtime=0; browser=0; fonts=0; shellcheck=0; dry_run=0; assume_yes=0; format=text
tmp=''; manager=''; distro=''; distro_version=''; runtime_status=not_requested
browser_status=not_requested; fonts_status=not_requested; shellcheck_status=not_requested; browser_blocked=0
runtime_source=''; browser_source=''; fonts_source=''; shellcheck_source=''

usage() {
  printf '%s\n' 'Verwendung: setup-linux.sh [AUSWAHL] [OPTIONEN]' \
    '  --runtime             PowerShell 7.6 Core' \
    '  --browser chromium    Chromium aus der Distribution' \
    '  --fonts               Liberation Sans (Linux)' \
    '  --shellcheck          ShellCheck für Entwicklungs- und CI-Prüfungen' \
    '  --all                 alle deklarierten Komponenten' \
    '  --dry-run             geplante Änderungen nur anzeigen' \
    '  --yes                 bestätigte Änderungen ausführen' \
    '  --format text|json    Ausgabeformat'
}
die() { printf 'FEHLER: %s\n' "$1" >&2; usage >&2; exit "$EXIT_USAGE_OR_PLATFORM"; }
fail() { printf 'FEHLER: %s\n' "$1" >&2; state >&2; exit "$EXIT_RUNTIME_ERROR"; }
state() {
  printf '%s\n' "PowerShell: $runtime_status" "Chromium: $browser_status" "Fonts: $fonts_status" "ShellCheck: $shellcheck_status"
  if ((runtime)) && declare -F pwsh_path >/dev/null 2>&1; then
    local runtime_executable runtime_version_found
    runtime_executable=$(pwsh_path || true)
    runtime_version_found='nicht ermittelbar'
    # shellcheck disable=SC2016 # PowerShell expression must remain literal for the child process.
    if [[ -n "$runtime_executable" ]]; then runtime_version_found=$("$runtime_executable" -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true); fi
    printf '%s\n' "  validiert: PowerShell ${runtime_version_found:-nicht ermittelbar} (${runtime_executable:-kein Pfad})"
  fi
  if ((browser)) && declare -F browser_path >/dev/null 2>&1; then
    local browser_executable browser_version_found
    browser_executable=$(browser_path || true)
    browser_version_found='nicht ermittelbar'
    if [[ -n "$browser_executable" ]]; then browser_version_found=$("$browser_executable" --version 2>/dev/null || true); fi
    printf '%s\n' "  validiert: Chromium ${browser_version_found:-nicht ermittelbar} (${browser_executable:-kein Pfad})"
  fi
  if ((fonts)); then printf '%s\n' "  validiert: Liberation Sans $(fc-match --format='%{file}' 'Liberation Sans' 2>/dev/null || true)"; fi
  if ((shellcheck)); then printf '%s\n' "  validiert: ShellCheck $(shellcheck --version 2>/dev/null | sed -n 's/^[Vv]ersion:[[:space:]]*//p' | head -n1) ($(command -v shellcheck || true))"; fi
}
cleanup() { [[ -z "$tmp" || ! -d "$tmp" ]] || rm -rf -- "$tmp"; }
on_error() { local line="$1" code="$2"; printf 'FEHLER: Linux-Setup schlug in Zeile %s (Status %s) fehl.\n' "$line" "$code" >&2; state >&2; exit "$EXIT_RUNTIME_ERROR"; }
trap cleanup EXIT
# shellcheck disable=SC2016 # Trap expands LINENO and the prior status at execution time.
trap 'on_error "$LINENO" "$?"' ERR
while (($#)); do
  case "$1" in
    --runtime) runtime=1; shift ;;
    --browser) (($# > 1)) || die '--browser benötigt chromium.'; [[ "$2" == chromium ]] || die "Nicht unterstützter Browser: $2"; browser=1; shift 2 ;;
    --browser=chromium) browser=1; shift ;;
    --browser=*) die "Nicht unterstützter Browser: ${1#*=}" ;;
    --fonts) fonts=1; shift ;;
    --shellcheck) shellcheck=1; shift ;;
    --all) runtime=1; browser=1; fonts=1; shellcheck=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --yes) assume_yes=1; shift ;;
    --format) (($# > 1)) || die '--format benötigt text oder json.'; format="$2"; shift 2 ;;
    --format=text|--format=json) format="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unbekannte Option: $1" ;;
  esac
done
[[ "$format" == text || "$format" == json ]] || die "Nicht unterstütztes Format: $format"
((runtime || browser || fonts || shellcheck)) || { usage; exit 0; }
[[ -r /etc/os-release ]] || { printf '%s\n' '/etc/os-release fehlt.' >&2; exit "$EXIT_USAGE_OR_PLATFORM"; }
# shellcheck disable=SC1091
. /etc/os-release
distro="${ID:-}"; distro_version="${VERSION_ID:-}"
[[ "$(uname -m)" == x86_64 ]] || { printf '%s\n' 'Nur Linux x86_64 wird unterstützt.' >&2; exit "$EXIT_USAGE_OR_PLATFORM"; }
if command -v apt-get >/dev/null 2>&1; then manager=apt
elif command -v dnf >/dev/null 2>&1; then manager=dnf
elif command -v yum >/dev/null 2>&1; then manager=yum
elif command -v pacman >/dev/null 2>&1; then manager=pacman
elif command -v zypper >/dev/null 2>&1; then manager=zypper
else
  printf '%s\n' 'Kein unterstützter Paketmanager (APT, DNF/YUM, Pacman oder Zypper).' >&2
  printf '%s\n' 'Manuell benötigt: PowerShell 7.6 Core, Chromium, Liberation Sans, ShellCheck.' >&2
  exit "$EXIT_USAGE_OR_PLATFORM"
fi
[[ -r "$MANIFEST" ]] || fail "Runtime-Manifest fehlt: $MANIFEST"
version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n1)
url=$(sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n1)
sha=$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([A-Fa-f0-9]*\)".*/\1/p' "$MANIFEST" | head -n1)
[[ "$version" =~ ^7\.6\.[0-9]+$ && "$url" == https://github.com/PowerShell/PowerShell/releases/download/v7.6.* && "$sha" =~ ^[A-Fa-f0-9]{64}$ ]] || fail 'Runtime-Manifest ist ungültig.'
if [[ -n "${XDG_DATA_HOME:-}" ]]; then data_home="$XDG_DATA_HOME"; else data_home="$HOME/.local/share"; fi
local_root="$data_home/apply-foundry/runtime/powershell/$version"; local_pwsh="$local_root/pwsh"
pwsh_path() { local p; p=$(command -v pwsh 2>/dev/null || true); [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }; [[ -x "$local_pwsh" ]] && printf '%s' "$local_pwsh"; }
runtime_ok() { local p v; p=$(pwsh_path || true); [[ -n "$p" ]] || return 1; v=$("$p" -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || true); [[ "$v" =~ ^7\.([6-9]|[1-9][0-9])([.][0-9]+)?([.-].*)?$ ]]; }
browser_path() { local p v; for p in chromium chromium-browser /usr/bin/chromium; do if command -v "$p" >/dev/null 2>&1 || [[ -x "$p" ]]; then v=$("$p" --version 2>/dev/null || true); [[ "$v" =~ [Cc]hrom(e|ium)[[:space:]]+[0-9]+ ]] && { printf '%s' "$p"; return 0; }; fi; done; return 1; }
browser_is_snap_transition() { [[ "$manager" == apt && "$distro" == ubuntu ]] && command -v apt-cache >/dev/null 2>&1 && apt-cache show "$browser_package" "${browser_package}-browser" 2>/dev/null | grep -qi 'snap'; }
fonts_ok() { command -v fc-match >/dev/null 2>&1 && fc-match --format='%{family}' 'Liberation Sans' 2>/dev/null | grep -Fq 'Liberation Sans'; }
shellcheck_ok() { local v; command -v shellcheck >/dev/null 2>&1 || return 1; v=$(shellcheck --version 2>/dev/null | sed -n 's/^[Vv]ersion:[[:space:]]*//p' | head -n1); [[ "$v" =~ ^[0-9]+([.][0-9]+){1,2}$ ]]; }
((runtime)) && runtime_ok && runtime_status=present || true; ((runtime)) && [[ "$runtime_status" != present ]] && runtime_status=missing
((browser)) && browser_path >/dev/null && browser_status=present || true; ((browser)) && [[ "$browser_status" != present ]] && browser_status=missing
((fonts)) && fonts_ok && fonts_status=present || true; ((fonts)) && [[ "$fonts_status" != present ]] && fonts_status=missing
((shellcheck)) && shellcheck_ok && shellcheck_status=present || true; ((shellcheck)) && [[ "$shellcheck_status" != present ]] && shellcheck_status=missing
case "$manager" in
  apt) browser_package=chromium; fonts_package=fonts-liberation2; shellcheck_package=shellcheck; runtime_package=powershell; runtime_source='Microsoft-Paketquelle (Fallback: offizielles SHA-256-geprüftes Archiv)'; browser_source='Chromium aus der APT-Distribution'; fonts_source='Liberation Sans aus der APT-Distribution'; shellcheck_source='ShellCheck aus der APT-Distribution'; solution='Microsoft-Paketquelle für Debian/Ubuntu' ;;
  dnf|yum) browser_package=chromium; fonts_package=liberation-sans-fonts; shellcheck_package=ShellCheck; runtime_package=powershell; runtime_source='Microsoft-Paketquelle für RHEL-kompatible Systeme (Fallback: offizielles SHA-256-geprüftes Archiv)'; browser_source='Chromium aus der DNF/YUM-Distribution'; fonts_source='Liberation Sans aus der DNF/YUM-Distribution'; shellcheck_source='ShellCheck aus der DNF/YUM-Distribution'; solution='Microsoft-Paketquelle für RHEL-kompatible Systeme' ;;
  pacman) browser_package=chromium; fonts_package=ttf-liberation; shellcheck_package=shellcheck; runtime_package=''; runtime_source='offizielles PowerShell-Archiv, lokal und SHA-256-geprüft'; browser_source='Chromium aus der Pacman-Distribution'; fonts_source='Liberation Sans aus der Pacman-Distribution'; shellcheck_source='ShellCheck aus der Pacman-Distribution'; solution='offizielles PowerShell-Archiv, lokal und SHA-256-geprüft' ;;
  zypper) browser_package=chromium; fonts_package=liberation-fonts; shellcheck_package=ShellCheck; runtime_package=''; runtime_source='offizielles PowerShell-Archiv, lokal und SHA-256-geprüft'; browser_source='Chromium aus der Zypper-Distribution'; fonts_source='Liberation Sans aus der Zypper-Distribution'; shellcheck_source='ShellCheck aus der Zypper-Distribution'; solution='offizielles PowerShell-Archiv, lokal und SHA-256-geprüft' ;;
esac
if [[ "$manager" == dnf || "$manager" == yum ]] && [[ "$distro" != rhel && "$distro" != rocky && "$distro" != almalinux && "$distro" != centos ]]; then solution='offizielles PowerShell-Archiv, lokal und SHA-256-geprüft'; runtime_source="$solution"; fi
if browser_is_snap_transition; then browser_source='Ubuntu stellt Chromium hier nur als Snap-Transition bereit; keine automatische Snap-Installation'; fi
json() { local blocked="$browser_blocked"; if ((browser)) && ((blocked == 0)) && browser_is_snap_transition; then blocked=1; fi; printf '{"schemaVersion":1,"platform":{"id":"%s","version":"%s","architecture":"x86_64"},"packageManager":"%s","runtime":{"status":"%s","solution":"%s","source":"%s","package":"%s","permission":"root-or-sudo-for-packages"},"browser":{"status":"%s","package":"%s","source":"%s","permission":"root-or-sudo","blocked":%s},"fonts":{"status":"%s","package":"%s","source":"%s","permission":"root-or-sudo"},"shellcheck":{"status":"%s","package":"%s","source":"%s","permission":"root-or-sudo"},"dryRun":%s}\n' "$distro" "$distro_version" "$manager" "$runtime_status" "$solution" "$runtime_source" "$runtime_package" "$browser_status" "$browser_package" "$browser_source" "$blocked" "$fonts_status" "$fonts_package" "$fonts_source" "$shellcheck_status" "$shellcheck_package" "$shellcheck_source" "$dry_run"; }
plan() {
  printf '%s\n' 'Geplante Projektabhängigkeiten:' "  Plattform: $distro $distro_version (x86_64)" "  Paketmanager: $manager"
  if ((runtime)); then printf '  PowerShell: %s | Paket=%s | Quelle=%s | Rechte=Root/sudo für Paketabhängigkeiten, Runtime benutzerweit möglich\n' "$runtime_status" "${runtime_package:-Archiv}" "$runtime_source"; fi
  if ((browser)); then printf '  Chromium: %s | Paket=%s | Quelle=%s | Rechte=Root/sudo\n' "$browser_status" "$browser_package" "$browser_source"; fi
  if ((fonts)); then printf '  Fonts: %s | Paket=%s | Quelle=%s | Rechte=Root/sudo\n' "$fonts_status" "$fonts_package" "$fonts_source"; fi
  if ((shellcheck)); then printf '  ShellCheck: %s | Paket=%s | Quelle=%s | Rechte=Root/sudo\n' "$shellcheck_status" "$shellcheck_package" "$shellcheck_source"; fi
}
if ((dry_run)); then [[ "$format" == json ]] && json || { plan; printf '%s\n' 'Dry-run abgeschlossen; es wurde nichts verändert.'; }; exit 0; fi
if ((browser)) && [[ "$browser_status" == missing ]] && browser_is_snap_transition; then browser_blocked=1; browser_status=unavailable; fi
pending=0; for s in "$runtime_status" "$browser_status" "$fonts_status" "$shellcheck_status"; do [[ "$s" == missing ]] && pending=1; done
if ((pending == 0)); then
  if ((browser_blocked)); then
    [[ "$format" == json ]] && json || plan
    printf '%s\n' 'Ubuntu bietet für Chromium nur eine Snap-Transition an. Gemäß Projektvertrag wird Snap nicht automatisch installiert; bitte Chromium aus einer von dir freigegebenen nativen Quelle bereitstellen und danach erneut diagnostizieren.' >&2
    exit "$EXIT_USAGE_OR_PLATFORM"
  fi
  [[ "$format" == json ]] && json || { plan; printf '%s\n' 'Alle ausgewählten Komponenten sind bereits passend installiert.'; }; exit 0
fi
if ((assume_yes == 0)); then plan; [[ -t 0 ]] || { printf '%s\n' 'Keine interaktive Eingabe verfügbar; nach Prüfung mit --yes erneut starten.' >&2; exit "$EXIT_USAGE_OR_PLATFORM"; }; printf 'Diese Änderungen jetzt ausführen? [j/N] '; read -r answer; case "$answer" in j|J|ja|JA|Ja|y|Y|yes|YES|Yes) ;; *) printf '%s\n' 'Setup wurde ohne Änderungen abgebrochen.'; exit "$EXIT_RUNTIME_ERROR" ;; esac; fi
if ((EUID == 0)); then as_root() { "$@"; }; elif command -v sudo >/dev/null 2>&1; then as_root() { sudo -- "$@"; }; else fail 'Für Systemänderungen sind Root-Rechte oder sudo erforderlich.'; fi
tmp=$(mktemp -d -t apply-foundry-setup.XXXXXXXX)
install_one() { case "$manager" in apt) apt-get update >&2; as_root apt-get install -y "$1" >&2 ;; dnf) as_root dnf install -y "$1" >&2 ;; yum) as_root yum install -y "$1" >&2 ;; pacman) as_root pacman -Sy --noconfirm --needed "$1" >&2 ;; zypper) as_root zypper --non-interactive install --no-recommends "$1" >&2 ;; esac; }
install_archive() { install_one curl; install_one ca-certificates; install_one tar; local archive actual; archive="$tmp/powershell.tar.gz"; curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$url" --output "$archive"; actual=$(sha256sum "$archive" | awk '{print toupper($1)}'); [[ "$actual" == "$(printf '%s' "$sha" | tr '[:lower:]' '[:upper:]')" ]] || fail 'SHA-256-Prüfung des PowerShell-Archivs fehlgeschlagen.'; mkdir -p "$local_root"; tar -xzf "$archive" -C "$local_root"; chmod +x "$local_pwsh"; runtime_ok || fail 'Archiv-PowerShell meldet nicht Core 7.6.'; runtime_status=installed; }
install_repo() {
  if [[ "$manager" == apt ]]; then
    if [[ "$distro" != ubuntu && "$distro" != debian ]]; then
      install_archive
      return
    fi
    install_one curl; install_one ca-certificates; install_one gnupg; install_one apt-transport-https
    local repo="https://packages.microsoft.com/config/$distro/$distro_version/packages-microsoft-prod.deb"
    if ! curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$repo" --output "$tmp/repo.deb"; then
      printf '%s\n' 'Microsoft-Paketquelle für diese Distribution ist nicht verfügbar; verwende das geprüfte offizielle Archiv.' >&2
      install_archive
      return
    fi
    dpkg-deb --info "$tmp/repo.deb" >/dev/null || fail 'Microsoft-Repositorypaket ist ungültig.'; [[ "$(dpkg-deb --field "$tmp/repo.deb" Package)" == packages-microsoft-prod && "$(dpkg-deb --field "$tmp/repo.deb" Architecture)" == all ]] || fail 'Microsoft-Repositorypaket besitzt unerwartete Metadaten.'; as_root dpkg -i "$tmp/repo.deb"; install_one "$runtime_package"
  else install_one curl; install_one ca-certificates; local major; major=$(printf '%s' "$distro_version" | cut -d. -f1); local repo="https://packages.microsoft.com/config/rhel/$major/packages-microsoft-prod.rpm"; curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$repo" --output "$tmp/repo.rpm"; rpm --checksig "$tmp/repo.rpm" >/dev/null || fail 'Microsoft-Repositorypaket ohne gültige RPM-Signatur.'; as_root rpm -U "$tmp/repo.rpm"; install_one "$runtime_package"; fi
  runtime_ok || fail 'Installierte PowerShell meldet nicht Core 7.6.'; runtime_status=installed
}
if ((runtime)) && [[ "$runtime_status" == missing ]]; then
  if [[ -n "$runtime_package" && "$solution" != *Archiv* ]]; then install_repo; else install_archive; fi
fi
if ((browser)) && [[ "$browser_status" == missing ]]; then install_one "$browser_package"; browser_path >/dev/null || fail 'Chromium konnte nicht validiert werden.'; browser_status=installed; fi
if ((fonts)) && [[ "$fonts_status" == missing ]]; then install_one "$fonts_package"; fonts_ok || fail 'Liberation Sans konnte nicht validiert werden.'; fonts_status=installed; fi
if ((shellcheck)) && [[ "$shellcheck_status" == missing ]]; then install_one "$shellcheck_package"; shellcheck_ok || fail 'ShellCheck konnte nicht validiert werden.'; shellcheck_status=installed; fi
if ((browser_blocked)); then
  [[ "$format" == json ]] && json || { printf '%s\n' 'Linux-Setup teilweise abgeschlossen; Chromium bleibt manuell erforderlich.'; state; }
  printf '%s\n' 'Ubuntu bietet für Chromium nur eine Snap-Transition an. Gemäß Projektvertrag wird Snap nicht automatisch installiert; bitte Chromium aus einer von dir freigegebenen nativen Quelle bereitstellen und danach erneut diagnostizieren.' >&2
  exit "$EXIT_USAGE_OR_PLATFORM"
fi
[[ "$format" == json ]] && json || { printf '%s\n' 'Linux-Setup erfolgreich abgeschlossen.'; state; }
