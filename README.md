# bewerbungs-agent

`bewerbungs-agent` ist ein modularer KI-gestützter Bewerbungsagent für deutsche Bewerbungsunterlagen. Er ist bewusst branchenneutral: Das konkrete Bewerbungsprofil entsteht aus der Stellenbeschreibung und den privaten Profildaten.

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

Der Agent erstellt den passenden Bewerbungsordner automatisch und speichert die fertige Bewerbung unter:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/
```

### Optional: Bewerbungsordner mit Hilfsskript vorbereiten

Normalerweise erstellt der Agent den Bewerbungsordner automatisch. Die folgenden Skripte sind nur optional, zum Beispiel wenn du die Ordnerstruktur vorab vorbereiten oder testen möchtest.

Windows 11 / PowerShell:

```powershell
.\Tools\Neue-Bewerbung.ps1 -Firma "Muster GmbH" -Rolle "Sachbearbeitung"
```

Linux / Bash:

```bash
bash Tools/neue-bewerbung.sh --firma "Muster GmbH" --rolle "Sachbearbeitung"
```

Beide Skripte erzeugen dieselbe private Ordnerstruktur:

```text
Private/Bewerbungen/Muster-GmbH/YYYY-MM-DD--Sachbearbeitung/
Private/Bewerbungen/Muster-GmbH/_Arbeitsdateien/YYYY-MM-DD--Sachbearbeitung/
```

Die Skripte legen Platzhalter und Entwürfe in `_Arbeitsdateien` ab. Im finalen Bewerbungsordner entstehen dadurch keine unfertigen `Analyse.md`, `Email-Nachricht--FIRMA.md` oder `Qualitaetscheck.md` Dateien.

### Bewerbung technisch prüfen

Nach jeder finalen Bewerbung sollte der statische Prüfer laufen:

```powershell
.\Tools\Pruefe-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Optional kann ein Browser-Layoutcheck Screenshots im privaten Arbeitsordner erzeugen:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Der statische Prüfer ist der technische Mindestcheck. Der Browser-Layoutcheck ist hilfreich, gilt aber nur als bestanden, wenn die erwarteten Dateien wirklich unter `_Arbeitsdateien` erzeugt wurden.

## 2. Empfohlene Agenten und Modelle

Die Empfehlung ist bewusst nach einfacher Bedienung sortiert. Ziel ist: möglichst wenig Einrichtung, keine API-Schlüssel und keine komplexe Entwicklerumgebung für normale Anwender.

| Empfehlung | Geeignet für | Kosten/Setup | Warum |
| --- | --- | --- | --- |
| **Gemini App, optional mit eigenem Gem** | normale Anwender | Google-Konto, Browser oder Smartphone; kostenloser Einstieg möglich, je nach Konto/Funktionsumfang auch kostenpflichtig | Sehr niedrige Einstiegshürde. Ein Gem kann feste Anweisungen und Wissensdateien nutzen. Gut für Nutzer, die Stellenbeschreibung und Ergebnisdateien manuell kopieren oder herunterladen möchten. |
| **Gemini Code Assist in VS Code** | Nutzer mit etwas IT-Verständnis | Google-Konto und VS Code; kostenloser Einstieg möglich | Gute leicht zugängliche Agentenlösung direkt in VS Code. Sinnvoll, wenn der Agent Projektdateien lesen und mit der lokalen Ordnerstruktur arbeiten soll. |
| **Codex in VS Code** | Projektpflege und fortgeschrittene Nutzer | ChatGPT-/Codex-Zugang und VS Code; je nach Konto kostenpflichtig | Beste Wahl für dieses Repository, wenn Dateien geändert, Audits gemacht, Skripte geprüft oder Git sauber gehalten werden sollen. Für reine Endanwender etwas technischer. |
| **ChatGPT Web/Desktop** | Textqualität und manuelle Nutzung | OpenAI-Konto; kostenloser Einstieg möglich, bessere Modelle/Funktionen je nach Konto kostenpflichtig | Gut für Lebenslauf- und Anschreiben-Formulierungen. Einfach zugänglich, aber ohne automatische lokale Ordner- und Dateiablage wie ein Editor-Agent. |
| **LM Studio** | lokale Nutzung mit Datenschutzfokus | kostenlose lokale App, aber passende Hardware und Modell-Download nötig | Gute lokale Oberfläche für Nutzer, die KI-Modelle auf dem eigenen Rechner ausführen möchten. Mehr Einrichtung und passende Hardware nötig. |
| **Ollama** | technischere lokale Nutzung | kostenlos lokal, aber Terminal und Modell-Download nötig | Stark für lokale Modelle und Automatisierung, aber eher terminalorientiert und deshalb nicht der einfachste Standardweg für normale Verbraucher. |

Empfohlener Standard für normale Anwender: **Gemini App mit eigenem Gem**.

Empfohlener Standard für VS-Code-Nutzer: **Gemini Code Assist** oder **Codex in VS Code**.

Empfohlene lokale Datenschutzoption: **LM Studio**. Ollama nur dann, wenn Terminalnutzung kein Problem ist.

