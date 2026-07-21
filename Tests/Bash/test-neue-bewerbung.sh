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

bash -n "$tool"

set +e
bash "$tool" --firma "Audit Firma" --rolle "Audit Rolle" --datum "2026-99-99" --bewerbungen-root "$test_root/invalid-date" >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Unmögliches Datum wurde nicht mit Exitcode 2 abgelehnt."
[[ ! -e "$test_root/invalid-date" ]] || fail "Ungültiges Datum erzeugte eine Ausgabe."

mkdir -p "$test_root/source-directory"
set +e
bash "$tool" --firma "Audit Firma" --rolle "Audit Rolle" --datum "2026-07-14" --stellenbeschreibung-path "$test_root/source-directory" --bewerbungen-root "$test_root/directory-source" >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Verzeichnisquelle wurde nicht mit Exitcode 2 abgelehnt."
[[ ! -e "$test_root/directory-source" ]] || fail "Verzeichnisquelle erzeugte eine Teilstruktur."

bash "$tool" --firma 'A&B <X>' --rolle 'R "Q"' --datum '2026-07-14' --bewerbungen-root "$test_root/escaping" >/dev/null
html="$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Lebenslauf--AundB-X--ENTWURF.html"
grep -Fq 'A&amp;B &lt;X&gt;' "$html" || fail "Firmenname wurde nicht korrekt HTML-kodiert."
grep -Fq 'R &quot;Q&quot;' "$html" || fail "Rollenname wurde nicht korrekt HTML-kodiert."
[[ -f "$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Bewerbungsauftrag.json" ]] || fail "Bewerbungsauftrag wurde nicht erzeugt."
[[ -d "$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Kandidat" ]] || fail "Kandidatenordner wurde nicht erzeugt."
auftrag="$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Bewerbungsauftrag.json"
matrix="$test_root/escaping/AundB-X/_Arbeitsdateien/2026-07-14--R-Q/Anforderungsmatrix--ENTWURF.json"
grep -Fq '"schemaVersion": 2' "$auftrag" || fail "Bewerbungsauftrag verwendet nicht Schema 2."
grep -Fq '"bewerbungsentscheidung": "noch_festzulegen"' "$auftrag" || fail "Bewerbungsentscheidung fehlt im Auftrag."
grep -Fq '"profillinksModus": "noch_festzulegen"' "$auftrag" || fail "Profillink-Modus fehlt im Auftrag."
grep -Fq '"gewichtung": "hoch"' "$matrix" || fail "Matrixentwurf enthält keine Gewichtung."

printf '%s\n' \
  '- Dateiname-Name: TEST.PERSON' \
  '- Gewünschte Stellenart: Vollzeit' \
  '- Gewünschtes Arbeitsmodell: hybrid' \
  '- Wunschgehalt verwenden: nein' \
  '- Gehaltslogik: manuelle Angabe bevorzugen' > "$test_root/personal.md"
printf '%s\n' '# Testprofil' > "$test_root/profile.md"
bash "$tool" --firma "Snapshot Firma" --rolle "Snapshot Rolle" --datum "2026-07-14" --stammdaten-path "$test_root/personal.md" --profil-path "$test_root/profile.md" --bewerbungen-root "$test_root/snapshot" >/dev/null
snapshot="$test_root/snapshot/Snapshot-Firma/_Arbeitsdateien/2026-07-14--Snapshot-Rolle/Bewerbungsauftrag.json"
grep -Fq '"bewerberDateiname": "TEST.PERSON"' "$snapshot" || fail "Dateiname-Name wurde nicht übernommen."
grep -Fq '"stellenart": "Vollzeit"' "$snapshot" || fail "Stellenart wurde nicht in den Snapshot übernommen."
grep -Fq '"arbeitsmodell": "hybrid"' "$snapshot" || fail "Arbeitsmodell wurde nicht in den Snapshot übernommen."

printf 'JOB-ONE\n' > "$test_root/job-one.md"
printf 'JOB-TWO\n' > "$test_root/job-two.md"
bash "$tool" --firma "A+B" --rolle "Audit" --datum "2026-07-14" --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/collision" >/dev/null
set +e
bash "$tool" --firma "A B" --rolle "Audit" --datum "2026-07-14" --stellenbeschreibung-path "$test_root/job-two.md" --bewerbungen-root "$test_root/collision" >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Slug-Kollision wurde nicht abgelehnt."
grep -Fqx 'JOB-ONE' "$test_root/collision/A-B/_Arbeitsdateien/2026-07-14--Audit/Kandidat/Stellenbeschreibung.md" || fail "Vorhandene Stellenbeschreibung wurde überschrieben."
[[ -z "$(find "$test_root/collision/A-B/2026-07-14--Audit" -mindepth 1 -print -quit)" ]] || fail "Finaler Ordner wurde vor der Freigabe befüllt."

bash "$tool" --firma "Fortsetzung Firma" --rolle "Fortsetzung Rolle" --datum "2026-07-14" --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/resume" >/dev/null
bash "$tool" --firma "Fortsetzung Firma" --rolle "Fortsetzung Rolle" --datum "2026-07-14" --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/resume" --fortsetzen >/dev/null

mkdir -p "$test_root/incomplete/Audit-Firma/2026-07-14--Audit-Rolle"
set +e
bash "$tool" --firma "Audit Firma" --rolle "Audit Rolle" --datum "2026-07-14" --bewerbungen-root "$test_root/incomplete" --fortsetzen >/dev/null 2>&1
code=$?
set -e
[[ $code -eq 2 ]] || fail "Unvollständige Bewerbung wurde blind fortgesetzt."

bash "$tool" --firma "Verzeichnis Firma" --rolle "Verzeichnis Rolle" --datum "2026-07-14" --bewerbungen-root "$test_root/job-directory" >/dev/null
job_path="$test_root/job-directory/Verzeichnis-Firma/_Arbeitsdateien/2026-07-14--Verzeichnis-Rolle/Kandidat/Stellenbeschreibung.md"
mkdir "$job_path"
set +e
bash "$tool" --firma "Verzeichnis Firma" --rolle "Verzeichnis Rolle" --datum "2026-07-14" --stellenbeschreibung-path "$test_root/job-one.md" --bewerbungen-root "$test_root/job-directory" --fortsetzen >/dev/null 2>&1
code=$?
set -e
[[ $code -ne 0 ]] || fail "Stellenbeschreibungs-Verzeichnis wurde beim Fortsetzen akzeptiert."
[[ -z "$(find "$job_path" -mindepth 1 -print -quit)" ]] || fail "Quelldatei wurde in das Stellenbeschreibungs-Verzeichnis kopiert."

printf '[OK] Bash-Regressionssuite bestanden.\n'
