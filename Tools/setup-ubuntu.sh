#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXIT_RUNTIME_ERROR=1
readonly EXIT_USAGE_OR_PLATFORM=2
readonly MICROSOFT_REPOSITORY_URL='https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb'
readonly GOOGLE_SIGNING_KEY_URL='https://dl.google.com/linux/linux_signing_key.pub'
readonly GOOGLE_REPOSITORY_LINE='deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main'

install_runtime=0
install_browser=0
install_fonts=0
dry_run=0
assume_yes=0
setup_tmp_dir=''
apt_updated=0
runtime_status='nicht_angefordert'
browser_status='nicht_angefordert'
fonts_status='nicht_angefordert'

usage() {
  printf '%s\n' \
    'Verwendung: setup-ubuntu.sh [AUSWAHL] [OPTIONEN]' \
    '' \
    'Opt-in-Einrichtung für Ubuntu 24.04 x86_64. Ohne Auswahl wird nichts verändert.' \
    '' \
    'Auswahl:' \
    '  --runtime          PowerShell 7.6 LTS aus der Microsoft-Paketquelle' \
    '  --browser chrome   Google Chrome Stable aus der Google-Paketquelle' \
    '  --fonts            fonts-liberation2 aus der Ubuntu-Paketquelle' \
    '  --all              Runtime, Chrome und Fonts' \
    '' \
    'Optionen:' \
    '  --dry-run          Geplante Änderungen nur anzeigen' \
    '  --yes              Bestätigung für Systemänderungen vorab erteilen' \
    '  -h, --help         Diese Hilfe anzeigen'
}

die_usage() {
  printf 'FEHLER: %s\n' "$1" >&2
  usage >&2
  exit "$EXIT_USAGE_OR_PLATFORM"
}

cleanup() {
  if [[ -n "$setup_tmp_dir" && -d "$setup_tmp_dir" ]]; then
    rm -f -- \
      "$setup_tmp_dir/packages-microsoft-prod.deb" \
      "$setup_tmp_dir/google-linux-signing-key.pub" \
      "$setup_tmp_dir/google-chrome.gpg" \
      "$setup_tmp_dir/google-chrome.list"
    rmdir -- "$setup_tmp_dir" 2>/dev/null || true
  fi
}

report_partial_state() {
  printf '%s\n' \
    "Erreichter Teilzustand:" \
    "  PowerShell: $runtime_status" \
    "  Chrome:     $browser_status" \
    "  Fonts:      $fonts_status" >&2
}

die_runtime() {
  printf 'FEHLER: %s\n' "$1" >&2
  report_partial_state
  exit "$EXIT_RUNTIME_ERROR"
}

on_error() {
  local line_number=$1
  local command_status=$2
  printf 'FEHLER: Ubuntu-Setup schlug in Zeile %s fehl (Status %s).\n' "$line_number" "$command_status" >&2
  report_partial_state
  exit "$EXIT_RUNTIME_ERROR"
}

trap cleanup EXIT
trap 'on_error "$LINENO" "$?"' ERR

