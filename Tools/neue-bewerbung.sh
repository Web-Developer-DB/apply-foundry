#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'EOF'
Usage:
  bash Tools/neue-bewerbung.sh --firma "Muster GmbH" [options]

Options:
  --firma NAME                    Firmenname, Pflichtangabe
  --rolle NAME                    Zielrolle, Standard: Bewerbung
  --umfang A|B|C|D|E              Vom Nutzer festgelegter Bewerbungsumfang
  --dokumente LISTE               Nur für E: lebenslauf,anschreiben,email_nachricht
  --dokumentmodus MODUS           Legacy-Direktwahl: vollbewerbung, anschreiben_mit_universalem_lebenslauf oder individuelle_auswahl
  --umfang-quelle QUELLE          auswahl (Standard), direkter_auftrag oder fortgesetzter_auftrag
  --email-allein-bestaetigt       Bestätigung für einen reinen E-Mail-Auftrag ohne Anlagen
  --universal-lebenslauf-path PATH Freigegebene HTML-Quelle für den Anschreiben-Modus
  --datum YYYY-MM-DD              Datum, Standard: heute
  --stellenbeschreibung-path PATH Pfad zu vorhandener Stellenbeschreibung
  --stammdaten-path PATH           Stammdaten für den Logistik-Snapshot
  --profil-path PATH               Profil für den Quellhash
  --bewerbungen-root PATH         Ausgabeordner, Standard: ./Private/Bewerbungen
  --fortsetzen                    Nur exakt dieselbe vorhandene Bewerbung ergänzen
  -h, --help                      Hilfe anzeigen
EOF
}

convert_to_slug() {
  local slug="$1"

  slug="${slug#"${slug%%[![:space:]]*}"}"
  slug="${slug%"${slug##*[![:space:]]}"}"

  slug="${slug//ä/ae}"
  slug="${slug//ö/oe}"
  slug="${slug//ü/ue}"
  slug="${slug//Ä/Ae}"
  slug="${slug//Ö/Oe}"
  slug="${slug//Ü/Ue}"
  slug="${slug//ß/ss}"
  slug="${slug//&/und}"

  slug="$(printf '%s' "$slug" | sed -E 's/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//')"

  if [[ -z "$slug" ]]; then
    printf 'Unbekannt'
  else
    printf '%s' "$slug"
  fi
}

html_escape() {
  local value="$1"
  local escaped=""
  local char
  local index

  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    case "$char" in
      '&') escaped+='&amp;' ;;
      '<') escaped+='&lt;' ;;
      '>') escaped+='&gt;' ;;
      '"') escaped+='&quot;' ;;
      "'") escaped+='&#39;' ;;
      *) escaped+="$char" ;;
    esac
  done

  printf '%s' "$escaped"
}

json_escape() {
  local value="$1"
  local escaped=""
  local char
  local codepoint
  local encoded
  local index

  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    case "$char" in
      '"') escaped+='\"' ;;
      \\) escaped+=$'\\\\' ;;
      $'\b') escaped+='\b' ;;
      $'\f') escaped+='\f' ;;
      $'\n') escaped+='\n' ;;
      $'\r') escaped+='\r' ;;
      $'\t') escaped+='\t' ;;
      *)
        if [[ "$char" == [[:cntrl:]] ]]; then
          printf -v codepoint '%d' "'$char"
          printf -v encoded '\\u%04x' "$codepoint"
          escaped+="$encoded"
        else
          escaped+="$char"
        fi
        ;;
    esac
  done

  printf '%s' "$escaped"
}

markdown_field() {
  local path="$1"
  local field="$2"
  [[ -f "$path" ]] || return 0
  sed -n -E "s/^[[:space:]]*-[[:space:]]*${field}:[[:space:]]*(.*)$/\\1/p" "$path" | head -n 1 | sed $'s/\r$//'
}

select_json_tool() {
  json_tool=""
  if command -v jq >/dev/null 2>&1 && jq --version >/dev/null 2>&1; then
    json_tool="jq"
  elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then
    json_tool="python3"
  elif command -v python >/dev/null 2>&1 && python -c 'import json, sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
    json_tool="python"
  elif command -v node >/dev/null 2>&1 && node -e 'JSON.parse("{}")' >/dev/null 2>&1; then
    json_tool="node"
  # shellcheck disable=SC2016 # PowerShell variables must remain literal here.
  elif command -v pwsh >/dev/null 2>&1 && pwsh -NoLogo -NoProfile -NonInteractive -Command '$null = "{}" | ConvertFrom-Json' >/dev/null 2>&1; then
    json_tool="pwsh"
  fi
}

validate_json_file() {
  local path="$1"
  case "$json_tool" in
    jq)
      jq -e . "$path" >/dev/null 2>&1
      ;;
    python3|python)
      "$json_tool" -c 'import json, sys; json.load(open(sys.argv[1], "r", encoding="utf-8-sig"))' "$path" >/dev/null 2>&1
      ;;
    node)
      node -e 'const fs = require("fs"); JSON.parse(fs.readFileSync(process.argv[1], "utf8").replace(/^\uFEFF/, ""));' "$path" >/dev/null 2>&1
      ;;
    pwsh)
      # shellcheck disable=SC2016 # PowerShell variables must remain literal here.
      JSON_PATH="$path" pwsh -NoLogo -NoProfile -NonInteractive -Command '$text = Get-Content -LiteralPath $env:JSON_PATH -Raw -Encoding UTF8; $null = $text | ConvertFrom-Json -ErrorAction Stop' >/dev/null 2>&1
      ;;
    *)
      return 2
      ;;
  esac
}

json_get_scalar() {
  local path="$1"
  local query="$2"
  case "$json_tool" in
    jq)
      jq -er --arg path "$query" '
        reduce ($path | split("."))[] as $key (.;
          if type == "object" and has($key) then .[$key] else error("missing") end
        )
        | if type == "string" then .
          elif type == "boolean" or type == "number" then tostring
          elif . == null then "null"
          else error("not scalar")
          end
      ' "$path"
      ;;
    python3|python)
      "$json_tool" -c '
import json, sys
with open(sys.argv[1], "r", encoding="utf-8-sig") as handle:
    value = json.load(handle)
for key in sys.argv[2].split("."):
    if not isinstance(value, dict) or key not in value:
        raise KeyError(key)
    value = value[key]
if isinstance(value, bool):
    text = "true" if value else "false"
elif value is None:
    text = "null"
