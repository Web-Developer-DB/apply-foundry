#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
dispatcher="$script_dir/bewerbung.ps1"

if [[ ! -f "$dispatcher" ]]; then
  printf 'Fehler: PowerShell-Dispatcher fehlt: %s\n' "$dispatcher" >&2
  exit 1
fi

if ! pwsh_path="$(command -v pwsh 2>/dev/null)" || [[ -z "$pwsh_path" ]]; then
  printf 'Fehler: PowerShell 7.6 oder neuer ist erforderlich; pwsh wurde nicht gefunden.\n' >&2
  exit 2
fi

# shellcheck disable=SC2016 # PowerShell variables must remain literal here.
if ! pwsh_version="$("$pwsh_path" -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>/dev/null)"; then
  printf 'Fehler: Die installierte PowerShell-Version konnte nicht ermittelt werden.\n' >&2
  exit 2
fi
pwsh_version="${pwsh_version//$'\r'/}"

if [[ ! "$pwsh_version" =~ ^([0-9]+)\.([0-9]+)(\.[0-9]+)?([.-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'Fehler: Unbekanntes PowerShell-Versionsformat: %s\n' "$pwsh_version" >&2
  exit 2
fi

pwsh_major="${BASH_REMATCH[1]}"
pwsh_minor="${BASH_REMATCH[2]}"
if ((pwsh_major < 7 || (pwsh_major == 7 && pwsh_minor < 6))); then
  printf 'Fehler: PowerShell 7.6 oder neuer ist erforderlich; gefunden wurde %s.\n' "$pwsh_version" >&2
  exit 2
fi

exec "$pwsh_path" -NoLogo -NoProfile -NonInteractive -File "$dispatcher" "$@"
