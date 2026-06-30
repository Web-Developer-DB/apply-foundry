#!/usr/bin/env bash
set -euo pipefail

print_usage() {
  cat <<'EOF'
Usage:
  bash Tools/neue-bewerbung.sh --firma "Team System House GmbH" [options]

Options:
  --firma NAME                    Firmenname, Pflichtangabe
  --rolle NAME                    Zielrolle, Standard: Bewerbung
  --datum YYYY-MM-DD              Datum, Standard: heute
  --stellenbeschreibung-path PATH Pfad zu vorhandener Stellenbeschreibung
  --bewerbungen-root PATH         Ausgabeordner, Standard: ./Private/Bewerbungen
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
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&#39;}"
  printf '%s' "$value"
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$script_dir/.." && pwd)"

firma=""
rolle="Bewerbung"
datum="$(date +%F)"
stellenbeschreibung_path=""
bewerbungen_root="$project_root/Private/Bewerbungen"

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
    --bewerbungen-root)
      [[ $# -ge 2 ]] || { echo "Fehlender Wert fuer --bewerbungen-root" >&2; exit 2; }
      bewerbungen_root="$2"
      shift 2
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

if [[ ! "$datum" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Fehler: --datum muss im Format YYYY-MM-DD angegeben werden." >&2
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

mkdir -p "$ziel_dir" "$arbeits_dir"

stellenbeschreibung_final_file="$ziel_dir/Stellenbeschreibung.md"
stellenbeschreibung_entwurf_file="$arbeits_dir/Stellenbeschreibung--ENTWURF.md"
analyse_entwurf_file="$arbeits_dir/Analyse--ENTWURF.md"
lebenslauf_entwurf_file="$arbeits_dir/Lebenslauf--$firma_slug--ENTWURF.html"
anschreiben_entwurf_file="$arbeits_dir/Anschreiben--$firma_slug--ENTWURF.html"
arbeitsnotizen_file="$arbeits_dir/Arbeitsnotizen.md"
email_entwurf_file="$arbeits_dir/Email-Nachricht--$firma_slug--ENTWURF.md"
qualitaetscheck_entwurf_file="$arbeits_dir/Qualitaetscheck--ENTWURF.md"
offene_fragen_entwurf_file="$arbeits_dir/Offene_Fragen--ENTWURF.md"
druck_hinweis_file="$ziel_dir/Druck-Hinweis.md"

if [[ -n "$stellenbeschreibung_path" ]]; then
  cp "$stellenbeschreibung_path" "$stellenbeschreibung_final_file"
elif [[ ! -e "$stellenbeschreibung_entwurf_file" ]]; then
  cat > "$stellenbeschreibung_entwurf_file" <<'EOF'
# Stellenbeschreibung

[Stellenbeschreibung hier einfügen]
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

Dieser Ordner ist nur für temporäre Entwürfe und Arbeitsnotizen gedacht.
Finale Dateien gehören erst nach vollständiger Agentenprüfung in den finalen Bewerbungsordner.
EOF
fi

if [[ ! -e "$email_entwurf_file" ]]; then
  cat > "$email_entwurf_file" <<EOF
# E-Mail-Nachricht

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