elif isinstance(value, (str, int, float)):
    text = str(value)
else:
    raise TypeError("not scalar")
sys.stdout.write(text)
' "$path" "$query"
      ;;
    node)
      node -e '
const fs = require("fs");
let value = JSON.parse(fs.readFileSync(process.argv[1], "utf8").replace(/^\uFEFF/, ""));
for (const key of process.argv[2].split(".")) {
  if (value === null || typeof value !== "object" || Array.isArray(value) || !Object.prototype.hasOwnProperty.call(value, key)) process.exit(3);
  value = value[key];
}
if (value === null) process.stdout.write("null");
else if (["string", "number", "boolean"].includes(typeof value)) process.stdout.write(String(value));
else process.exit(4);
' "$path" "$query"
      ;;
    pwsh)
      # shellcheck disable=SC2016 # PowerShell variables must remain literal here.
      JSON_PATH="$path" JSON_QUERY="$query" pwsh -NoLogo -NoProfile -NonInteractive -Command '
$value = (Get-Content -LiteralPath $env:JSON_PATH -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
foreach ($segment in $env:JSON_QUERY.Split(".")) {
  $property = $value.PSObject.Properties[$segment]
  if ($null -eq $property) { exit 3 }
  $value = $property.Value
}
if ($value -is [bool]) { [Console]::Out.Write($value.ToString().ToLowerInvariant()) }
elseif ($null -eq $value) { [Console]::Out.Write("null") }
elseif ($value -is [string] -or $value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) { [Console]::Out.Write([string]$value) }
else { exit 4 }
'
      ;;
    *)
      return 2
      ;;
  esac
}

json_get_type() {
  local path="$1"
  local query="$2"
  case "$json_tool" in
    jq)
      jq -er --arg path "$query" '
        reduce ($path | split("."))[] as $key (.;
          if type == "object" and has($key) then .[$key] else error("missing") end
        )
        | if type == "boolean" then "boolean"
          elif type == "number" and (. == floor) then "integer"
          elif type == "number" then "number"
          elif type == "string" then "string"
          elif . == null then "null"
          else type
          end
      ' "$path"
      ;;
    python3|python)
      "$json_tool" -c '
import json, sys
with open(sys.argv[1], "r", encoding="utf-8-sig") as handle:
    value = json.load(handle)
for key in sys.argv[2].split("."):
    if not isinstance(value, dict) or key not in value:
        raise KeyError(key)
    value = value[key]
if isinstance(value, bool):
    text = "boolean"
elif isinstance(value, int):
    text = "integer"
elif isinstance(value, float):
    text = "number"
elif isinstance(value, str):
    text = "string"
elif value is None:
    text = "null"
elif isinstance(value, list):
    text = "array"
elif isinstance(value, dict):
    text = "object"
else:
    raise TypeError("unknown JSON type")
sys.stdout.write(text)
' "$path" "$query"
      ;;
    node)
      node -e '
const fs = require("fs");
let value = JSON.parse(fs.readFileSync(process.argv[1], "utf8").replace(/^\uFEFF/, ""));
for (const key of process.argv[2].split(".")) {
  if (value === null || typeof value !== "object" || Array.isArray(value) || !Object.prototype.hasOwnProperty.call(value, key)) process.exit(3);
  value = value[key];
}
let type;
if (value === null) type = "null";
else if (Array.isArray(value)) type = "array";
else if (typeof value === "number") type = Number.isInteger(value) ? "integer" : "number";
else type = typeof value;
process.stdout.write(type);
' "$path" "$query"
      ;;
    pwsh)
      # shellcheck disable=SC2016 # PowerShell variables must remain literal here.
      JSON_PATH="$path" JSON_QUERY="$query" pwsh -NoLogo -NoProfile -NonInteractive -Command '
$value = (Get-Content -LiteralPath $env:JSON_PATH -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
foreach ($segment in $env:JSON_QUERY.Split(".")) {
  $property = $value.PSObject.Properties[$segment]
  if ($null -eq $property) { exit 3 }
  $value = $property.Value
}
if ($value -is [bool]) { [Console]::Out.Write("boolean") }
elseif ($value -is [int] -or $value -is [long]) { [Console]::Out.Write("integer") }
elseif ($value -is [double] -or $value -is [decimal]) { [Console]::Out.Write("number") }
elseif ($value -is [string]) { [Console]::Out.Write("string") }
elseif ($null -eq $value) { [Console]::Out.Write("null") }
elseif ($value -is [System.Array]) { [Console]::Out.Write("array") }
else { [Console]::Out.Write("object") }
'
      ;;
    *)
      return 2
      ;;
  esac
}

test_root_schema_integer_lexeme() {
  local path="$1"
  local expected="$2"
  LC_ALL=C awk -v expected="$expected" '
    { content = content $0 "\n" }
    END {
      sub(/^\357\273\277/, "", content)
      pattern = "^[[:space:]]*\\{[[:space:]]*\"schemaVersion\"[[:space:]]*:[[:space:]]*" expected "[[:space:]]*[,}]"
      exit(content ~ pattern ? 0 : 1)
    }
  ' "$path"
}

file_sha256() {
  local path="$1"
  local hash=""
  if [[ ! -f "$path" ]]; then
    echo "Fehler: SHA-256-Quelle fehlt oder ist keine Datei: $path" >&2
    return 2
  fi
  case "$sha256_tool" in
    sha256sum) hash="$(sha256sum -- "$path" | awk '{print toupper($1)}')" ;;
    shasum) hash="$(shasum -a 256 -- "$path" | awk '{print toupper($1)}')" ;;
    *) echo "Fehler: Kein unterstütztes SHA-256-Werkzeug ausgewählt." >&2; return 2 ;;
  esac
  if [[ ! "$hash" =~ ^[A-F0-9]{64}$ ]]; then
    echo "Fehler: Für die Datei wurde kein gültiger SHA-256-Wert erzeugt: $path" >&2
    return 2
  fi
  printf '%s' "$hash"
}