while (($# > 0)); do
  case "$1" in
    --runtime)
      install_runtime=1
      shift
      ;;
    --browser)
      (($# >= 2)) || die_usage '--browser benötigt den Wert chrome.'
      [[ "$2" == 'chrome' ]] || die_usage "Nicht unterstützter Browser: $2"
      install_browser=1
      shift 2
      ;;
    --browser=chrome)
      install_browser=1
      shift
      ;;
    --browser=*)
      die_usage "Nicht unterstützter Browser: ${1#*=}"
      ;;
    --fonts)
      install_fonts=1
      shift
      ;;
    --all)
      install_runtime=1
      install_browser=1
      install_fonts=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --yes)
      assume_yes=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      (($# == 0)) || die_usage 'Positionsargumente sind nicht zulässig.'
      ;;
    *)
      die_usage "Unbekannte Option: $1"
      ;;
  esac
done

if ((install_runtime == 0 && install_browser == 0 && install_fonts == 0)); then
  usage
  exit 0
fi

read_os_release_value() {
  local key=$1
  local value
  value=$(sed -n "s/^${key}=//p" /etc/os-release | head -n 1)
  if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
    value=${value:1:${#value}-2}
  fi
  printf '%s' "$value"
}

if [[ ! -r /etc/os-release ]]; then
  printf 'FEHLER: /etc/os-release fehlt; unterstützt wird ausschließlich Ubuntu 24.04 x86_64.\n' >&2
  exit "$EXIT_USAGE_OR_PLATFORM"
fi

distribution_id=$(read_os_release_value ID)
distribution_version=$(read_os_release_value VERSION_ID)
architecture=$(uname -m)
if [[ "$distribution_id" != 'ubuntu' || "$distribution_version" != '24.04' || "$architecture" != 'x86_64' ]]; then
  printf 'FEHLER: Nicht unterstützte Plattform: ID=%s VERSION_ID=%s ARCH=%s; erforderlich ist Ubuntu 24.04 x86_64.\n' \
    "$distribution_id" "$distribution_version" "$architecture" >&2
  exit "$EXIT_USAGE_OR_PLATFORM"
fi

runtime_ok() {
  command -v pwsh >/dev/null 2>&1 &&
    pwsh -NoLogo -NoProfile -NonInteractive -Command \
      'if ($PSVersionTable.PSEdition -eq "Core" -and $PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -eq 6) { exit 0 } else { exit 1 }' \
      >/dev/null 2>&1
}

browser_ok() {
  command -v google-chrome-stable >/dev/null 2>&1 &&
    google-chrome-stable --version 2>/dev/null | grep -Eq '^Google Chrome [0-9]+([.][0-9]+){1,3}'
}

fonts_ok() {
  if [[ -f /usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf ||
        -f /usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf ]]; then
    return 0
  fi
  if command -v fc-match >/dev/null 2>&1; then
    local family
    family=$(fc-match --format='%{family}' 'Liberation Sans' 2>/dev/null || true)
    [[ "$family" == *'Liberation Sans'* ]]
    return
  fi
  return 1
}

runtime_needed=0
browser_needed=0
fonts_needed=0
if ((install_runtime == 1)); then
  if runtime_ok; then runtime_status='bereits_vorhanden'; else runtime_status='ausstehend'; runtime_needed=1; fi
fi
if ((install_browser == 1)); then
  if browser_ok; then browser_status='bereits_vorhanden'; else browser_status='ausstehend'; browser_needed=1; fi
fi
if ((install_fonts == 1)); then
  if fonts_ok; then fonts_status='bereits_vorhanden'; else fonts_status='ausstehend'; fonts_needed=1; fi
fi

printf '%s\n' 'Geplante Systemänderungen:'
if ((runtime_needed == 1)); then
  printf '%s\n' \
    '  - Microsoft-Paketquelle für Ubuntu 24.04 registrieren, falls erforderlich.' \
    '  - Neueste verfügbare PowerShell-Version 7.6.x aus dieser Quelle installieren.'
elif ((install_runtime == 1)); then
  printf '%s\n' '  - PowerShell 7.6 ist bereits vorhanden; keine Änderung.'
fi
if ((browser_needed == 1)); then
  printf '%s\n' \
    '  - Offiziellen Google-Signaturschlüssel und die Chrome-APT-Quelle registrieren.' \
    '  - google-chrome-stable installieren.'
elif ((install_browser == 1)); then
  printf '%s\n' '  - Google Chrome Stable ist bereits vorhanden; keine Änderung.'
fi
if ((fonts_needed == 1)); then
  printf '%s\n' '  - Ubuntu-Paket fonts-liberation2 installieren.'
elif ((install_fonts == 1)); then
  printf '%s\n' '  - Liberation Sans ist bereits vorhanden; keine Änderung.'
fi
if ((runtime_needed == 1 || browser_needed == 1)); then
  printf '%s\n' '  - Erforderliche APT-/HTTPS-/Signaturwerkzeuge installieren oder aktualisieren.'
fi

if ((runtime_needed == 0 && browser_needed == 0 && fonts_needed == 0)); then
  printf '%s\n' 'Alle ausgewählten Komponenten sind bereits passend installiert.'
  exit 0
fi

if ((dry_run == 1)); then
  printf '%s\n' 'Dry-run abgeschlossen; es wurde nichts verändert.'
  exit 0
fi

if ((assume_yes == 0)); then
  if [[ ! -t 0 ]]; then
    printf '%s\n' 'FEHLER: Keine interaktive Eingabe verfügbar. Nach Prüfung der Liste mit --yes erneut starten.' >&2
    exit "$EXIT_USAGE_OR_PLATFORM"
  fi
  printf 'Diese Systemänderungen jetzt ausführen? [j/N] '
  read -r confirmation
  case "$confirmation" in
    j|J|ja|JA|Ja|y|Y|yes|YES|Yes) ;;
    *)
      printf '%s\n' 'Setup wurde ohne Änderungen abgebrochen.'
      exit "$EXIT_RUNTIME_ERROR"
      ;;
  esac
fi

if ((EUID == 0)); then
  sudo_command=()
elif command -v sudo >/dev/null 2>&1; then
  sudo_command=(sudo --)
else
  die_runtime 'Für Systemänderungen sind Root-Rechte oder sudo erforderlich.'
fi

as_root() {
  "${sudo_command[@]}" "$@"
}

ensure_apt_updated() {
  if ((apt_updated == 0)); then
    as_root apt-get update
    apt_updated=1
  fi
}

setup_tmp_dir=$(mktemp -d -t bewerbungs-agent-setup.XXXXXXXX)
if [[ ! "$setup_tmp_dir" =~ ^/[^[:cntrl:]]*/bewerbungs-agent-setup\.[A-Za-z0-9]+$ || -L "$setup_tmp_dir" ]]; then
  die_runtime "Unsicheres temporäres Verzeichnis wurde verweigert: $setup_tmp_dir"
fi

if ((runtime_needed == 1 || browser_needed == 1)); then
  ensure_apt_updated
  as_root apt-get install -y ca-certificates curl gnupg apt-transport-https
fi

if ((runtime_needed == 1)); then
  if ! apt-cache madison powershell 2>/dev/null | awk '{print $3}' | grep -Eq '^7[.]6[.][0-9]+-[0-9]+[.]deb$'; then
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
      "$MICROSOFT_REPOSITORY_URL" --output "$setup_tmp_dir/packages-microsoft-prod.deb"
    dpkg-deb --info "$setup_tmp_dir/packages-microsoft-prod.deb" >/dev/null
    as_root dpkg -i "$setup_tmp_dir/packages-microsoft-prod.deb"
    runtime_status='paketquelle_registriert'
    apt_updated=0
    ensure_apt_updated
  fi

  powershell_package_version=$(
    apt-cache madison powershell 2>/dev/null |
      awk '{print $3}' |
      grep -E '^7[.]6[.][0-9]+-[0-9]+[.]deb$' |
      sort -V |
      tail -n 1 || true
  )
  if [[ ! "$powershell_package_version" =~ ^7\.6\.[0-9]+-[0-9]+\.deb$ ]]; then
    die_runtime 'Microsoft-Paketquelle bietet keine validierbare PowerShell-7.6-Version an.'
  fi
  as_root apt-get install -y --allow-downgrades "powershell=$powershell_package_version"
  runtime_status='paket_installiert_validierung_ausstehend'
  runtime_ok || {
    die_runtime 'Installierte PowerShell meldet nicht Core 7.6.x.'
  }
  runtime_status='installiert'
fi

if ((browser_needed == 1)); then
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    "$GOOGLE_SIGNING_KEY_URL" --output "$setup_tmp_dir/google-linux-signing-key.pub"
  gpg --batch --yes --dearmor \
    --output "$setup_tmp_dir/google-chrome.gpg" \
    "$setup_tmp_dir/google-linux-signing-key.pub"
  gpg --batch --show-keys "$setup_tmp_dir/google-chrome.gpg" >/dev/null
  printf '%s\n' "$GOOGLE_REPOSITORY_LINE" > "$setup_tmp_dir/google-chrome.list"
  as_root install -m 0644 "$setup_tmp_dir/google-chrome.gpg" /usr/share/keyrings/google-chrome.gpg
  as_root install -m 0644 "$setup_tmp_dir/google-chrome.list" /etc/apt/sources.list.d/google-chrome.list
  browser_status='paketquelle_registriert'
  apt_updated=0
  ensure_apt_updated
  as_root apt-get install -y google-chrome-stable
  browser_status='paket_installiert_validierung_ausstehend'
  browser_ok || {
    die_runtime 'Google Chrome Stable konnte nach der Installation nicht validiert werden.'
  }
  browser_status='installiert'
fi

if ((fonts_needed == 1)); then
  ensure_apt_updated
  as_root apt-get install -y fonts-liberation2
  fonts_status='paket_installiert_validierung_ausstehend'
  fonts_ok || {
    die_runtime 'Liberation Sans konnte nach der Installation nicht validiert werden.'
  }
  fonts_status='installiert'
fi

printf '%s\n' \
  'Ubuntu-Setup erfolgreich abgeschlossen.' \
  "  PowerShell: $runtime_status" \
  "  Chrome:     $browser_status" \
  "  Fonts:      $fonts_status"