Nicht als Standard empfohlen: API-only-Setups, komplexe lokale Agentenframeworks oder Anbieter, bei denen Nutzer erst API-Schlüssel, Zusatzdienste und mehrere Integrationsschritte einrichten müssen.

Wichtig: Keine konkrete Modellversion fest in die Prompts schreiben. Die Dienste wechseln ihre Standardmodelle. Für die Nutzung gilt deshalb: Das beste verfügbare Modell des gewählten Agenten verwenden und die Ausgabe nach `Prompts/09_QUALITAETSCHECK.md` prüfen.

Offizielle Einstiegspunkte:

- Gemini Gems: <https://support.google.com/gemini/answer/15235603>
- Gemini Code Assist: <https://developers.google.com/gemini-code-assist/docs/overview>
- Codex: <https://openai.com/codex/>
- ChatGPT: <https://chatgpt.com/>
- LM Studio: <https://lmstudio.ai/>
- Ollama: <https://ollama.com/download>

## 3. Lebenslauf-Standard

Der Agent erstellt moderne Lebensläufe für den deutschsprachigen Arbeitsmarkt. Der Lebenslauf soll nicht nur Skills und Projekte zeigen, sondern die klassischen CV-Stationen sauber berücksichtigen:

- Berufserfahrung / berufliche Stationen
- Ausbildung, Studium oder berufliche Bildung
- Schulbildung, sofern vorhanden oder sinnvoll
- Weiterbildungen, Zertifikate und Qualifikationen
- Kenntnisse, Sprachen und relevante Zusatzpraxis

Ziel ist eine klare, recruiterfreundliche DIN-A4-Seite. Wenn wichtige Stationen sonst abgeschnitten, gequetscht oder unübersichtlich würden, erstellt der Agent bewusst einen strukturierten zweiseitigen Lebenslauf. Eine zweite Seite ist erlaubt, wenn sie sauber aufgebaut ist und nicht wie ein zufälliger Rest wirkt.

Projekte, private Praxis und Zusatzkenntnisse werden nur aufgenommen, wenn sie zur Stelle passen oder einen echten Recruiter-Nutzen haben. Sie dürfen formale Stationen wie Ausbildung oder Schulbildung nicht verdrängen.

## 4. Private Daten einrichten

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

## 5. Was ist privat?

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

## 6. Was darf auf GitHub?

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

## 7. Wichtige Dateien

- `Prompts/00_AGENTEN_START_HIER.md`: zentrale Startdatei für den Agenten.
- `Private/Daten/01_PERSOENLICHE_DATEN.md`: lokale private Kontaktdaten.
- `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md`: lokales privates Profil, Skills, Grenzen und Belege.
- `Prompts/03_LEBENSLAUF_REGELN.md`: deutscher CV-Aufbau, formale Stationen, Länge, Priorisierung und Stil des Lebenslaufs.
- `Prompts/04_ANSCHREIBEN_REGELN.md`: Aufbau, Tonalität und Inhalt des Anschreibens.
- `Prompts/05_EMAIL_NACHRICHT_REGELN.md`: kurze E-Mail-Nachricht.
- `Prompts/06_ROLLENLOGIK.md`: neutrale Profil-, Rollen- und Recruiter-Strategie je nach Stellenbeschreibung.
- `Prompts/07_WAHRHEIT_UND_GRENZEN.md`: keine erfundenen Angaben.
- `Prompts/08_HTML_CSS_DESIGNREGELN.md`: A4, Firefox-Druck und HTML/CSS-Regeln.
- `Prompts/09_QUALITAETSCHECK.md`: Checkliste vor Abschluss, inklusive Recruiter-Nutzen und A4-Fit-Check.
- `Prompts/10_DATEI_UND_ORDNER_REGELN.md`: Struktur, Namen, Slugs und Arbeitsdateien.
- `Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md`: technische Schlussprüfung, robuste Suchmuster, statischer Prüfer und optionaler Browser-Layoutcheck.

## 8. Ausgabe pro Bewerbung