validate_date() {
  local value="$1"
  [[ "$value" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]] || return 1

  local year=$((10#${BASH_REMATCH[1]}))
  local month=$((10#${BASH_REMATCH[2]}))
  local day=$((10#${BASH_REMATCH[3]}))
  local max_day

  case "$month" in
    1|3|5|7|8|10|12) max_day=31 ;;
    4|6|9|11) max_day=30 ;;
    2)
      max_day=28
      if (( (year % 400 == 0) || (year % 4 == 0 && year % 100 != 0) )); then
        max_day=29
      fi
      ;;
    *) return 1 ;;
  esac

  ((day >= 1 && day <= max_day))
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"

firma=""
rolle="Bewerbung"
dokumentmodus=""
umfang_auswahl=""
dokumente_csv=""
umfang_quelle="auswahl"
email_allein_bestaetigt=false
universal_lebenslauf_path=""
datum="$(date +%F)"
stellenbeschreibung_path=""
stammdaten_path="$project_root/Private/Daten/01_PERSOENLICHE_DATEN.md"
profil_path="$project_root/Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
bewerbungen_root="$project_root/Private/Bewerbungen"
fortsetzen=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --firma)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --firma" >&2; exit 2; }
      firma="$2"
      shift 2
      ;;
    --rolle)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --rolle" >&2; exit 2; }
      rolle="$2"
      shift 2
      ;;
    --dokumentmodus)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --dokumentmodus" >&2; exit 2; }
      dokumentmodus="$2"
      shift 2
      ;;
    --umfang)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --umfang" >&2; exit 2; }
      umfang_auswahl="${2^^}"
      shift 2
      ;;
    --dokumente)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --dokumente" >&2; exit 2; }
      dokumente_csv="$2"
      shift 2
      ;;
    --umfang-quelle)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --umfang-quelle" >&2; exit 2; }
      umfang_quelle="$2"
      shift 2
      ;;
    --email-allein-bestaetigt)
      email_allein_bestaetigt=true
      shift
      ;;
    --universal-lebenslauf-path)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --universal-lebenslauf-path" >&2; exit 2; }
      universal_lebenslauf_path="$2"
      shift 2
      ;;
    --datum)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --datum" >&2; exit 2; }
      datum="$2"
      shift 2
      ;;
    --stellenbeschreibung-path)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --stellenbeschreibung-path" >&2; exit 2; }
      stellenbeschreibung_path="$2"
      shift 2
      ;;
    --stammdaten-path)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --stammdaten-path" >&2; exit 2; }
      stammdaten_path="$2"
      shift 2
      ;;
    --profil-path)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --profil-path" >&2; exit 2; }
      profil_path="$2"
      shift 2
      ;;
    --bewerbungen-root)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --bewerbungen-root" >&2; exit 2; }
      bewerbungen_root="$2"
      shift 2
      ;;
    --fortsetzen)
      fortsetzen=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unbekannte Option: $1" >&2
      print_usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$firma" ]]; then
  echo "Fehler: --firma ist erforderlich." >&2
  print_usage >&2
  exit 2
fi

firma="${firma#"${firma%%[![:space:]]*}"}"
firma="${firma%"${firma##*[![:space:]]}"}"
rolle="${rolle#"${rolle%%[![:space:]]*}"}"
rolle="${rolle%"${rolle##*[![:space:]]}"}"

if [[ -z "$firma" || -z "$rolle" ]]; then
  echo "Fehler: --firma und --rolle dürfen nicht leer sein." >&2
  exit 2
fi

if (( ${#firma} > 120 || ${#rolle} > 120 )); then
  echo "Fehler: Firma und Rolle dürfen jeweils höchstens 120 Zeichen lang sein." >&2
  exit 2
fi

if [[ "$firma" =~ [[:cntrl:]] || "$rolle" =~ [[:cntrl:]] ]]; then
  echo "Fehler: Firma und Rolle dürfen keine Steuerzeichen oder Zeilenumbrüche enthalten." >&2
  exit 2
fi

if ! validate_date "$datum"; then
  echo "Fehler: --datum muss ein echtes Kalenderdatum im Format YYYY-MM-DD sein." >&2
  exit 2
fi

if [[ -n "$stellenbeschreibung_path" && ! -f "$stellenbeschreibung_path" ]]; then
  echo "Fehler: --stellenbeschreibung-path muss auf eine vorhandene Datei zeigen: $stellenbeschreibung_path" >&2
  exit 2
fi

for source_path in "$stammdaten_path" "$profil_path"; do
  if [[ ! -f "$source_path" ]]; then
    echo "Fehler: Stammdaten- und Profilpfad müssen vor der Anlage auf vorhandene Dateien zeigen: $source_path" >&2
    exit 2
  fi
done

sha256_tool=""
if command -v sha256sum >/dev/null 2>&1; then
  sha256_tool="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  sha256_tool="shasum"
else
  echo "Fehler: Für belastbare Quellnachweise wird sha256sum oder shasum benötigt." >&2
  exit 2
fi

json_tool=""
select_json_tool
if [[ -z "$json_tool" ]]; then
  echo "Fehler: Für die verbindliche JSON-Prüfung wird jq, Python 3, Python, Node.js oder PowerShell 7 benötigt." >&2
  exit 2
fi

if [[ -z "$dokumentmodus" && -z "$umfang_auswahl" ]]; then
  echo "Fehler: Der Bewerbungsumfang muss vor der Ordneranlage mit --umfang A-E oder --dokumentmodus festgelegt werden." >&2
  exit 2
fi

if [[ "$umfang_quelle" != "auswahl" && "$umfang_quelle" != "direkter_auftrag" && "$umfang_quelle" != "fortgesetzter_auftrag" ]]; then
  echo "Fehler: --umfang-quelle ist ungültig." >&2
  exit 2
fi

include_cv=false
include_letter=false
include_email=false
cv_kind="nicht_enthalten"
resolved_mode=""

if [[ -n "$umfang_auswahl" ]]; then
  case "$umfang_auswahl" in
    A)
      resolved_mode="vollbewerbung"
      include_cv=true; include_letter=true; include_email=true; cv_kind="individuell"
      ;;
    B)
      resolved_mode="anschreiben_mit_universalem_lebenslauf"
      include_cv=true; include_letter=true; include_email=true; cv_kind="universal_unveraendert"
      ;;
    C)
      resolved_mode="individuelle_auswahl"
      include_cv=true; cv_kind="individuell"
      ;;
    D)
      resolved_mode="individuelle_auswahl"
      include_letter=true
      ;;
    E)
      resolved_mode="individuelle_auswahl"
      [[ -n "$dokumente_csv" ]] || { echo "Fehler: Umfang E erfordert --dokumente." >&2; exit 2; }
      IFS=',' read -r -a dokumente <<< "$dokumente_csv"
      for dokument in "${dokumente[@]}"; do
        dokument="${dokument//[[:space:]]/}"
        case "$dokument" in
          lebenslauf) include_cv=true ;;
          anschreiben) include_letter=true ;;
          email_nachricht) include_email=true ;;
          *) echo "Fehler: Unbekanntes Dokument in --dokumente: $dokument" >&2; exit 2 ;;
        esac
      done
      if [[ "$include_cv" == true ]]; then
        if [[ -n "$universal_lebenslauf_path" ]]; then cv_kind="universal_unveraendert"; else cv_kind="individuell"; fi
      fi
      ;;
    *) echo "Fehler: --umfang muss A, B, C, D oder E sein." >&2; exit 2 ;;
  esac
  if [[ "$umfang_auswahl" != "E" && -n "$dokumente_csv" ]]; then
    echo "Fehler: --dokumente ist nur für Umfang E zulässig." >&2
    exit 2
  fi
  if [[ -n "$dokumentmodus" && "$dokumentmodus" != "$resolved_mode" ]]; then
    echo "Fehler: --dokumentmodus und --umfang widersprechen sich." >&2
    exit 2
  fi
  dokumentmodus="$resolved_mode"
