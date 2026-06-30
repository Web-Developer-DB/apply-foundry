# bewerbungs-agent

`bewerbungs-agent` ist ein modularer KI-gestützter Bewerbungsagent für deutsche Bewerbungsunterlagen.

Aus einer Stellenbeschreibung erzeugt der Agent:

- einen bewerbungsspezifischen Lebenslauf als HTML
- ein individuelles Anschreiben als HTML
- eine kurze E-Mail-Nachricht
- eine Analyse der Stellenanzeige
- einen Qualitätscheck

Das Projekt ist so getrennt, dass öffentliche Agentenlogik auf GitHub liegen kann, während echte private Daten lokal unter `Private/` bleiben.

## 1. Schnellstart

### Bewerbung direkt durch den Agenten erstellen

Dem Agenten diesen Auftrag geben:

```text
Nutze Prompts/00_AGENTEN_START_HIER.md und erstelle eine Bewerbung für diese Stellenbeschreibung:

[Stellenbeschreibung hier einfügen]
```

Der Agent liest dann:

1. private Daten aus `Private/Daten/`
2. öffentliche Agentenregeln aus `Prompts/`
3. Designvorlagen aus `Vorlagen/`

Die fertige Bewerbung wird gespeichert unter:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/
```

### Bewerbungsordner vorher anlegen

Windows 11 / PowerShell:

```powershell
.\Tools\Neue-Bewerbung.ps1 -Firma "Team System House GmbH" -Rolle "IT-Support"
```

Linux / Bash:

```bash
bash Tools/neue-bewerbung.sh --firma "Team System House GmbH" --rolle "IT-Support"
```

Beide Skripte erzeugen dieselbe private Ordnerstruktur:

```text
Private/Bewerbungen/Team-System-House-GmbH/YYYY-MM-DD--IT-Support/
Private/Bewerbungen/Team-System-House-GmbH/_Arbeitsdateien/YYYY-MM-DD--IT-Support/
```

Die Skripte legen Platzhalter und Entwürfe in `_Arbeitsdateien` ab. Im finalen Bewerbungsordner entstehen dadurch keine unfertigen `Analyse.md`, `Email-Nachricht--FIRMA.md` oder `Qualitaetscheck.md` Dateien.

## 2. Private Daten einrichten

Echte persönliche Daten gehören ausschließlich hierhin:

```text
Private/Daten/
```

Benötigte Dateien:

```text
Private/Daten/01_PERSOENLICHE_DATEN.md
Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md
```

Wenn der Ordner fehlt, die Beispielstruktur verwenden:

```text
Private.example/Daten/
```

Vorgehen:

1. `Private/Daten/` lokal erstellen.
2. Beispiele aus `Private.example/Daten/` kopieren.
3. `.example` aus den Dateinamen entfernen.
4. Platzhalter durch echte private Daten ersetzen.

Wichtig: `Private/` ist in `.gitignore` eingetragen und darf nicht veröffentlicht werden.

## 3. Was ist privat?

Privat und nicht für GitHub:

```text
Private/
Private/Daten/
Private/Bewerbungen/
Private/Bewertungen/
Private/LebenslaufUniversal/
Private/Archiv/
```

Zusätzlich werden alte private Root-Ordner ignoriert, falls sie später versehentlich wieder entstehen:

```text
Bewerbungen/
Bewertungen/
LebenslaufUniversal/
Archiv/
```

Privat sind insbesondere Kontaktdaten, Profil, Berufserfahrung, Projekte, Skills, generierte Bewerbungen, Stellenbeschreibungen, Bewertungen, Notizen und Exporte.

## 4. Was darf auf GitHub?

Öffentlich geeignet:

```text
Prompts/
Vorlagen/
Tools/
Private.example/
README.md
.gitignore
.gitattributes
```

Diese Dateien dürfen keine echten privaten Bewerberdaten enthalten.

## 5. Wichtige Dateien

- `Prompts/00_AGENTEN_START_HIER.md`: zentrale Startdatei für den Agenten.
- `Private/Daten/01_PERSOENLICHE_DATEN.md`: lokale private Kontaktdaten.
- `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md`: lokales privates Profil, Skills, Grenzen und Belege.
- `Prompts/03_LEBENSLAUF_REGELN.md`: Aufbau, Länge, Priorisierung und Stil des Lebenslaufs.
- `Prompts/04_ANSCHREIBEN_REGELN.md`: Aufbau, Tonalität und Inhalt des Anschreibens.
- `Prompts/05_EMAIL_NACHRICHT_REGELN.md`: kurze E-Mail-Nachricht.
- `Prompts/06_ROLLENLOGIK.md`: Gewichtung je nach Stellenbeschreibung.
- `Prompts/07_WAHRHEIT_UND_GRENZEN.md`: keine erfundenen Angaben.
- `Prompts/08_HTML_CSS_DESIGNREGELN.md`: A4, Firefox-Druck und HTML/CSS-Regeln.
- `Prompts/09_QUALITAETSCHECK.md`: Checkliste vor Abschluss.
- `Prompts/10_DATEI_UND_ORDNER_REGELN.md`: Struktur, Namen, Slugs und Arbeitsdateien.

## 6. Ausgabe pro Bewerbung

Finaler Bewerbungsordner:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/
```

Pflichtdateien:

- `Stellenbeschreibung.md`
- `Analyse.md`
- `Lebenslauf--FIRMA.html`
- `Anschreiben--FIRMA.html`
- `Email-Nachricht--FIRMA.md`
- `Qualitaetscheck.md`
- `Druck-Hinweis.md`

