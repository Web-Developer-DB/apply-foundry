# Datenstruktur

Dieser Ordner zeigt die empfohlene Struktur für private Bewerberdaten. Die beiden `.example.md`-Dateien enthalten frei erfundene Beispieldaten, damit sichtbar wird, wie die Dateien ausgefüllt werden können.

Kopiere die Dateien lokal nach `Private/Daten/`, entferne bei den beiden Datendateien `.example` aus dem Dateinamen und ersetze alle fiktiven Beispieldaten durch echte lokale Angaben.

## Datei 01: Persönliche Daten

`01_PERSOENLICHE_DATEN.md` ist nur für Identität, Kontakt und Bewerbungslogistik zuständig.

Dazu gehören:

- Name, Vorname, Nachname und Dateiname-Name
- Adresse, Telefon, E-Mail
- GitHub, Portfolio und andere öffentliche Profile
- Verfügbarkeit, frühester Eintrittstermin und gewünschte Stellenart
- gewünschtes Arbeitsmodell, Region, Pendeldistanz und Reisebereitschaft
- Gehaltswunsch und Gehaltslogik
- optionale persönliche Angaben, wenn sie wirklich verwendet werden sollen

Kopiere keine Auswahltexte wie `[Vollzeit / Teilzeit]` unverändert in die echte private Datei. Trage eine echte Entscheidung oder einen eindeutigen Wert wie `nicht festgelegt` ein. Vor Bewerbungen prüft `python3 Tools/bewerbung.py stammdaten` diese Datei; ungeklärte Kernentscheidungen können die finale Veröffentlichung blockieren.

Nicht hier eintragen:

- Berufserfahrung
- Ausbildung, Weiterbildung oder Schulbildung
- Kenntnisse, Projekte, Zielrollen oder Kurzprofile

## Optionales Passfoto

Ein Bewerbungsfoto ist freiwillig. Wenn individuelle Lebensläufe automatisch ein Foto verwenden sollen, lege die eigene PNG-Datei ausschließlich und mit exakter Schreibweise hier ab:

`Private/Daten/Passfoto.png`

Fehlt die Datei, erstellt der Agent ohne Rückfrage einen Lebenslauf ohne Foto. Lege kein fiktives oder öffentliches Beispielbild unter `Private.example/` ab. Das Original bleibt privat, wird nicht verändert und nicht separat nach `Versand/` kopiert; der individuelle Lebenslauf enthält bei Verwendung nur eine bytegleiche eingebettete Datenressource. Universelle Lebensläufe bleiben unabhängig von dieser Datei unverändert.

Hinweis zum Gehaltswunsch:

- Eine manuelle Gehaltsangabe in Datei `01` hat Vorrang.
- Eine automatische Schätzung erfolgt nur bei ausdrücklicher Aktivierung und nutzt eine aktuelle, nachvollziehbare Quelle sowie Stellenbeschreibung, Zielrolle, Seniorität, einschlägige Berufserfahrung, Region, Arbeitsmodell und Stellenart. Alter, Geschlecht und andere geschützte persönliche Merkmale bleiben unberücksichtigt.
- Wenn keine belastbare aktuelle Datengrundlage verfügbar ist, wird keine Zahl geraten, sondern eine offene Frage dokumentiert.
- Wenn die Stellenanzeige keinen Gehaltswunsch verlangt und `nur wenn in der Stellenanzeige verlangt` gesetzt ist, wird im Anschreiben kein Gehalt genannt.

## Datei 02: Bewerberprofil und Positionierung

`02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` ist die fachliche Quelle für Lebenslauf, Anschreiben und Rollenstrategie.

Dazu gehören:

- Zielrollen und Positionierung
- Berufserfahrung und übertragbare Erfahrung
- Ausbildung, Umschulung, Weiterbildung und Schulbildung
- technische Kompetenzen, Sprachen und Soft Skills
- private IT-Praxis, Home-Lab und Projekte
- Grenzen und Hinweise, was nicht behauptet werden darf

Die fachlichen Angaben sollen nach Belegarten getrennt werden:

- `BERUFLICH BELEGT`: berufliche Stationen und Tätigkeiten
- `ÜBERTRAGBAR`: beruflich belegte Stärken, die in andere Rollen übertragen werden können
- `WEITERBILDUNG`: Kurse, Umschulungen, Zertifikate und Qualifikationen
- `PROJEKTPRAXIS`: Lern-, Portfolio- oder Weiterbildungsprojekte
- `PRIVATE PRAXIS / HOME-LAB`: private Systeme und selbstständige Praxis
- `GRUNDLAGEN / VERSTÄNDNIS`: Basiswissen ohne professionelle Routine
- `EINARBEITUNGSZIEL`: Themen für eine neue Rolle
- `NICHT BEHAUPTEN`: Sperrliste für nicht belegte Erfahrung oder Verantwortung

Nicht hier eintragen:

- Adresse, Telefon, E-Mail oder Dateiname-Name
- persönliche optionale Angaben ohne fachlichen Bezug

## Konfliktregel

Wenn Angaben doppelt oder widersprüchlich vorkommen:

- Kontakt und Dateinamen kommen aus Datei `01`.
- Fachliche Lebenslaufdaten kommen aus Datei `02`.
- Widersprüche sollen in `Offene_Fragen.md` dokumentiert werden.
- Fehlende Angaben werden nicht erfunden.

## Pflegeprinzip

Eine Information soll nur an einer Stelle gepflegt werden. Wenn neue Daten ergänzt werden, zuerst prüfen, ob sie persönliche Stammdaten oder fachliche Lebenslaufdaten sind.
