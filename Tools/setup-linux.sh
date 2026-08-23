#!/usr/bin/env bash
set -euo pipefail

script_source="${BASH_SOURCE[0]}"
if [[ "$script_source" == */* ]]; then script_parent="${script_source%/*}"; else script_parent=.; fi
script_dir="$(cd -- "$script_parent" && pwd -P)"
readonly script_dir
readonly python_setup="$script_dir/setup-linux.py"
readonly minimum_python='3.9'
readonly exit_runtime_error=1
readonly exit_usage_or_platform=2
original_args=("$@")

usage() {
  printf '%s\n' \
    'Verwendung: setup-linux.sh [AUSWAHL] [OPTIONEN]' \
    '  --runtime             System-Python 3.9 oder neuer' \
    '  --browser chromium    Chromium aus der Distribution' \
    '  --fonts               Liberation Sans aus der Distribution' \
    '  --shellcheck          ShellCheck aus der Distribution' \
    '  --all                 alle deklarierten Komponenten' \
    '  --dry-run             geplante Änderungen nur anzeigen' \
    '  --yes                 bestätigte Änderungen ausführen' \
    '  --format text|json    Ausgabeformat'
}

python_is_usable() {
  "$1" -I -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) and sys.prefix == getattr(sys, "base_prefix", sys.prefix) else 1)' >/dev/null 2>&1
}

find_system_python() {
  local candidate resolved
  for candidate in /usr/bin/python3 /bin/python3 /usr/local/bin/python3 /usr/bin/python /bin/python; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    resolved="$candidate"
    if python_is_usable "$resolved"; then
      printf '%s' "$resolved"
      return 0
    fi
  done
  return 1
}

find_system_command() {
  local name="$1" candidate
  for candidate in "/usr/bin/$name" "/usr/sbin/$name" "/bin/$name" "/sbin/$name"; do
    if [[ -f "$candidate" && -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

if system_python="$(find_system_python)"; then
  exec "$system_python" "$python_setup" "${original_args[@]}"
fi

# Ab hier fehlt die Kernruntime. Bash validiert ausschließlich die gemeinsamen
# Setup-Optionen und darf nur System-Python installieren. Alle weitere Logik
# liegt nach erfolgreichem Bootstrap in setup-linux.py.
runtime_selected=0
browser_selected=0
fonts_selected=0
shellcheck_selected=0
all_selected=0
selection_seen=0
dry_run=0
assume_yes=0
output_format=text

while (($#)); do
  case "$1" in
    --runtime)
      runtime_selected=1; selection_seen=1; shift ;;
    --browser)
      (($# > 1)) || { printf '%s\n' 'FEHLER: --browser benötigt chromium.' >&2; exit "$exit_usage_or_platform"; }
      [[ "$2" == chromium ]] || { printf 'FEHLER: Nicht unterstützter Browser: %s\n' "$2" >&2; exit "$exit_usage_or_platform"; }
      browser_selected=1; selection_seen=1; shift 2 ;;
    --browser=chromium)
      browser_selected=1; selection_seen=1; shift ;;
    --browser=*)
      printf 'FEHLER: Nicht unterstützter Browser: %s\n' "${1#*=}" >&2; exit "$exit_usage_or_platform" ;;
    --fonts)
      fonts_selected=1; selection_seen=1; shift ;;
    --shellcheck)
      shellcheck_selected=1; selection_seen=1; shift ;;
    --all)
      runtime_selected=1; browser_selected=1; fonts_selected=1; shellcheck_selected=1; all_selected=1; selection_seen=1; shift ;;
    --dry-run)
      dry_run=1; shift ;;
    --yes)
      assume_yes=1; shift ;;
    --format)
      (($# > 1)) || { printf '%s\n' 'FEHLER: --format benötigt text oder json.' >&2; exit "$exit_usage_or_platform"; }
      output_format="$2"; shift 2 ;;
    --format=text|--format=json)
      output_format="${1#*=}"; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      printf 'FEHLER: Unbekannte Option: %s\n' "$1" >&2; usage >&2; exit "$exit_usage_or_platform" ;;
  esac
done

[[ "$output_format" == text || "$output_format" == json ]] || {
  printf 'FEHLER: Nicht unterstütztes Format: %s\n' "$output_format" >&2
  exit "$exit_usage_or_platform"
}
((selection_seen)) || { usage; exit 0; }
if ((runtime_selected == 0)); then
  printf 'FEHLER: System-Python %s oder neuer fehlt. Zuerst ausführen: ./Tools/setup-linux.sh --runtime --dry-run\n' "$minimum_python" >&2
  exit "$exit_usage_or_platform"
fi
[[ -r /etc/os-release ]] || { printf '%s\n' 'FEHLER: /etc/os-release fehlt.' >&2; exit "$exit_usage_or_platform"; }
[[ "$(uname -m)" == x86_64 ]] || { printf '%s\n' 'FEHLER: Nur Linux x86_64 wird unterstützt.' >&2; exit "$exit_usage_or_platform"; }

# /etc/os-release ist eine rootverwaltete Betriebssystemdatei und verwendet
# bewusst Shell-kompatible Zuweisungen.
# shellcheck disable=SC1091
. /etc/os-release
distro="${ID:-unknown}"
distro_version="${VERSION_ID:-unknown}"
[[ "$distro" =~ ^[A-Za-z0-9._-]+$ ]] || distro=unknown
[[ "$distro_version" =~ ^[A-Za-z0-9._-]+$ ]] || distro_version=unknown

manager=''
manager_executable=''
runtime_package=''
browser_package=''
fonts_package=''
shellcheck_package=''
source_name=''
if manager_executable="$(find_system_command apt-get)"; then manager=apt; runtime_package=python3; browser_package=chromium; fonts_package=fonts-liberation2; shellcheck_package=shellcheck; source_name=APT
elif manager_executable="$(find_system_command dnf)"; then manager=dnf; runtime_package=python3; browser_package=chromium; fonts_package=liberation-sans-fonts; shellcheck_package=ShellCheck; source_name=DNF
elif manager_executable="$(find_system_command yum)"; then manager=yum; runtime_package=python3; browser_package=chromium; fonts_package=liberation-sans-fonts; shellcheck_package=ShellCheck; source_name=YUM
elif manager_executable="$(find_system_command pacman)"; then manager=pacman; runtime_package=python; browser_package=chromium; fonts_package=ttf-liberation; shellcheck_package=shellcheck; source_name=Pacman
elif manager_executable="$(find_system_command zypper)"; then manager=zypper; runtime_package=python3; browser_package=chromium; fonts_package=liberation-fonts; shellcheck_package=ShellCheck; source_name=Zypper
else
  printf 'FEHLER: Kein unterstützter Paketmanager erkannt. Installiere System-Python %s oder neuer manuell und starte erneut.\n' "$minimum_python" >&2
  exit "$exit_usage_or_platform"
fi

bool_json() { if (($1)); then printf true; else printf false; fi; }
deferred_action() { if (($1)); then printf deferred; else printf none; fi; }
runtime_json="$(bool_json "$runtime_selected")"
browser_json="$(bool_json "$browser_selected")"
fonts_json="$(bool_json "$fonts_selected")"
shellcheck_json="$(bool_json "$shellcheck_selected")"
browser_action="$(deferred_action "$browser_selected")"
fonts_action="$(deferred_action "$fonts_selected")"
shellcheck_action="$(deferred_action "$shellcheck_selected")"
bootstrap_apply_command='./Tools/setup-linux.sh'
if ((all_selected)); then
  bootstrap_apply_command+=' --all'
else
  ((runtime_selected)) && bootstrap_apply_command+=' --runtime'
  ((browser_selected)) && bootstrap_apply_command+=' --browser chromium'
  ((fonts_selected)) && bootstrap_apply_command+=' --fonts'
  ((shellcheck_selected)) && bootstrap_apply_command+=' --shellcheck'
fi
bootstrap_apply_command+=' --yes'
[[ "$output_format" == json ]] && bootstrap_apply_command+=' --format json'

emit_bootstrap_json() {
  local status="$1" action="$2" dry_json=false
  ((dry_run)) && dry_json=true
  local pacman_upgrade=false pacman_detail='Es werden nur die aufgeführten Distributionspakete installiert.'
  if [[ "$manager" == pacman ]]; then pacman_upgrade=true; pacman_detail='Der erste Pacman-Lauf synchronisiert Paketdaten und aktualisiert das vollständige System (-Syu), bevor Python installiert wird.'; fi
  printf '{"schemaVersion":2,"kind":"linux_setup_plan","status":"%s","platform":{"id":"%s","version":"%s","architecture":"x86_64"},"packageManager":"%s","packageManagerPath":"%s","coreRuntime":{"selected":%s,"platform":"linux","language":"python","minimumVersion":"%s","setupCommand":"./Tools/setup-linux.sh --runtime --dry-run --format json","status":"missing","version":null,"path":null,"packages":["%s"],"source":"%s-Distribution","permission":"root-or-sudo","installable":true,"blocked":false,"plannedAction":"%s"},"dependencies":{"browser":{"selected":%s,"status":"not_evaluated","packages":["%s"],"source":"%s-Distribution","permission":"root-or-sudo","plannedAction":"%s"},"fonts":{"selected":%s,"status":"not_evaluated","packages":["%s"],"source":"%s-Distribution","permission":"root-or-sudo","plannedAction":"%s"},"shellcheck":{"selected":%s,"status":"not_evaluated","packages":["%s"],"source":"%s-Distribution","permission":"root-or-sudo","plannedAction":"%s"}},"plannedChanges":[{"component":"coreRuntime","action":"install","packages":["%s"],"source":"%s-Distribution","permission":"root-or-sudo","includesFullSystemUpgrade":%s}],"manualActions":[],"changesRequired":true,"manualActionRequired":false,"requiresPrivilege":true,"packageManagerOperation":{"refreshMetadata":true,"fullSystemUpgrade":%s,"detail":"%s"},"applyCommand":"%s","dryRun":%s}\n' \
    "$status" "$distro" "$distro_version" "$manager" "$manager_executable" "$runtime_json" "$minimum_python" "$runtime_package" "$source_name" "$action" \
    "$browser_json" "$browser_package" "$source_name" "$browser_action" "$fonts_json" "$fonts_package" "$source_name" "$fonts_action" "$shellcheck_json" "$shellcheck_package" "$source_name" "$shellcheck_action" \
    "$runtime_package" "$source_name" "$pacman_upgrade" "$pacman_upgrade" "$pacman_detail" "$bootstrap_apply_command" "$dry_json"
}

emit_bootstrap_plan() {
  printf '%s\n' \
    'Geplante Python-Bootstrap-Änderung:' \
    "  Plattform: $distro $distro_version (x86_64)" \
    "  Paketmanager: $manager ($manager_executable)" \
    "  Python: missing | Paket=$runtime_package | Quelle=$source_name-Distribution | Rechte=Root/sudo | Änderung=install" \
    '  Nach erfolgreichem Bootstrap delegiert Bash alle ausgewählten Komponenten an setup-linux.py.' \
    "  Sicherer Setup-Befehl: $bootstrap_apply_command"
  if [[ "$manager" == pacman ]]; then printf '%s\n' '  Pacman: vollständige Systemaktualisierung mit -Syu vor der Python-Installation.'; fi
}

if ((dry_run)); then
  if [[ "$output_format" == json ]]; then emit_bootstrap_json planned install; else emit_bootstrap_plan; printf '%s\n' 'Dry-run abgeschlossen; es wurde nichts verändert.'; fi
  exit 0
fi

if [[ "$output_format" == text ]]; then emit_bootstrap_plan; else printf '%s\n' 'Python-Bootstrap: Paketplan geprüft; Paketinstallation folgt.' >&2; fi
if ((assume_yes == 0)); then
  [[ -t 0 ]] || {
    printf '%s\n' 'FEHLER: Keine interaktive Eingabe verfügbar; nach Prüfung mit --yes erneut starten.' >&2
    exit "$exit_usage_or_platform"
  }
  printf 'Diese Änderung jetzt ausführen? [j/N] '
  read -r answer
  case "${answer,,}" in
    j|ja|y|yes) ;;
    *)
      [[ "$output_format" == json ]] && emit_bootstrap_json cancelled install
      printf '%s\n' 'Setup wurde ohne Änderungen abgebrochen.' >&2
      exit "$exit_runtime_error" ;;
  esac
fi

if ((EUID == 0)); then
  run_root() { "$@"; }
elif sudo_path="$(find_system_command sudo)"; then
  run_root() { "$sudo_path" -- "$@"; }
else
  [[ "$output_format" == json ]] && emit_bootstrap_json failed install
  printf '%s\n' 'FEHLER: Für Systemänderungen sind Root-Rechte oder sudo erforderlich. Teilzustand: Python fehlt weiterhin.' >&2
  exit "$exit_runtime_error"
fi

install_failed=0
case "$manager" in
  apt)
    # Metadatenaktualisierung und Installation verwenden denselben
    # Root-/sudo-Wrapper. Dadurch kann kein unprivilegierter APT-Lockfehler
    # zwischen Plan und Installation entstehen.
    run_root "$manager_executable" update || install_failed=1
    if ((install_failed == 0)); then run_root "$manager_executable" install --yes --no-install-recommends "$runtime_package" || install_failed=1; fi ;;
  dnf|yum)
    run_root "$manager_executable" install -y "$runtime_package" || install_failed=1 ;;
  pacman)
    run_root "$manager_executable" -Syu --noconfirm --needed "$runtime_package" || install_failed=1 ;;
  zypper)
    run_root "$manager_executable" --non-interactive install --no-recommends "$runtime_package" || install_failed=1 ;;
esac

if ((install_failed)); then
  [[ "$output_format" == json ]] && emit_bootstrap_json failed install
  printf '%s\n' 'FEHLER: Python-Paketinstallation fehlgeschlagen. Teilzustand: Python ist nicht validiert; weitere Komponenten wurden nicht verändert.' >&2
  exit "$exit_runtime_error"
fi
if ! system_python="$(find_system_python)"; then
  [[ "$output_format" == json ]] && emit_bootstrap_json failed install
  printf 'FEHLER: Das Distributionspaket stellt kein System-Python %s oder neuer bereit. Teilzustand: Paketbefehl war erfolgreich, Runtime-Validierung ist fehlgeschlagen.\n' "$minimum_python" >&2
  exit "$exit_runtime_error"
fi

printf 'Python-Bootstrap validiert: %s (%s)\n' "${minimum_python}+" "$system_python" >&2
exec "$system_python" "$python_setup" "${original_args[@]}"