else
  case "$dokumentmodus" in
    vollbewerbung)
      umfang_auswahl="A"; include_cv=true; include_letter=true; include_email=true; cv_kind="individuell"
      ;;
    anschreiben_mit_universalem_lebenslauf)
      umfang_auswahl="B"; include_cv=true; include_letter=true; include_email=true; cv_kind="universal_unveraendert"
      ;;
    individuelle_auswahl)
      umfang_auswahl="E"
      [[ -n "$dokumente_csv" ]] || { echo "Fehler: individuelle_auswahl erfordert --dokumente." >&2; exit 2; }
      IFS=',' read -r -a dokumente <<< "$dokumente_csv"
      for dokument in "${dokumente[@]}"; do
        dokument="${dokument//[[:space:]]/}"
        case "$dokument" in
          lebenslauf) include_cv=true ;;
          anschreiben) include_letter=true ;;
          email_nachricht) include_email=true ;;
          *) echo "Fehler: Unbekanntes Dokument in --dokumente: $dokument" >&2; exit 2 ;;
        esac
      done
      if [[ "$include_cv" == true ]]; then
        if [[ -n "$universal_lebenslauf_path" ]]; then cv_kind="universal_unveraendert"; else cv_kind="individuell"; fi
      fi
      ;;
    *) echo "Fehler: --dokumentmodus ist ungültig." >&2; exit 2 ;;
  esac
fi

if [[ "$include_cv" == false && "$include_letter" == false && "$include_email" == false ]]; then
  echo "Fehler: Der Dokumentumfang muss mindestens ein Dokument enthalten." >&2
  exit 2
fi
if [[ "$include_email" == true && "$include_cv" == false && "$include_letter" == false && "$email_allein_bestaetigt" == false ]]; then
  echo "Fehler: Ein reiner E-Mail-Auftrag ohne Anlagen erfordert --email-allein-bestaetigt." >&2
  exit 2
fi
case "$umfang_auswahl" in
  A) scope_code="komplette_bewerbung" ;;
  B) scope_code="anschreiben_mit_universalem_lebenslauf" ;;
  C) scope_code="individueller_lebenslauf" ;;
  D) scope_code="nur_anschreiben" ;;
  *) scope_code="eigene_zusammenstellung" ;;
esac
scope_summary="Lebenslauf=$cv_kind; Anschreiben=$include_letter; E-Mail=$include_email"

bewerber_dateiname="$(markdown_field "$stammdaten_path" 'Dateiname-Name')"
universal_source_full=""
universal_source_hash=""
if [[ "$cv_kind" == "universal_unveraendert" ]]; then
  if [[ -z "$universal_lebenslauf_path" || ! -f "$universal_lebenslauf_path" ]]; then
    echo "Fehler: Ein unveränderter universeller Lebenslauf erfordert --universal-lebenslauf-path mit einer vorhandenen HTML-Datei." >&2
    exit 2
  fi
  universal_source_full="$(cd -- "$(dirname -- "$universal_lebenslauf_path")" && pwd)/$(basename -- "$universal_lebenslauf_path")"
  if [[ "$universal_source_full" != *.html ]]; then
    echo "Fehler: Der universelle Lebenslauf muss als HTML-Quelle vorliegen." >&2
    exit 2
  fi
  if [[ -z "$bewerber_dateiname" || "$(basename -- "$universal_source_full")" != "Lebenslauf - $bewerber_dateiname.html" ]]; then
    echo "Fehler: Der universelle Lebenslauf muss exakt 'Lebenslauf - $bewerber_dateiname.html' heißen." >&2
    exit 2
  fi
  if grep -Eiq '\[ergänzen\]|\{\{[^}]+\}\}|TODO|DOKUMENT NOCH NICHT FINAL' "$universal_source_full"; then
    echo "Fehler: Der universelle Lebenslauf enthält Platzhalter oder Entwurfsmarker." >&2
    exit 2
  fi
  universal_source_hash="$(file_sha256 "$universal_source_full")"
elif [[ -n "$universal_lebenslauf_path" ]]; then
  echo "Fehler: --universal-lebenslauf-path ist nur zulässig, wenn der Umfang einen universellen Lebenslauf enthält." >&2
  exit 2
fi

if [[ -e "$bewerbungen_root" && ! -d "$bewerbungen_root" ]]; then
  echo "Fehler: --bewerbungen-root existiert, ist aber kein Ordner: $bewerbungen_root" >&2
  exit 2
fi

firma_slug="$(convert_to_slug "$firma")"
rolle_slug="$(convert_to_slug "$rolle")"
firma_html="$(html_escape "$firma")"
rolle_html="$(html_escape "$rolle")"

bewerbungen_root_full="$(mkdir -p "$bewerbungen_root" && cd -- "$bewerbungen_root" && pwd)"
firma_dir="$bewerbungen_root_full/$firma_slug"
ziel_dir="$firma_dir/$datum--$rolle_slug"
arbeits_dir="$firma_dir/_Arbeitsdateien/$datum--$rolle_slug"
kandidat_dir="$arbeits_dir/Kandidat"

for path in "$ziel_dir" "$arbeits_dir"; do
  if [[ -e "$path" && ! -d "$path" ]]; then
    echo "Fehler: Bewerbungspfad existiert, ist aber kein Ordner: $path" >&2
    exit 2
  fi
done

ziel_existed=0
arbeits_existed=0
[[ -d "$ziel_dir" ]] && ziel_existed=1
[[ -d "$arbeits_dir" ]] && arbeits_existed=1

