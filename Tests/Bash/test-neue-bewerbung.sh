#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
tool="$repo_root/Tools/neue-bewerbung.sh"
test_root="$(mktemp -d)"

case "$test_root" in
  /tmp/*) ;;
  *) printf 'Unsicherer Testpfad: %s\n' "$test_root" >&2; exit 99 ;;
esac
trap 'rm -rf -- "$test_root"' EXIT

fail() {
  printf '[FEHLER] %s\n' "$1" >&2
  exit 1
}

test_json_tool=""
if command -v jq >/dev/null 2>&1 && jq --version >/dev/null 2>&1; then
  test_json_tool="jq"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import json' >/dev/null 2>&1; then
  test_json_tool="python3"
elif command -v python >/dev/null 2>&1 && python -c 'import json, sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' >/dev/null 2>&1; then
  test_json_tool="python"
elif command -v node >/dev/null 2>&1 && node -e 'JSON.parse("{}")' >/dev/null 2>&1; then
  test_json_tool="node"
elif command -v pwsh >/dev/null 2>&1 && pwsh -NoLogo -NoProfile -NonInteractive -Command '$null = "{}" | ConvertFrom-Json' >/dev/null 2>&1; then
  test_json_tool="pwsh"
else
  fail "Kein echter JSON-Parser für die Regressionstests verfügbar."
fi

assert_json_parses() {
  local path="$1"
  case "$test_json_tool" in
    jq)
      jq -e . "$path" >/dev/null 2>&1 || fail "JSON-Datei ist nicht parsebar: $path"
      ;;
    python3|python)
      "$test_json_tool" -c 'import json, sys; json.load(open(sys.argv[1], "r", encoding="utf-8-sig"))' "$path" >/dev/null 2>&1 || fail "JSON-Datei ist nicht parsebar: $path"
      ;;
    node)
      node -e 'const fs = require("fs"); JSON.parse(fs.readFileSync(process.argv[1], "utf8").replace(/^\uFEFF/, ""));' "$path" >/dev/null 2>&1 || fail "JSON-Datei ist nicht parsebar: $path"
      ;;
    pwsh)
      pwsh -NoLogo -NoProfile -NonInteractive -Command "\$text = Get-Content -LiteralPath \$args[0] -Raw -Encoding UTF8; \$null = \$text | ConvertFrom-Json -ErrorAction Stop" "$path" >/dev/null 2>&1 || fail "JSON-Datei ist nicht parsebar: $path"
      ;;
  esac
}

printf '%s\n' '- Dateiname-Name: TEST.PERSON' > "$test_root/default-personal.md"
printf '%s\n' '# Fiktives Testprofil' > "$test_root/default-profile.md"

invoke_tool() {
  bash "$tool" \
    --stammdaten-path "$test_root/default-personal.md" \
    --profil-path "$test_root/default-profile.md" \
    "$@"
}

bash -n "$tool"

nohash_bin="$test_root/nohash-bin"
mkdir -p "$nohash_bin"
date_path="$(command -v date)"
dirname_path="$(command -v dirname)"
printf '#!/bin/bash\nexec "%s" "$@"\n' "$date_path" > "$nohash_bin/date"
printf '#!/bin/bash\nexec "%s" "$@"\n' "$dirname_path" > "$nohash_bin/dirname"
chmod +x "$nohash_bin/date" "$nohash_bin/dirname"
bash_path="$(command -v bash)"
set +e
missing_hash_output="$(PATH="$nohash_bin" "$bash_path" "$tool" --firma "Ohne Hash" --rolle "Audit" --datum "2026-07-14" --umfang A --stammdaten-path "$test_root/default-personal.md" --profil-path "$test_root/default-profile.md" 2>&1)"
code=$?
set -e
[[ $code -eq 2 ]] || fail "Fehlendes SHA-256-Werkzeug wurde nicht mit Exitcode 2 abgelehnt (Exitcode $code; Ausgabe: $missing_hash_output)."
[[ "$missing_hash_output" == *"sha256sum oder shasum"* ]] || fail "Fehlendes SHA-256-Werkzeug wurde nicht verständlich gemeldet."
[[ ! -e "$test_root/nohash" ]] || fail "Fehlendes SHA-256-Werkzeug erzeugte eine Teilstruktur."

set +e
invoke_tool --firma "Audit Firma" --rolle "Audit Rolle" --datum "2026-99-99" --bewerbungen-root "$test_root/invalid-date" >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Unmögliches Datum wurde nicht mit Exitcode 2 abgelehnt."
[[ ! -e "$test_root/invalid-date" ]] || fail "Ungültiges Datum erzeugte eine Ausgabe."

mkdir -p "$test_root/source-directory"
set +e
invoke_tool --firma "Audit Firma" --rolle "Audit Rolle" --datum "2026-07-14" --stellenbeschreibung-path "$test_root/source-directory" --bewerbungen-root "$test_root/directory-source" >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Verzeichnisquelle wurde nicht mit Exitcode 2 abgelehnt."
[[ ! -e "$test_root/directory-source" ]] || fail "Verzeichnisquelle erzeugte eine Teilstruktur."

invoke_tool --firma 'A&B <X>' --rolle 'R "Q"' --datum '2026-07-14' --umfang A --bewerbungen-root "$test_root/escaping" >/dev/null
html="$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Lebenslauf--AundB-X--ENTWURF.html"
grep -Fq 'A&amp;B &lt;X&gt;' "$html" || fail "Firmenname wurde nicht korrekt HTML-kodiert."
grep -Fq 'R &quot;Q&quot;' "$html" || fail "Rollenname wurde nicht korrekt HTML-kodiert."
[[ -f "$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Bewerbungsauftrag.json" ]] || fail "Bewerbungsauftrag wurde nicht erzeugt."
[[ -d "$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Kandidat" ]] || fail "Kandidatenordner wurde nicht erzeugt."
auftrag="$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Bewerbungsauftrag.json"
matrix="$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Anforderungsmatrix--ENTWURF.json"
assert_json_parses "$auftrag"
grep -Fq '"schemaVersion": 4' "$auftrag" || fail "Bewerbungsauftrag verwendet nicht Schema 4."
grep -Fq '"dokumentmodus": "vollbewerbung"' "$auftrag" || fail "Standard-Dokumentmodus fehlt im Auftrag."
grep -Fq '"kennung": "komplette_bewerbung"' "$auftrag" || fail "Dokumentumfang A fehlt im Auftrag."
grep -Fq '"bewerbungsentscheidung": "noch_festzulegen"' "$auftrag" || fail "Bewerbungsentscheidung fehlt im Auftrag."
grep -Fq '"profillinksModus": "noch_festzulegen"' "$auftrag" || fail "Profillink-Modus fehlt im Auftrag."
grep -Fq '"gewichtung": "hoch"' "$matrix" || fail "Matrixentwurf enthält keine Gewichtung."

printf '%s\r\n' '- Dateiname-Name: CRLF.PERSON' > "$test_root/crlf-personal.md"
printf '%b\r\n' '- Verfügbarkeit: sofort\toder\rspäter\001' >> "$test_root/crlf-personal.md"
printf '%s\r\n' '# Fiktives CRLF-Testprofil' > "$test_root/crlf-profile.md"
invoke_tool --firma "CRLF Firma" --rolle "CRLF Rolle" --datum "2026-07-14" --umfang A --stammdaten-path "$test_root/crlf-personal.md" --profil-path "$test_root/crlf-profile.md" --bewerbungen-root "$test_root/crlf" >/dev/null
crlf_order="$test_root/crlf/CRLF-Firma/_Arbeitsdateien/2026-07-14--CRLF-Rolle/Bewerbungsauftrag.json"
assert_json_parses "$crlf_order"
grep -Fq '"verfuegbarkeit": "sofort\toder\rspäter\u0001"' "$crlf_order" || fail "Steuerzeichen aus CRLF-Stammdaten wurden nicht JSON-konform maskiert."
if LC_ALL=C grep -q $'\r' "$crlf_order"; then
  fail "Bewerbungsauftrag enthält ein unmaskiertes CR-Zeichen."
fi

mkdir -p "$test_root/universal-source"
printf '%s\n' '<!doctype html><html><head><style>.page { width: 210mm; height: 297mm; overflow: hidden; }</style></head><body><main class="page">TEST.PERSON universell</main></body></html>' > "$test_root/universal-source/Lebenslauf - TEST.PERSON.html"
printf '%s\n' '- Dateiname-Name: TEST.PERSON' > "$test_root/universal-personal.md"
printf '%s\n' '# Testprofil' > "$test_root/universal-profile.md"
invoke_tool --firma "Universal Firma" --rolle "Universal Rolle" --datum "2026-07-14" --dokumentmodus "anschreiben_mit_universalem_lebenslauf" --universal-lebenslauf-path "$test_root/universal-source/Lebenslauf - TEST.PERSON.html" --stammdaten-path "$test_root/universal-personal.md" --profil-path "$test_root/universal-profile.md" --bewerbungen-root "$test_root/universal-app" >/dev/null
universal_work="$test_root/universal-app/Universal-Firma/_Arbeitsdateien/2026-07-14--Universal-Rolle"
cmp -s "$test_root/universal-source/Lebenslauf - TEST.PERSON.html" "$universal_work/Kandidat/Lebenslauf - TEST.PERSON.html" || fail "Universalquelle wurde verändert übernommen."
[[ ! -e "$universal_work/Lebenslauf--Universal-Firma--ENTWURF.html" ]] || fail "Im Anschreiben-Modus wurde ein Lebenslaufentwurf erzeugt."
grep -Fq '"dokumentmodus": "anschreiben_mit_universalem_lebenslauf"' "$universal_work/Bewerbungsauftrag.json" || fail "Anschreiben-Modus fehlt im Auftrag."
invoke_tool --firma "Universal Firma" --rolle "Universal Rolle" --datum "2026-07-14" --umfang B --universal-lebenslauf-path "$test_root/universal-source/Lebenslauf - TEST.PERSON.html" --stammdaten-path "$test_root/universal-personal.md" --profil-path "$test_root/universal-profile.md" --bewerbungen-root "$test_root/universal-app" --fortsetzen >/dev/null

mkdir -p "$test_root/universal-source-copy"
cp -- "$test_root/universal-source/Lebenslauf - TEST.PERSON.html" "$test_root/universal-source-copy/Lebenslauf - TEST.PERSON.html"
set +e
invoke_tool --firma "Universal Firma" --rolle "Universal Rolle" --datum "2026-07-14" --umfang B --universal-lebenslauf-path "$test_root/universal-source-copy/Lebenslauf - TEST.PERSON.html" --stammdaten-path "$test_root/universal-personal.md" --profil-path "$test_root/universal-profile.md" --bewerbungen-root "$test_root/universal-app" --fortsetzen >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Gleicher Universal-CV-Hash unter einem anderen Quellpfad wurde beim Fortsetzen akzeptiert."

invoke_tool --firma "Legacy Universal" --rolle "Legacy Rolle" --datum "2026-07-14" --umfang B --universal-lebenslauf-path "$test_root/universal-source/Lebenslauf - TEST.PERSON.html" --stammdaten-path "$test_root/universal-personal.md" --profil-path "$test_root/universal-profile.md" --bewerbungen-root "$test_root/legacy-universal" >/dev/null
legacy_universal_work="$test_root/legacy-universal/Legacy-Universal/_Arbeitsdateien/2026-07-14--Legacy-Rolle"
sed -i -E 's/"schemaVersion"[[:space:]]*:[[:space:]]*4/"schemaVersion": 2/' "$legacy_universal_work/Bewerbungsauftrag.json"
assert_json_parses "$legacy_universal_work/Bewerbungsauftrag.json"
invoke_tool --firma "Legacy Universal" --rolle "Legacy Rolle" --datum "2026-07-14" --umfang B --universal-lebenslauf-path "$test_root/universal-source/Lebenslauf - TEST.PERSON.html" --stammdaten-path "$test_root/universal-personal.md" --profil-path "$test_root/universal-profile.md" --bewerbungen-root "$test_root/legacy-universal" --fortsetzen >/dev/null

printf '%s\n' \
  '- Dateiname-Name: TEST.PERSON' \
  '- Gewünschte Stellenart: Vollzeit' \
  '- Gewünschtes Arbeitsmodell: hybrid' \
  '- Wunschgehalt verwenden: nein' \
  '- Gehaltslogik: manuelle Angabe bevorzugen' > "$test_root/personal.md"
printf '%s\n' '# Testprofil' > "$test_root/profile.md"
invoke_tool --firma "Snapshot Firma" --rolle "Snapshot Rolle" --datum "2026-07-14" --umfang A --stammdaten-path "$test_root/personal.md" --profil-path "$test_root/profile.md" --bewerbungen-root "$test_root/snapshot" >/dev/null
snapshot="$test_root/snapshot/Snapshot-Firma/_Arbeitsdateien/2026-07-14--Snapshot-Rolle/Bewerbungsauftrag.json"
grep -Fq '"bewerberDateiname": "TEST.PERSON"' "$snapshot" || fail "Dateiname-Name wurde nicht übernommen."
grep -Fq '"stellenart": "Vollzeit"' "$snapshot" || fail "Stellenart wurde nicht in den Snapshot übernommen."
grep -Fq '"arbeitsmodell": "hybrid"' "$snapshot" || fail "Arbeitsmodell wurde nicht in den Snapshot übernommen."

printf 'JOB-ONE\n' > "$test_root/job-one.md"
printf 'JOB-TWO\n' > "$test_root/job-two.md"
invoke_tool --firma "A+B" --rolle "Audit" --datum "2026-07-14" --umfang A --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/collision" >/dev/null
set +e
invoke_tool --firma "A B" --rolle "Audit" --datum "2026-07-14" --umfang A --stellenbeschreibung-path "$test_root/job-two.md" --bewerbungen-root "$test_root/collision" >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Slug-Kollision wurde nicht abgelehnt."
grep -Fqx 'JOB-ONE' "$test_root/collision/A-B/_Arbeitsdateien/2026-07-14--Audit/Kandidat/Stellenbeschreibung.md" || fail "Vorhandene Stellenbeschreibung wurde überschrieben."
[[ -z "$(find "$test_root/collision/A-B/2026-07-14--Audit" -mindepth 1 -print -quit)" ]] || fail "Finaler Ordner wurde vor der Freigabe befüllt."

invoke_tool --firma "Fortsetzung Firma" --rolle "Fortsetzung Rolle" --datum "2026-07-14" --umfang A --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/resume" >/dev/null
invoke_tool --firma "Fortsetzung Firma" --rolle "Fortsetzung Rolle" --datum "2026-07-14" --umfang A --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/resume" --fortsetzen >/dev/null
resume_work="$test_root/resume/Fortsetzung-Firma/_Arbeitsdateien/2026-07-14--Fortsetzung-Rolle"
sed -i -E 's/"schemaVersion"[[:space:]]*:[[:space:]]*4/"schemaVersion": 2/' "$resume_work/Bewerbungsauftrag.json"
sed -i -E '/^- Dokumentmodus:/d; /^- Dokumentumfang:/d' "$resume_work/Arbeitsnotizen.md"
set +e
invoke_tool --firma "Fortsetzung Firma" --rolle "Fortsetzung Rolle" --datum "2026-07-14" --umfang C --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/resume" --fortsetzen >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Legacy-Vollauftrag wurde mit einem engeren Dokumentumfang fortgesetzt."

invoke_tool --firma "Typ Firma" --rolle "Typ Rolle" --datum "2026-07-14" --umfang A --bewerbungen-root "$test_root/schema-types" >/dev/null
typed_work="$test_root/schema-types/Typ-Firma/_Arbeitsdateien/2026-07-14--Typ-Rolle"
typed_order="$typed_work/Bewerbungsauftrag.json"
typed_baseline="$test_root/schema-types-baseline.json"
cp -- "$typed_order" "$typed_baseline"
for invalid_schema in '"4"' true 4.0; do
  cp -- "$typed_baseline" "$typed_order"
  sed -i -E "s/\"schemaVersion\"[[:space:]]*:[[:space:]]*4/\"schemaVersion\": $invalid_schema/" "$typed_order"
  assert_json_parses "$typed_order"
  set +e
  invoke_tool --firma "Typ Firma" --rolle "Typ Rolle" --datum "2026-07-14" --umfang A --bewerbungen-root "$test_root/schema-types" --fortsetzen >/dev/null 2>&1
  code=$?
  set -e
  [[ $code -eq 2 ]] || fail "Nicht-ganzzahlige schemaVersion $invalid_schema wurde beim Fortsetzen akzeptiert."
done
for boolean_field in anschreiben emailNachricht emailAlleinBestaetigt; do
  cp -- "$typed_baseline" "$typed_order"
  sed -i -E "s/(\"$boolean_field\"[[:space:]]*:[[:space:]]*)(true|false)/\\1\"\\2\"/" "$typed_order"
  assert_json_parses "$typed_order"
  set +e
  invoke_tool --firma "Typ Firma" --rolle "Typ Rolle" --datum "2026-07-14" --umfang A --bewerbungen-root "$test_root/schema-types" --fortsetzen >/dev/null 2>&1
  code=$?
  set -e
  [[ $code -eq 2 ]] || fail "Stringifizierter Scope-Boolean $boolean_field wurde beim Fortsetzen akzeptiert."
done
cp -- "$typed_baseline" "$typed_order"

mkdir -p "$test_root/incomplete/Audit-Firma/2026-07-14--Audit-Rolle"
set +e
invoke_tool --firma "Audit Firma" --rolle "Audit Rolle" --datum "2026-07-14" --umfang A --bewerbungen-root "$test_root/incomplete" --fortsetzen >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Unvollständige Bewerbung wurde blind fortgesetzt."

invoke_tool --firma "Verzeichnis Firma" --rolle "Verzeichnis Rolle" --datum "2026-07-14" --umfang A --bewerbungen-root "$test_root/job-directory" >/dev/null
job_path="$test_root/job-directory/Verzeichnis-Firma/_Arbeitsdateien/2026-07-14--Verzeichnis-Rolle/Kandidat/Stellenbeschreibung.md"
mkdir "$job_path"
set +e
invoke_tool --firma "Verzeichnis Firma" --rolle "Verzeichnis Rolle" --datum "2026-07-14" --umfang A --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/job-directory" --fortsetzen >/dev/null 2>&1
code=$?
set -e
[[ $code -ne 0 ]] || fail "Stellenbeschreibungs-Verzeichnis wurde beim Fortsetzen akzeptiert."
[[ -z "$(find "$job_path" -mindepth 1 -print -quit)" ]] || fail "Quelldatei wurde in das Stellenbeschreibungs-Verzeichnis kopiert."

invoke_tool --firma "Nur CV" --rolle "Audit" --datum "2026-07-14" --umfang C --bewerbungen-root "$test_root/scope-c" >/dev/null
scope_c="$test_root/scope-c/Nur-CV/_Arbeitsdateien/2026-07-14--Audit"
[[ -f "$scope_c/Lebenslauf--Nur-CV--ENTWURF.html" ]] || fail "Umfang C erzeugte keinen Lebenslaufentwurf."
[[ ! -e "$scope_c/Anschreiben--Nur-CV--ENTWURF.html" && ! -e "$scope_c/Email-Nachricht--Nur-CV--ENTWURF.md" ]] || fail "Umfang C erzeugte abgewählte Dokumente."

invoke_tool --firma "Nur Brief" --rolle "Audit" --datum "2026-07-14" --umfang D --bewerbungen-root "$test_root/scope-d" >/dev/null
scope_d="$test_root/scope-d/Nur-Brief/_Arbeitsdateien/2026-07-14--Audit"
[[ -f "$scope_d/Anschreiben--Nur-Brief--ENTWURF.html" ]] || fail "Umfang D erzeugte keinen Anschreibenentwurf."
[[ ! -e "$scope_d/Lebenslauf--Nur-Brief--ENTWURF.html" && ! -e "$scope_d/Email-Nachricht--Nur-Brief--ENTWURF.md" ]] || fail "Umfang D erzeugte abgewählte Dokumente."
set +e
invoke_tool --firma "Nur Brief" --rolle "Audit" --datum "2026-07-14" --umfang E --dokumente anschreiben --bewerbungen-root "$test_root/scope-d" --fortsetzen >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Auswahl D wurde beim Fortsetzen trotz abweichender Auswahl E akzeptiert."

invoke_tool --firma "Freie Auswahl" --rolle "Audit" --datum "2026-07-14" --umfang E --dokumente lebenslauf,anschreiben --bewerbungen-root "$test_root/scope-e" >/dev/null
scope_e="$test_root/scope-e/Freie-Auswahl/_Arbeitsdateien/2026-07-14--Audit"
[[ -f "$scope_e/Lebenslauf--Freie-Auswahl--ENTWURF.html" && -f "$scope_e/Anschreiben--Freie-Auswahl--ENTWURF.html" ]] || fail "Umfang E erzeugte nicht die gewählte Kombination."
[[ ! -e "$scope_e/Email-Nachricht--Freie-Auswahl--ENTWURF.md" ]] || fail "Umfang E erzeugte eine abgewählte E-Mail."

set +e
invoke_tool --firma "Nur E-Mail" --rolle "Audit" --datum "2026-07-14" --umfang E --dokumente email_nachricht --bewerbungen-root "$test_root/scope-email" >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "E-Mail-only wurde ohne ausdrückliche Bestätigung akzeptiert."
[[ ! -e "$test_root/scope-email" ]] || fail "Unbestätigtes E-Mail-only erzeugte eine Teilstruktur."

invoke_tool --firma "Nur E-Mail" --rolle "Audit" --datum "2026-07-14" --umfang E --dokumente email_nachricht --email-allein-bestaetigt --bewerbungen-root "$test_root/scope-email" >/dev/null
scope_email="$test_root/scope-email/Nur-E-Mail/_Arbeitsdateien/2026-07-14--Audit"
scope_email_draft="$scope_email/Email-Nachricht--Nur-E-Mail--ENTWURF.md"
[[ -f "$scope_email_draft" ]] || fail "Bestätigtes E-Mail-only erzeugte keinen E-Mail-Entwurf."
[[ ! -e "$scope_email/Lebenslauf--Nur-E-Mail--ENTWURF.html" && ! -e "$scope_email/Anschreiben--Nur-E-Mail--ENTWURF.html" ]] || fail "E-Mail-only erzeugte nicht ausgewählte Anlagenentwürfe."
grep -Fq 'hiermit bewerbe ich mich' "$scope_email_draft" || fail "E-Mail-only enthält keine anlagenfreie Bewerbungsformulierung."
if grep -Eiq 'anbei|Bewerbungsunterlagen' "$scope_email_draft"; then
  fail "E-Mail-only behauptet fälschlich vorhandene Bewerbungsanlagen."
fi
scope_email_order="$scope_email/Bewerbungsauftrag.json"
assert_json_parses "$scope_email_order"
grep -Fq '"lebenslauf": "nicht_enthalten"' "$scope_email_order" || fail "E-Mail-only speichert einen falschen Lebenslaufumfang."
grep -Fq '"anschreiben": false' "$scope_email_order" || fail "E-Mail-only speichert ein Anschreiben."
grep -Fq '"emailNachricht": true' "$scope_email_order" || fail "E-Mail-only speichert keine E-Mail."
grep -Fq '"emailAlleinBestaetigt": true' "$scope_email_order" || fail "E-Mail-only speichert die ausdrückliche Bestätigung nicht."

printf '[OK] Bash-Regressionssuite bestanden.\n'