Finaler Bewerbungsordner:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/
```

Pflichtdateien:

- `Stellenbeschreibung.md`
- `Analyse.md`
- `Lebenslauf - NACHNAME.VORNAME.html`
- `Anschreiben - NACHNAME.VORNAME.html`
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

Für den Versand per E-Mail oder PDF-Export heißen Lebenslauf und Anschreiben nach Bewerbername:

```text
Lebenslauf - NACHNAME.VORNAME.html
Anschreiben - NACHNAME.VORNAME.html
```

Falls PDFs erstellt werden:

```text
Lebenslauf - NACHNAME.VORNAME.pdf
Anschreiben - NACHNAME.VORNAME.pdf
```

Vorname und Nachname kommen aus `Private/Daten/01_PERSOENLICHE_DATEN.md`. Der Firmenname bleibt im Bewerbungsordner und wird nicht mehr in den finalen Versanddateien verwendet.

## 9. Windows und Linux

Das Projekt soll unter Windows 11 PowerShell und Linux Bash gleich funktionieren.

Parameter:

- PowerShell: `-Firma`, `-Rolle`, `-Datum`, `-StellenbeschreibungPath`, `-BewerbungenRoot`
- Bash: `--firma`, `--rolle`, `--datum`, `--stellenbeschreibung-path`, `--bewerbungen-root`

Standardausgabeordner beider Skripte:

```text
Private/Bewerbungen/
```

Projektinterne Pfade werden in der Dokumentation mit `/` geschrieben. Unter Windows darf PowerShell intern `\` verwenden.

## 10. Vorlagen

Aktive öffentliche Vorlagen liegen in `Vorlagen/`:

- `Designreferenz-Lebenslauf.html`
- `Designreferenz-Anschreiben.html`

Vorlagen dürfen nur Platzhalter enthalten, keine echten Bewerberdaten.

## 11. Drucken und PDF

Die HTML-Dateien sind für A4 vorbereitet.

Wenn Dateiname, URL, Datum oder Seitenzahl im Ausdruck erscheinen, kommt das aus dem Firefox-Druckdialog und nicht aus der HTML-Datei.

Vor dem finalen PDF-Export oder Druck in Firefox:

1. `Strg + P` drücken.
2. `Weitere Einstellungen` öffnen.
3. `Kopf- und Fußzeilen drucken` deaktivieren.
4. Skalierung auf `100%` stellen.
5. Ränder auf `Keine` stellen.

Bei Einseiten-Dokumenten nutzt der Print-Modus eine feste A4-Fläche von `210mm x 297mm`. Wenn ein Lebenslauf bewusst zwei Seiten braucht, sollen zwei getrennte A4-Seitencontainer erstellt werden. Der Agent soll zuerst Inhalte priorisieren und Layout moderat optimieren; wenn das nicht professionell reicht, ist ein sauber strukturierter zweiseitiger Lebenslauf besser als ein abgeschnittener oder gequetschter Einseiter.

## 12. Typischer Agentenablauf

1. Stellenbeschreibung lesen.
2. Firma und Zielrolle erkennen.
3. Private Daten aus `Private/Daten/` lesen.
4. Agentenregeln aus `Prompts/` lesen.
5. neutrales Bewerbungsprofil, Rollenstrategie und Recruiter-Strategie bestimmen.
6. Bewerbungsordner unter `Private/Bewerbungen/` erstellen.
7. Analyse speichern.
8. Lebenslauf nach deutschem CV-Standard erstellen: Berufserfahrung, Ausbildung/Studium/berufliche Bildung, Schulbildung, Weiterbildungen, Kenntnisse und relevante Praxis korrekt priorisieren.
9. Anschreiben erstellen.
10. E-Mail-Nachricht erstellen.
11. Druckfähigkeit prüfen.
12. Qualitätscheck speichern.
13. Statischen technischen Check mit `Tools/Pruefe-Bewerbung.ps1` ausführen.
14. Optional Browser-Layoutcheck mit `Tools/Layoutcheck-Bewerbung.ps1` ausführen.
15. Kurz berichten, wo die Dateien liegen und welche Checks bestanden wurden.

## 13. Anpassung

| Ziel | Datei |
| --- | --- |
| Kontaktdaten, Vorname/Nachname und Versanddateinamen ändern | `Private/Daten/01_PERSOENLICHE_DATEN.md` |
| Profil, Skills, Projekte ändern | `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` |
| Lebenslauf-Aufbau ändern | `Prompts/03_LEBENSLAUF_REGELN.md` |
| Anschreiben-Stil ändern | `Prompts/04_ANSCHREIBEN_REGELN.md` |
| E-Mail-Text ändern | `Prompts/05_EMAIL_NACHRICHT_REGELN.md` |
| Rollenlogik ändern | `Prompts/06_ROLLENLOGIK.md` |
| Wahrheitsregeln ändern | `Prompts/07_WAHRHEIT_UND_GRENZEN.md` |
| HTML/CSS ändern | `Prompts/08_HTML_CSS_DESIGNREGELN.md` |
| Qualitätscheck ändern | `Prompts/09_QUALITAETSCHECK.md` |
| Ordnerstruktur ändern | `Prompts/10_DATEI_UND_ORDNER_REGELN.md` |
| Technische Abschlussprüfung ändern | `Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md`, `Tools/Pruefe-Bewerbung.ps1`, `Tools/Layoutcheck-Bewerbung.ps1` |
| Windows-Skript ändern | `Tools/Neue-Bewerbung.ps1` |
| Linux-Skript ändern | `Tools/neue-bewerbung.sh` |

## 14. Projektstruktur

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

## 15. GitHub-Sicherheit

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

## 16. Entwicklerhinweise

- `.gitattributes` erzwingt LF-Zeilenenden für `.sh`.
- `.gitignore` schützt private Daten und generierte Dokumente.
- Öffentliche Beispiel-Dateien liegen in `Private.example/`.
- Die Hilfsskripte sollen dieselbe Ordnerstruktur erzeugen.
- Finale Bewerbungsdateien dürfen keine sichtbaren Platzhalter enthalten.
