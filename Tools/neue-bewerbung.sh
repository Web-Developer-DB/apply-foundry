#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'EOF'
Usage:
  bash Tools/neue-bewerbung.sh --firma "Muster GmbH" [options]

Options:
  --firma NAME                    Firmenname, Pflichtangabe
  --rolle NAME                    Zielrolle, Standard: Bewerbung
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
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

markdown_field() {
  local path="$1"
  local field="$2"
  [[ -f "$path" ]] || return 0
  sed -n -E "s/^[[:space:]]*-[[:space:]]*${field}:[[:space:]]*(.*)$/\\1/p" "$path" | head -n 1
}

file_sha256() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$path" | awk '{print toupper($1)}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$path" | awk '{print toupper($1)}'
  fi
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

if [[ ! -e "$auftrag_file" ]]; then
  firma_json="$(json_escape "$firma")"
  rolle_json="$(json_escape "$rolle")"
  ziel_json="$(json_escape "$ziel_dir")"
  arbeits_json="$(json_escape "$arbeits_dir")"
  kandidat_json="$(json_escape "$kandidat_dir")"
  bewerber_dateiname_json="$(json_escape "$(markdown_field "$stammdaten_path" 'Dateiname-Name')")"
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
  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$auftrag_file" <<EOF
{
  "schemaVersion": 2,
  "firma": "$firma_json",
  "firmaSlug": "$firma_slug",
  "rolle": "$rolle_json",
  "rolleSlug": "$rolle_slug",
  "datum": "$datum",
  "bewerberDateiname": "$bewerber_dateiname_json",
  "zielOrdner": "$ziel_json",
  "arbeitsOrdner": "$arbeits_json",
  "kandidatOrdner": "$kandidat_json",
  "seitenstrategie": "noch_festzulegen",
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
    "schulbildungsmodus": "noch_festzulegen",
    "profillinksModus": "noch_festzulegen",
    "profillinksAuswahl": []
  },
  "quellnachweise": {
    "stammdatenSha256BeiAnlage": "$stammdaten_hash",
    "profilSha256BeiAnlage": "$profil_hash"
  },
  "createdAtUtc": "$created_at"
}
EOF
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

if [[ ! -e "$lebenslauf_entwurf_file" ]]; then
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

if [[ ! -e "$anschreiben_entwurf_file" ]]; then
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
- Finaler Bewerbungsordner: $ziel_dir
- Entwurfs-/Arbeitsdateien: $arbeits_dir
- Kandidatendateien vor Freigabe: $kandidat_dir

Dieser Ordner ist nur für temporäre Entwürfe und Arbeitsnotizen gedacht.
Versandfertig benannte Kandidatendateien gehören zunächst in den Kandidatenordner.
Der finale Bewerbungsordner bleibt bis zur erfolgreichen atomaren Veröffentlichung leer.
EOF
fi

if [[ ! -e "$email_entwurf_file" ]]; then
  cat > "$email_entwurf_file" <<EOF
Betreff: Bewerbung als $rolle - [Name aus Private/Daten/01_PERSOENLICHE_DATEN.md]

Sehr geehrte Damen und Herren,

anbei sende ich Ihnen meine Bewerbungsunterlagen für die Position als $rolle.

Über eine Rückmeldung freue ich mich.

Mit freundlichen Grüßen
[Name aus Private/Daten/01_PERSOENLICHE_DATEN.md]
EOF
fi

if [[ ! -e "$qualitaetscheck_entwurf_file" ]]; then
  cat > "$qualitaetscheck_entwurf_file" <<'EOF'
# Qualitätscheck

- [ ] Stellenbeschreibung analysiert
- [ ] Lebenslauf auf Zielrolle zugeschnitten
- [ ] Anschreiben individuell formuliert
- [ ] E-Mail-Nachricht erstellt
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

Wenn in Firefox Dateiname, URL, Datum oder Seitenzahl im Ausdruck erscheinen, kommt das aus dem Firefox-Druckdialog und nicht aus der HTML-Datei.

Vor dem finalen PDF-Export oder Druck:

1. HTML-Datei in Firefox öffnen.
2. Strg + P drücken.
3. Weitere Einstellungen öffnen.
4. Kopf- und Fußzeilen drucken deaktivieren.
5. Skalierung auf 100% stellen.
6. Ränder auf Keine stellen.

Ziel: Die sichtbare A4-Seite im Browser soll ohne Firefox-Dateipfad, URL, Datum oder Seitenzahlen als PDF/Druck ausgegeben werden.
EOF
fi

printf 'Bewerbungsordner: %s\n' "$ziel_dir"
printf 'Arbeitsdateien: %s\n' "$arbeits_dir"
printf 'Kandidatendateien: %s\n' "$kandidat_dir"
success=1