if (( (ziel_existed || arbeits_existed) && !fortsetzen )); then
  echo "Fehler: Die Bewerbung existiert bereits. Verwende --fortsetzen nur für exakt dieselbe Bewerbung oder wähle Datum/Rolle eindeutig." >&2
  exit 2
fi

if (( fortsetzen && (ziel_existed != arbeits_existed) )); then
  echo "Fehler: Die vorhandene Bewerbung ist unvollständig; Ziel- und Arbeitsordner müssen beide existieren." >&2
  exit 2
fi

if (( fortsetzen && arbeits_existed )); then
  existing_notes="$arbeits_dir/Arbeitsnotizen.md"
  if [[ ! -f "$existing_notes" ]] || ! grep -Fqx -- "- Firma: $firma" "$existing_notes" || ! grep -Fqx -- "- Zielrolle: $rolle" "$existing_notes"; then
    echo "Fehler: Der vorhandene Arbeitsordner gehört nicht nachweislich zu derselben Firma und Rolle." >&2
    exit 2
  fi
  if grep -Eq '^- Dokumentmodus: (vollbewerbung|anschreiben_mit_universalem_lebenslauf|individuelle_auswahl)$' "$existing_notes" && ! grep -Fqx -- "- Dokumentmodus: $dokumentmodus" "$existing_notes"; then
    echo "Fehler: Der vorhandene Arbeitsordner verwendet einen anderen Dokumentmodus." >&2
    exit 2
  fi
  if grep -q '^- Dokumentumfang:' "$existing_notes" && ! grep -Fqx -- "- Dokumentumfang: $scope_summary" "$existing_notes"; then
    echo "Fehler: Der vorhandene Arbeitsordner verwendet einen anderen Dokumentumfang." >&2
    exit 2
  fi
  existing_order="$arbeits_dir/Bewerbungsauftrag.json"
  if [[ ! -f "$existing_order" ]]; then
    echo "Fehler: Der vorhandene Arbeitsordner enthält keinen prüfbaren Bewerbungsauftrag." >&2
    exit 2
  fi
  if ! validate_json_file "$existing_order"; then
    echo "Fehler: Bewerbungsauftrag ist kein gültiges JSON-Dokument." >&2
    exit 2
  fi
  if ! existing_schema="$(json_get_scalar "$existing_order" "schemaVersion" 2>/dev/null)"; then
    echo "Fehler: Bewerbungsauftrag enthält keine unterstützte Schemaversion." >&2
    exit 2
  fi
  if ! existing_schema_type="$(json_get_type "$existing_order" "schemaVersion" 2>/dev/null)" ||
     [[ "$existing_schema_type" != "integer" ]] ||
     ! test_root_schema_integer_lexeme "$existing_order" "$existing_schema"; then
    echo "Fehler: schemaVersion muss eine literale JSON-Ganzzahl sein." >&2
    exit 2
  fi
  case "$existing_schema" in
    4)
      if ! existing_selection="$(json_get_scalar "$existing_order" "dokumentumfang.auswahl" 2>/dev/null)" ||
         ! existing_scope_code="$(json_get_scalar "$existing_order" "dokumentumfang.kennung" 2>/dev/null)" ||
         ! existing_cv_kind="$(json_get_scalar "$existing_order" "dokumentumfang.lebenslauf" 2>/dev/null)" ||
         ! existing_letter="$(json_get_scalar "$existing_order" "dokumentumfang.anschreiben" 2>/dev/null)" ||
         ! existing_email="$(json_get_scalar "$existing_order" "dokumentumfang.emailNachricht" 2>/dev/null)" ||
         ! existing_email_only_approval="$(json_get_scalar "$existing_order" "dokumentumfang.emailAlleinBestaetigt" 2>/dev/null)" ||
         ! existing_letter_type="$(json_get_type "$existing_order" "dokumentumfang.anschreiben" 2>/dev/null)" ||
         ! existing_email_type="$(json_get_type "$existing_order" "dokumentumfang.emailNachricht" 2>/dev/null)" ||
         ! existing_email_only_approval_type="$(json_get_type "$existing_order" "dokumentumfang.emailAlleinBestaetigt" 2>/dev/null)" ||
         ! existing_mode="$(json_get_scalar "$existing_order" "dokumentmodus" 2>/dev/null)"; then
        echo "Fehler: Bewerbungsauftrag mit Schema 4 enthält keinen vollständig prüfbaren Dokumentumfang." >&2
        exit 2
      fi
      if [[ "$existing_letter_type" != "boolean" ||
            "$existing_email_type" != "boolean" ||
            "$existing_email_only_approval_type" != "boolean" ]]; then
        echo "Fehler: Dokumentumfang mit Schema 4 enthält nicht typisierte Boolesche Werte." >&2
        exit 2
      fi
      if [[ "$existing_selection" != "$umfang_auswahl" ||
            "$existing_scope_code" != "$scope_code" ||
            "$existing_cv_kind" != "$cv_kind" ||
            "$existing_letter" != "$include_letter" ||
            "$existing_email" != "$include_email" ||
            "$existing_email_only_approval" != "$email_allein_bestaetigt" ||
            "$existing_mode" != "$dokumentmodus" ]]; then
        echo "Fehler: Bewerbungsauftrag und gewünschter Dokumentumfang stimmen beim Fortsetzen nicht exakt überein." >&2
        exit 2
      fi
      ;;
    1|2|3)
      legacy_mode="$(json_get_scalar "$existing_order" "dokumentmodus" 2>/dev/null || true)"
      case "$legacy_mode" in
        ""|vollbewerbung)
          legacy_selection="A"
          legacy_mode="vollbewerbung"
          ;;
        anschreiben_mit_universalem_lebenslauf)
          legacy_selection="B"
          ;;
        *)
          echo "Fehler: Legacy-Bewerbungsauftrag enthält keinen eindeutig fortsetzbaren Dokumentumfang. Zuerst auf Schema 4 migrieren." >&2
          exit 2
          ;;
      esac
      if [[ "$umfang_auswahl" != "$legacy_selection" || "$dokumentmodus" != "$legacy_mode" ]]; then
        echo "Fehler: Legacy-Bewerbungsauftrag repräsentiert einen anderen Dokumentumfang. Fortsetzen wurde verweigert." >&2
        exit 2
      fi
      ;;
    *)
      echo "Fehler: Bewerbungsauftrag enthält keine unterstützte Schemaversion." >&2
      exit 2
      ;;
  esac

  if [[ "$cv_kind" == "universal_unveraendert" ]]; then
    if ! existing_universal_path="$(json_get_scalar "$existing_order" "universalLebenslauf.sourceHtmlPath" 2>/dev/null)" ||
       ! existing_universal_hash="$(json_get_scalar "$existing_order" "universalLebenslauf.sourceHtmlSha256BeiAnlage" 2>/dev/null)" ||
       ! existing_candidate_name="$(json_get_scalar "$existing_order" "universalLebenslauf.kandidatDatei" 2>/dev/null)" ||
       ! existing_applicant_name="$(json_get_scalar "$existing_order" "bewerberDateiname" 2>/dev/null)"; then
      echo "Fehler: Bewerbungsauftrag enthält keine vollständig gebundene Universal-Lebenslauf-Quelle." >&2
      exit 2
    fi
    if [[ "$existing_universal_path" != "$universal_source_full" ||
          "${existing_universal_hash^^}" != "${universal_source_hash^^}" ||
          "$existing_candidate_name" != "Lebenslauf - $bewerber_dateiname.html" ||
          "$existing_applicant_name" != "$bewerber_dateiname" ]]; then
      echo "Fehler: Beim Fortsetzen wurden Pfad, Dateiname oder Hash der Universal-Lebenslauf-Quelle verändert." >&2
      exit 2
    fi
  fi