Arbeitsdateien:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/
```

Typische Arbeitsdateien:

- `Stellenbeschreibung--ENTWURF.md`
- `Analyse--ENTWURF.md`
- `Lebenslauf--FIRMA--ENTWURF.html`
- `Anschreiben--FIRMA--ENTWURF.html`
- `Email-Nachricht--FIRMA--ENTWURF.md`
- `Qualitaetscheck--ENTWURF.md`
- `Offene_Fragen--ENTWURF.md`
- `Arbeitsnotizen.md`

Diese Dateien sind nicht final und dürfen nicht unverändert versendet werden.

## 7. Windows und Linux

Das Projekt soll unter Windows 11 PowerShell und Linux Bash gleich funktionieren.

Parameter:

- PowerShell: `-Firma`, `-Rolle`, `-Datum`, `-StellenbeschreibungPath`, `-BewerbungenRoot`
- Bash: `--firma`, `--rolle`, `--datum`, `--stellenbeschreibung-path`, `--bewerbungen-root`

Standardausgabeordner beider Skripte:

```text
Private/Bewerbungen/
```

Projektinterne Pfade werden in der Dokumentation mit `/` geschrieben. Unter Windows darf PowerShell intern `\` verwenden.

## 8. Vorlagen

Aktive öffentliche Vorlagen liegen in `Vorlagen/`:

- `Designreferenz-Lebenslauf.html`
- `Designreferenz-Anschreiben.html`

Vorlagen dürfen nur Platzhalter enthalten, keine echten Bewerberdaten.

## 9. Drucken und PDF

Die HTML-Dateien sind für A4 vorbereitet.

Wenn Dateiname, URL, Datum oder Seitenzahl im Ausdruck erscheinen, kommt das aus dem Firefox-Druckdialog und nicht aus der HTML-Datei.

Vor dem finalen PDF-Export oder Druck in Firefox:

1. `Strg + P` drücken.
2. `Weitere Einstellungen` öffnen.
3. `Kopf- und Fußzeilen drucken` deaktivieren.
4. Skalierung auf `100%` stellen.
5. Ränder auf `Keine` stellen.

Bei Einseiten-Dokumenten nutzt der Print-Modus eine feste A4-Fläche von `210mm x 297mm`. Wenn ein Lebenslauf bewusst zwei Seiten braucht, sollen zwei getrennte A4-Seitencontainer erstellt werden.

## 10. Typischer Agentenablauf

1. Stellenbeschreibung lesen.
2. Firma und Zielrolle erkennen.
3. Private Daten aus `Private/Daten/` lesen.
4. Agentenregeln aus `Prompts/` lesen.
5. Rollenstrategie bestimmen.
6. Bewerbungsordner unter `Private/Bewerbungen/` erstellen.
7. Analyse speichern.
8. Lebenslauf erstellen.
9. Anschreiben erstellen.
10. E-Mail-Nachricht erstellen.
11. Druckfähigkeit prüfen.
12. Qualitätscheck speichern.
13. Kurz berichten, wo die Dateien liegen.

## 11. Anpassung

| Ziel | Datei |
| --- | --- |
| Kontaktdaten ändern | `Private/Daten/01_PERSOENLICHE_DATEN.md` |
| Profil, Skills, Projekte ändern | `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` |
| Lebenslauf-Aufbau ändern | `Prompts/03_LEBENSLAUF_REGELN.md` |
| Anschreiben-Stil ändern | `Prompts/04_ANSCHREIBEN_REGELN.md` |
| E-Mail-Text ändern | `Prompts/05_EMAIL_NACHRICHT_REGELN.md` |
| Rollenlogik ändern | `Prompts/06_ROLLENLOGIK.md` |
| Wahrheitsregeln ändern | `Prompts/07_WAHRHEIT_UND_GRENZEN.md` |
| HTML/CSS ändern | `Prompts/08_HTML_CSS_DESIGNREGELN.md` |
| Qualitätscheck ändern | `Prompts/09_QUALITAETSCHECK.md` |
| Ordnerstruktur ändern | `Prompts/10_DATEI_UND_ORDNER_REGELN.md` |
| Windows-Skript ändern | `Tools/Neue-Bewerbung.ps1` |
| Linux-Skript ändern | `Tools/neue-bewerbung.sh` |

## 12. Projektstruktur

Öffentliche Struktur:

```text
bewerbungs-agent/
├─ README.md
├─ .gitignore
├─ .gitattributes
├─ Prompts/
├─ Vorlagen/
├─ Tools/
└─ Private.example/
```

Lokale private Struktur:

```text
Private/
├─ Daten/
├─ Bewerbungen/
├─ Bewertungen/
├─ LebenslaufUniversal/
└─ Archiv/
```

## 13. GitHub-Sicherheit

Vor einem Commit prüfen:

```powershell
git status --short
```

In dieser Ausgabe dürfen keine echten Dateien aus `Private/` erscheinen.

Optional prüfen:

```powershell
git status --short --ignored
```

`!! Private/` ist normal und bedeutet, dass der private Ordner ignoriert wird.

## 14. Entwicklerhinweise

- `.gitattributes` erzwingt LF-Zeilenenden für `.sh`.
- `.gitignore` schützt private Daten und generierte Dokumente.
- Öffentliche Beispiel-Dateien liegen in `Private.example/`.
- Die Hilfsskripte sollen dieselbe Ordnerstruktur erzeugen.
- Finale Bewerbungsdateien dürfen keine sichtbaren Platzhalter enthalten.