fi

ziel_created=0
arbeits_created=0
success=0

cleanup_on_exit() {
  local code="$1"
  if ((code != 0 && !success)); then
    if ((arbeits_created)) && [[ "$arbeits_dir" == "$bewerbungen_root_full"/* ]]; then
      rm -rf -- "$arbeits_dir"
    fi
    if ((ziel_created)) && [[ "$ziel_dir" == "$bewerbungen_root_full"/* ]]; then
      rm -rf -- "$ziel_dir"
    fi
  fi
  return "$code"
}
trap 'cleanup_on_exit $?' EXIT

if (( !ziel_existed )); then
  mkdir -p "$ziel_dir"
  ziel_created=1
fi
if (( !arbeits_existed )); then
  mkdir -p "$arbeits_dir"
  arbeits_created=1
fi
mkdir -p "$kandidat_dir"

stellenbeschreibung_kandidat_file="$kandidat_dir/Stellenbeschreibung.md"
stellenbeschreibung_entwurf_file="$arbeits_dir/Stellenbeschreibung--ENTWURF.md"
analyse_entwurf_file="$arbeits_dir/Analyse--ENTWURF.md"
lebenslauf_entwurf_file="$arbeits_dir/Lebenslauf--$firma_slug--ENTWURF.html"
anschreiben_entwurf_file="$arbeits_dir/Anschreiben--$firma_slug--ENTWURF.html"
arbeitsnotizen_file="$arbeits_dir/Arbeitsnotizen.md"
email_entwurf_file="$arbeits_dir/Email-Nachricht--$firma_slug--ENTWURF.md"
qualitaetscheck_entwurf_file="$arbeits_dir/Qualitaetscheck--ENTWURF.md"
offene_fragen_entwurf_file="$arbeits_dir/Offene_Fragen--ENTWURF.md"
anforderungsmatrix_entwurf_file="$arbeits_dir/Anforderungsmatrix--ENTWURF.json"
auftrag_file="$arbeits_dir/Bewerbungsauftrag.json"
druck_hinweis_file="$kandidat_dir/Druck-Hinweis.md"
universal_candidate_file="$kandidat_dir/Lebenslauf - $bewerber_dateiname.html"

if [[ -n "$stellenbeschreibung_path" ]]; then
  if [[ -f "$stellenbeschreibung_kandidat_file" ]]; then
    if ! cmp -s -- "$stellenbeschreibung_path" "$stellenbeschreibung_kandidat_file"; then
      echo "Fehler: Eine andere Stellenbeschreibung liegt bereits im Kandidatenordner. Überschreiben wurde verweigert." >&2
      exit 1
    fi
  elif [[ -e "$stellenbeschreibung_kandidat_file" ]]; then
    echo "Fehler: Stellenbeschreibung.md existiert, ist aber keine Datei." >&2
    exit 1
  else
    cp "$stellenbeschreibung_path" "$stellenbeschreibung_kandidat_file"
  fi
elif [[ ! -e "$stellenbeschreibung_kandidat_file" && ! -e "$stellenbeschreibung_entwurf_file" ]]; then
  cat > "$stellenbeschreibung_entwurf_file" <<'EOF'
# Stellenbeschreibung

[Stellenbeschreibung hier einfügen]
EOF
fi

if [[ "$cv_kind" == "universal_unveraendert" ]]; then
  if [[ -f "$universal_candidate_file" ]]; then
    [[ "$(file_sha256 "$universal_candidate_file")" == "$universal_source_hash" ]] || {
      echo "Fehler: Der Kandidaten-Lebenslauf weicht von der freigegebenen Universalquelle ab." >&2
      exit 1
    }
  elif [[ -e "$universal_candidate_file" ]]; then
    echo "Fehler: Der erwartete universelle Lebenslauf im Kandidatenordner ist keine Datei." >&2
    exit 1
  else
    cp -- "$universal_source_full" "$universal_candidate_file"
  fi
fi

if [[ ! -e "$auftrag_file" ]]; then
  firma_json="$(json_escape "$firma")"
  rolle_json="$(json_escape "$rolle")"
  ziel_json="$(json_escape "$ziel_dir")"
  arbeits_json="$(json_escape "$arbeits_dir")"
  kandidat_json="$(json_escape "$kandidat_dir")"
  bewerber_dateiname_json="$(json_escape "$bewerber_dateiname")"
  verfuegbarkeit_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Verfügbarkeit')")"
  eintritt_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Frühester Eintrittstermin')")"
  stellenart_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Gewünschte Stellenart')")"
  stundenumfang_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Gewünschter Stundenumfang')")"
  arbeitsmodell_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Gewünschtes Arbeitsmodell')")"
  region_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Gewünschte Region')")"
  pendeldistanz_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Maximale Pendeldistanz')")"
  reisebereitschaft_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Reisebereitschaft')")"
  schicht_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Schicht- oder Wochenendbereitschaft')")"
  befristung_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Befristung')")"
  umzug_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Umzugsbereitschaft')")"
  gehalt_verwenden_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Wunschgehalt verwenden')")"
  gehalt_manuell_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Wunschgehalt manuell')")"
  gehaltsmodell_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Gehaltsmodell')")"
  gehaltsregion_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Gehaltsregion')")"
  gehaltslogik_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Gehaltslogik')")"
  stammdaten_hash="$(file_sha256 "$stammdaten_path")"
  profil_hash="$(file_sha256 "$profil_path")"
  dokumentmodus_json="$(json_escape "$dokumentmodus")"
  if [[ "$cv_kind" == "universal_unveraendert" ]]; then
    universal_source_json="$(json_escape "$universal_source_full")"
    universal_candidate_json="$(json_escape "Lebenslauf - $bewerber_dateiname.html")"
    universal_json="{\"sourceHtmlPath\": \"$universal_source_json\", \"sourceHtmlSha256BeiAnlage\": \"$universal_source_hash\", \"kandidatDatei\": \"$universal_candidate_json\"}"
  else
    universal_json="null"
  fi
  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$auftrag_file" <<EOF
{
  "schemaVersion": 4,
  "firma": "$firma_json",
  "firmaSlug": "$firma_slug",
  "rolle": "$rolle_json",
  "rolleSlug": "$rolle_slug",
  "datum": "$datum",
  "bewerberDateiname": "$bewerber_dateiname_json",
  "zielOrdner": "$ziel_json",
  "arbeitsOrdner": "$arbeits_json",
  "kandidatOrdner": "$kandidat_json",
  "dokumentmodus": "$dokumentmodus_json",
  "dokumentumfang": {
    "auswahl": "$umfang_auswahl",
    "kennung": "$scope_code",
    "lebenslauf": "$cv_kind",
    "anschreiben": $include_letter,
    "emailNachricht": $include_email,
    "quelle": "$umfang_quelle",
    "bestaetigt": true,
    "emailAlleinBestaetigt": $email_allein_bestaetigt,
    "bestaetigtAtUtc": "$created_at"
  },
  "universalLebenslauf": $universal_json,
  "seitenstrategie": "$(if [[ "$include_cv" == true ]]; then printf 'noch_festzulegen'; else printf 'nicht_erforderlich'; fi)",
  "bewerbungslogistik": {
    "verfuegbarkeit": "$verfuegbarkeit_json",
    "fruehesterEintrittstermin": "$eintritt_json",
    "stellenart": "$stellenart_json",
    "stundenumfang": "$stundenumfang_json",
    "arbeitsmodell": "$arbeitsmodell_json",
    "region": "$region_json",
    "maximalePendeldistanz": "$pendeldistanz_json",
    "reisebereitschaft": "$reisebereitschaft_json",
    "schichtOderWochenendbereitschaft": "$schicht_json",
    "befristung": "$befristung_json",
    "umzugsbereitschaft": "$umzug_json",
    "wunschgehaltVerwenden": "$gehalt_verwenden_json",
    "wunschgehaltManuell": "$gehalt_manuell_json",
    "gehaltsmodell": "$gehaltsmodell_json",
    "gehaltsregion": "$gehaltsregion_json",
    "gehaltslogik": "$gehaltslogik_json"
  },
  "bewerbungsentscheidung": "noch_festzulegen",
  "darstellungsoptionen": {
    "schulbildungsmodus": "$(if [[ "$include_cv" == true ]]; then printf 'noch_festzulegen'; else printf 'nicht_erforderlich'; fi)",
    "profillinksModus": "$(if [[ "$include_cv" == true ]]; then printf 'noch_festzulegen'; else printf 'nicht_erforderlich'; fi)",
    "profillinksAuswahl": []
  },
  "dialog": {
    "schemaVersion": 1,
    "status": "profilabgleich_ausstehend",
    "rueckfragen": [],
    "angaben": [],
    "updatedAtUtc": "$created_at"
  },
  "quellnachweise": {
    "stammdatenSha256BeiAnlage": "$stammdaten_hash",
    "profilSha256BeiAnlage": "$profil_hash"
  },
  "createdAtUtc": "$created_at"
}
EOF
  if ! validate_json_file "$auftrag_file"; then
    echo "Fehler: Der erzeugte Bewerbungsauftrag ist kein gültiges JSON-Dokument." >&2
    exit 1
  fi
fi

if [[ ! -e "$anforderungsmatrix_entwurf_file" ]]; then
  cat > "$anforderungsmatrix_entwurf_file" <<'EOF'
{
  "schemaVersion": 2,
  "requirements": [
    {
      "id": "muss-1",
      "anforderung": "durch den Agenten aus der Stellenbeschreibung zu extrahieren",
      "typ": "muss",
      "kategorie": "fachlich",
      "gewichtung": "hoch",
      "status": "unklar",
      "belegart": "",
      "beleg": "",
      "behandlung": "vor Erstellung der Kandidatendateien klären"
    }
  ]
}
EOF
fi

if [[ ! -e "$analyse_entwurf_file" ]]; then
  cat > "$analyse_entwurf_file" <<EOF
# Analyse

- Firma: $firma
- Zielrolle: $rolle
- Datum: $datum
- Profilstrategie: [nach Analyse ergänzen]
- Wichtigste Anforderungen: [ergänzen]
- Passende Bewerberargumente: [ergänzen]
- Bewusst weggelassene Inhalte: [ergänzen]
EOF
fi

if [[ "$include_cv" == true && "$cv_kind" == "individuell" && ! -e "$lebenslauf_entwurf_file" ]]; then
  cat > "$lebenslauf_entwurf_file" <<EOF
<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Lebenslauf - Bewerber - $firma_html</title>
  <style>
    @page { size: A4; margin: 0; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; font-family: Arial, Helvetica, sans-serif; color: #101828; line-height: 1.4; }
    .page { width: 210mm; min-height: 297mm; margin: 0 auto; padding: 16mm; background: #fff; }
    .warning { padding: 8mm; border: 2px solid #b42318; color: #7a271a; background: #fff4ed; font-weight: 700; }
    @media print { html, body { width: 210mm; min-height: 297mm; margin: 0; padding: 0; background: #fff; } .page { width: 210mm; min-height: 297mm; margin: 0; box-shadow: none; } }
  </style>
</head>
<body>
  <main class="page">
    <h1>Lebenslauf - Arbeitsentwurf</h1>
    <p class="warning">DOKUMENT NOCH NICHT FINAL - durch den Agenten vollständig ersetzen.</p>
    <p>Firma: $firma_html</p>
    <p>Zielrolle: $rolle_html</p>
    <p>Nutze die Regeln aus <code>Prompts/00_AGENTEN_START_HIER.md</code> und die neutrale Vorlage <code>Vorlagen/Designreferenz-Lebenslauf.html</code>.</p>
  </main>
</body>
</html>
EOF
fi

if [[ "$include_letter" == true && ! -e "$anschreiben_entwurf_file" ]]; then
  cat > "$anschreiben_entwurf_file" <<EOF
<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Anschreiben - Bewerber - $firma_html</title>
  <style>
    @page { size: A4; margin: 0; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; font-family: Arial, Helvetica, sans-serif; color: #101828; line-height: 1.4; }
    .page { width: 210mm; min-height: 297mm; margin: 0 auto; padding: 18mm; background: #fff; }
    .warning { padding: 8mm; border: 2px solid #b42318; color: #7a271a; background: #fff4ed; font-weight: 700; }
    @media print { html, body { width: 210mm; min-height: 297mm; margin: 0; padding: 0; background: #fff; } .page { width: 210mm; min-height: 297mm; margin: 0; box-shadow: none; } }
  </style>
</head>
<body>
  <main class="page">
    <h1>Anschreiben - Arbeitsentwurf</h1>
    <p class="warning">DOKUMENT NOCH NICHT FINAL - durch den Agenten vollständig ersetzen.</p>
    <p>Firma: $firma_html</p>
    <p>Zielrolle: $rolle_html</p>
    <p>Nutze die Regeln aus <code>Prompts/00_AGENTEN_START_HIER.md</code> und die neutrale Vorlage <code>Vorlagen/Designreferenz-Anschreiben.html</code>.</p>
  </main>
</body>
</html>
EOF
fi

if [[ ! -e "$arbeitsnotizen_file" ]]; then
  cat > "$arbeitsnotizen_file" <<EOF
# Arbeitsnotizen

- Firma: $firma
- Zielrolle: $rolle
- Dokumentmodus: $dokumentmodus
- Dokumentumfang: $scope_summary
- Finaler Bewerbungsordner: $ziel_dir
- Entwurfs-/Arbeitsdateien: $arbeits_dir
- Kandidatendateien vor Freigabe: $kandidat_dir

Dieser Ordner ist nur für temporäre Entwürfe und Arbeitsnotizen gedacht.
Versandfertig benannte Kandidatendateien gehören zunächst in den Kandidatenordner.
Der finale Bewerbungsordner bleibt bis zur erfolgreichen atomaren Veröffentlichung leer.
EOF
fi

if [[ "$include_email" == true && ! -e "$email_entwurf_file" ]]; then
  if [[ "$include_cv" == true || "$include_letter" == true ]]; then
    email_intro="anbei sende ich Ihnen meine Bewerbungsunterlagen für die Position als $rolle bei $firma."
  else
    email_intro="hiermit bewerbe ich mich für die Position als $rolle bei $firma."
  fi
  cat > "$email_entwurf_file" <<EOF
Betreff: Bewerbung als $rolle - [Name aus Private/Daten/01_PERSOENLICHE_DATEN.md]

Sehr geehrte Damen und Herren,

$email_intro

Über eine Rückmeldung freue ich mich.

Mit freundlichen Grüßen
[Name aus Private/Daten/01_PERSOENLICHE_DATEN.md]
EOF
fi

if [[ ! -e "$qualitaetscheck_entwurf_file" ]]; then
  cat > "$qualitaetscheck_entwurf_file" <<'EOF'
# Qualitätscheck

- [ ] Stellenbeschreibung analysiert
EOF
  if [[ "$include_cv" == true ]]; then printf '%s\n' '- [ ] Lebenslauf gemäß gewählter Strategie geprüft' >> "$qualitaetscheck_entwurf_file"; fi
  if [[ "$include_letter" == true ]]; then printf '%s\n' '- [ ] Anschreiben individuell formuliert' >> "$qualitaetscheck_entwurf_file"; fi
  if [[ "$include_email" == true ]]; then printf '%s\n' '- [ ] E-Mail-Nachricht erstellt' >> "$qualitaetscheck_entwurf_file"; fi
  cat >> "$qualitaetscheck_entwurf_file" <<'EOF'
- [ ] Keine erfundenen Kenntnisse
- [ ] Keine sichtbaren Platzhalter in finalen Dokumenten
- [ ] Fehlende Daten in Offene_Fragen.md dokumentiert
- [ ] HTML/CSS druckfreundlich geprüft
EOF
fi

if [[ ! -e "$offene_fragen_entwurf_file" ]]; then
  cat > "$offene_fragen_entwurf_file" <<'EOF'
# Offene Fragen

- [ ] Fehlen Ansprechpartner oder Adresse?
- [ ] Sind genaue Zeiträume relevant?
- [ ] Gibt es einen gewünschten Eintrittstermin?
EOF
fi

if [[ ! -e "$druck_hinweis_file" ]]; then
  cat > "$druck_hinweis_file" <<'EOF'
# Druck-Hinweis

Der verbindliche PDF-Export erfolgt automatisiert mit Chrome oder Edge. Browser-Kopf- und Fußzeilen wie Dateiname, URL, Datum oder Seitenzahl dürfen dabei nicht erscheinen.

Vor dem finalen PDF-Export oder Druck:

1. Tools/Finalisiere-Bewerbung.ps1 mit -Browser auto ausführen.
2. Jeden frisch erzeugten Seitenscreenshot tatsächlich prüfen.
3. Keine manuelle Browservorschau als bestandenen maschinellen Export ausgeben.

Ziel: Die sichtbare A4-Seite wird ohne Browser-Dateipfad, URL, Datum oder Browser-Seitenzahlen als PDF ausgegeben.
EOF
fi

if ! validate_json_file "$auftrag_file"; then
  echo "Fehler: Bewerbungsauftrag ist vor Abschluss kein gültiges JSON-Dokument." >&2
  exit 1
fi

printf 'Bewerbungsordner: %s\n' "$ziel_dir"
printf 'Arbeitsdateien: %s\n' "$arbeits_dir"
printf 'Kandidatendateien: %s\n' "$kandidat_dir"
printf 'Dokumentmodus: %s\n' "$dokumentmodus"
printf 'Dokumentumfang: %s\n' "$scope_summary"
if [[ "$cv_kind" == "universal_unveraendert" ]]; then
  printf 'Universeller Lebenslauf unverändert übernommen: %s\n' "$universal_candidate_file"
fi
success=1
