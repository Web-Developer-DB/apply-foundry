<!-- cspell:words Layoutcheck MitLayoutcheck NurVorbereiten MinPdfBytes NichtUeberschreiben firefox Pruefe Qualitaetscheck Strg Headless Sandbox Sandboxfehler Browserfreigabe -->

# bewerbungs-agent

`bewerbungs-agent` ist ein lokaler, modularer Bewerbungsassistent für deutsche Bewerbungsunterlagen. Aus einer konkreten Stellenbeschreibung und den privaten Profildaten erstellt der Agent eine passgenaue Bewerbung:

- Lebenslauf als für den Druck vorbereitete HTML-Datei
- Anschreiben als für den Druck vorbereitete HTML-Datei
- kurze E-Mail-Nachricht
- Stellenanalyse
- Qualitätscheck
- optional PDFs aus Lebenslauf und Anschreiben

Das Projekt ist bewusst so aufgebaut, dass öffentliche Agentenlogik auf GitHub liegen kann, während echte persönliche Daten und generierte Bewerbungen lokal unter `Private/` bleiben.

## Inhalt

- [Teil 1: Anleitung für Anwender](#teil-1-anleitung-für-anwender)
- [Teil 2: Dokumentation für Entwickler](#teil-2-dokumentation-für-entwickler)

# Teil 1: Anleitung für Anwender

Dieser Teil erklärt, wie du mit dem Projekt Bewerbungsunterlagen erzeugst, prüfst und als PDF exportierst.

## Was du bekommst

Pro Bewerbung entsteht ein eigener privater Ordner:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/
```

Darin liegen am Ende typischerweise:

```text
Stellenbeschreibung.md
Analyse.md
Lebenslauf - NACHNAME.VORNAME.html
Lebenslauf - NACHNAME.VORNAME.pdf
Anschreiben - NACHNAME.VORNAME.html
Anschreiben - NACHNAME.VORNAME.pdf
Email-Nachricht--FIRMA.md
Qualitaetscheck.md
Druck-Hinweis.md
Offene_Fragen.md
```

PDF-Dateien entstehen nur, wenn der automatische PDF-Export ausgeführt wurde und Chrome oder Edge verfügbar ist.

## Voraussetzungen

Für die normale Nutzung brauchst du:

- dieses Repository lokal auf deinem Rechner
- einen KI-Agenten, der lokale Projektdateien lesen und schreiben kann, zum Beispiel Codex in VS Code
- private Profildaten unter `Private/Daten/`
- eine konkrete Stellenbeschreibung

Für die technischen Hilfsskripte unter Windows:

- PowerShell
- optional Chrome oder Edge für automatischen PDF-Export
- optional Chrome, Edge oder Firefox für die visuelle Prüfung im Browser

Unter Linux gibt es aktuell ein Bash-Skript für die Ordnererstellung. Die technischen Prüf- und Exporttools sind derzeit PowerShell-Skripte.

## Private Daten einrichten

Echte persönliche Daten gehören ausschließlich in:

```text
Private/Daten/
```

Benötigte Dateien:

```text
Private/Daten/01_PERSOENLICHE_DATEN.md
Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md
```

Optional, aber empfohlen:

```text
Private/Daten/README.md
```

Wenn `Private/Daten/` noch fehlt:

1. Erstelle den Ordner `Private/Daten/`.
2. Nutze die Dateien aus `Private.example/Daten/` als Strukturvorlage.
3. Entferne Beispielplatzhalter.
4. Trage persönliche Stammdaten nur in `01_PERSOENLICHE_DATEN.md` ein.
5. Trage fachliche Lebenslaufdaten nur in `02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` ein.
6. Nutze `Private/Daten/README.md` als lokale Pflegeanleitung, wenn du die Daten später erweiterst.

Wichtig: `Private/` ist in `.gitignore` eingetragen und darf nicht veröffentlicht werden.

### Zuständigkeit der privaten Datenfiles

`01_PERSOENLICHE_DATEN.md` enthält nur:

- Name, Vorname, Nachname und Dateiname-Name
- Adresse, Telefon, E-Mail
- GitHub, Portfolio und andere öffentliche Profile
- Verfügbarkeit und optionale persönliche Angaben

`02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` enthält:

- Zielrollen und Positionierung
- Berufserfahrung und übertragbare Erfahrung
- Ausbildung, Umschulung, Weiterbildung und Schulbildung
- Kenntnisse, Sprachen, Projekte und private Praxis
- Grenzen und Hinweise, was nicht behauptet werden darf

Eine Information soll nur an einer Stelle gepflegt werden. Kontakt- und Angaben für Dateinamen kommen aus Datei `01`; fachliche CV-Daten kommen aus Datei `02`.

## Bewerbung durch den Agenten erstellen lassen

Gib dem Agenten diesen Auftrag:

```text
Nutze Prompts/00_AGENTEN_START_HIER.md und erstelle eine Bewerbung für diese Stellenbeschreibung:

<Stellenbeschreibung einfügen>
```

Der Agent liest dann:

1. `Private/Daten/01_PERSOENLICHE_DATEN.md`
2. `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md`
3. die Regeln aus `Prompts/`
4. passende Designreferenzen aus `Vorlagen/`

Danach erstellt er einen privaten Bewerbungsordner und speichert dort die finalen Dateien.

## Was der Agent fachlich macht

Der Agent erstellt keinen universellen Lebenslauf. Er erstellt eine auf die konkrete Bewerbung zugeschnittene Version.

Dabei entscheidet die Stellenbeschreibung, welche Profilteile sichtbar werden:

- Zielrolle und Firma erkennen
- Anforderungen, Muss-Kriterien und Kann-Kriterien analysieren
- passende Kompetenzen aus den privaten Daten auswählen
- irrelevante Themen kürzen oder weglassen
- Quereinstieg, Lücken und private Praxis ehrlich einordnen
- Lebenslauf, Anschreiben und E-Mail passend zur Rolle formulieren
- keine Kenntnisse, Arbeitgeber, Zeiträume oder Zertifikate erfinden

Der Lebenslauf soll wie ein deutscher tabellarischer CV wirken, nicht wie eine Portfolio-Seite oder reine Skill-Sammlung.

## Optional: Bewerbungsordner manuell vorbereiten

Normalerweise erstellt der Agent den Ordner selbst. Du kannst die Struktur aber auch manuell vorbereiten.

Windows / PowerShell:

```powershell
.\Tools\Neue-Bewerbung.ps1 -Firma "Muster GmbH" -Rolle "Junior Webentwickler"
```

Linux / Bash:

```bash
bash Tools/neue-bewerbung.sh --firma "Muster GmbH" --rolle "Junior Webentwickler"
```

Die Skripte erzeugen:

```text
Private/Bewerbungen/Muster-GmbH/YYYY-MM-DD--Junior-Webentwickler/
Private/Bewerbungen/Muster-GmbH/_Arbeitsdateien/YYYY-MM-DD--Junior-Webentwickler/
```

Entwürfe und Arbeitsnotizen liegen immer unter `_Arbeitsdateien`. Der finale Bewerbungsordner bleibt für Versanddateien sauber.

## Bewerbung technisch prüfen

Nach jeder Bewerbung sollte der statische Prüfer laufen:

```powershell
.\Tools\Pruefe-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Der Prüfer kontrolliert:

- Pflichtdateien vorhanden
- finale Dateinamen korrekt
- Lebenslauf und Anschreiben nutzen denselben Bewerbernamen
- keine sichtbaren Platzhalter oder Entwurfsmarker
- HTML-Dateien haben feste A4-Grundstruktur
- CSS ist eingebettet
- keine externen Skripte, Fonts oder CDNs
- `overflow: hidden` wird nur auf der äußeren A4-Seite verwendet
- E-Mail-Nachricht ist kurz und ohne Platzhalter

Wenn der Prüfer rot ist, sollte die Bewerbung noch nicht versendet werden.

## Optional: Visuelle Prüfung erzeugen

Der Layout-Check öffnet die finalen HTML-Dateien per Headless-Browser und erzeugt Screenshots im privaten Arbeitsordner:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Unter Windows 11 mit VS Code, PowerShell und installiertem Chrome ist dieser direkte Weg empfohlen:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -Browser chrome
```

Die Screenshots liegen unter:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Layoutcheck/
```

Der Layout-Check gilt nur als erfolgreich, wenn die erwarteten Screenshot-Dateien wirklich erzeugt wurden und eine sinnvolle Größe haben.

Bei Agenten mit Sandbox kann der Browserstart dort fehlschlagen, obwohl das HTML korrekt ist. Dann denselben Chrome-Befehl außerhalb der Sandbox oder mit lokaler Browserfreigabe erneut ausführen und den Sandboxfehler dokumentieren. Nicht unnötig auf Firefox wechseln, wenn Chrome lokal verfügbar ist.

Der erzeugte Screenshot sollte danach visuell geprüft werden:

- Einseiten-Dokumente zeigen eine vollständige A4-Seite.
- Keine Inhalte sind unten abgeschnitten.
- Es gibt keine zerstückelte zweite Seite und keine großen ungewollten Leerflächen.
- Schulbildung, berufliche Bildung und Weiterbildung bleiben sichtbar.
- Schriftgröße, Zeilenabstand und Spalten wirken professionell lesbar.

Bei bewusst zweiseitigen Lebensläufen zusätzlich einen höheren Screenshot erzeugen oder die PDF-Ausgabe mit allen Seiten prüfen:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -Browser chrome -Height 2300
```

## PDFs automatisch exportieren

Wenn der statische Check grün ist und Chrome oder Edge verfügbar ist:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Mit Layout-Check vor dem Export:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -MitLayoutcheck
```

Unter Windows 11 mit Chrome kann der Export gezielt mit Chrome gestartet werden:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -Browser chrome
```

Das Exporttool:

- führt zuerst den statischen Prüfer aus
- bricht ab, wenn die Bewerbung technisch nicht sauber ist
- nutzt Chrome oder Edge Headless
- erzeugt PDFs im finalen Bewerbungsordner
- prüft Existenz, Dateigröße und PDF-Header

Die PDFs heißen genauso wie die HTML-Dateien:

```text
Lebenslauf - NACHNAME.VORNAME.html
Lebenslauf - NACHNAME.VORNAME.pdf
Anschreiben - NACHNAME.VORNAME.html
Anschreiben - NACHNAME.VORNAME.pdf
```

## Drucken und manueller PDF-Export

Die HTML-Dateien sind für A4 vorbereitet.

Wenn in Firefox Dateiname, URL, Datum oder Seitenzahl erscheinen, kommt das aus dem Druckdialog, nicht aus der HTML-Datei.

Empfohlene Firefox-Einstellungen:

1. HTML-Datei öffnen.
2. Den Druckdialog öffnen, zum Beispiel mit `Strg + P`.
3. `Weitere Einstellungen` öffnen.
4. `Kopf- und Fußzeilen drucken` deaktivieren.
5. Skalierung auf `100%` stellen.
6. Ränder auf `Keine` stellen.

Bei einseitigen Dokumenten soll eine feste A4-Fläche von `210mm x 297mm` verwendet werden. Wenn ein Lebenslauf fachlich nicht sauber auf eine Seite passt, ist ein bewusst zweiseitiger Lebenslauf besser als ein gequetschtes oder abgeschnittenes einseitiges Dokument.

## Offene Fragen in Bewerbungen

Wenn wichtige Informationen fehlen, legt der Agent `Offene_Fragen.md` an oder ergänzt sie.

Typische offene Punkte:

- Schulabschluss noch nicht bestätigt
- Ansprechpartner fehlt
- Eintrittstermin oder Kündigungsfrist unklar
- eine in der Anzeige gewünschte Technologie ist nur als Lernfeld, nicht als Erfahrung belegt

Offene Fragen blockieren die Bewerbung nur dann, wenn sie fachlich kritisch sind. Sonst werden sie dokumentiert und die Bewerbung neutral formuliert.

## Was darf versendet werden?

Für den Versand geeignet sind:

- `Lebenslauf - NACHNAME.VORNAME.html`
- `Lebenslauf - NACHNAME.VORNAME.pdf`
- `Anschreiben - NACHNAME.VORNAME.html`
- `Anschreiben - NACHNAME.VORNAME.pdf`
- `Email-Nachricht--FIRMA.md`

Nicht versenden:

- Dateien aus `_Arbeitsdateien`
- Entwürfe
- Screenshots aus dem Layout-Check
- interne Notizen
- `Analyse.md`, falls sie nur für dich gedacht ist
- `Qualitaetscheck.md`, falls er nicht ausdrücklich gewünscht ist

## Datenschutz

Privat und nicht für GitHub:

```text
Private/
Private/Daten/
Private/Bewerbungen/
Private/Bewertungen/
Private/LebenslaufUniversal/
Private/Archiv/
```

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

Vor einem Commit:

```powershell
git status --short
```

In dieser Ausgabe dürfen keine echten Dateien aus `Private/` erscheinen.

## Häufige Probleme

Wenn der statische Check fehlschlägt:

- Fehlermeldung lesen
- HTML oder Markdown korrigieren
- `Pruefe-Bewerbung.ps1` erneut ausführen

Wenn der Layout-Check fehlschlägt:

- prüfen, ob Chrome, Edge oder Firefox installiert ist
- prüfen, ob die Ausgabedateien unter `_Arbeitsdateien` erzeugt wurden
- den statischen Check trotzdem separat betrachten
- unter Windows 11 zuerst `-Browser chrome` nutzen
- bei Sandboxfehler denselben Chrome-Lauf außerhalb der Sandbox oder mit lokaler Browserfreigabe wiederholen

Wenn der PDF-Export fehlschlägt:

- prüfen, ob Chrome oder Edge installiert ist
- statischen Check erneut ausführen
- manuell über Firefox drucken, falls kein Headless-Export möglich ist

Wenn Text im PDF abgeschnitten wirkt:

- HTML öffnen und Layout prüfen
- Lebenslauf kürzen oder bewusst auf zwei A4-Seiten umbauen
- niemals Inhalt durch `overflow` verstecken

# Teil 2: Dokumentation für Entwickler

Dieser Teil beschreibt Projektstruktur, Datenfluss, Tool-Verantwortlichkeiten und Erweiterungspunkte.

## Projektprinzipien

Das Projekt trennt strikt zwischen öffentlicher Logik und privaten Daten.

Öffentlich:

- Prompts und Regeln
- Designreferenzen
- Hilfsskripte
- Beispielstrukturen
- README

Privat:

- echte Bewerberdaten
- generierte Bewerbungen
- Stellenbeschreibungen
- Arbeitsnotizen
- Screenshots
- PDFs

Die öffentlichen Dateien dürfen keine echten Kontaktdaten, privaten Lebenslaufdaten oder realen Bewerbungsunterlagen enthalten.

## Öffentliche Projektstruktur

```text
bewerbungs-agent/
├─ README.md
├─ .gitignore
├─ .gitattributes
├─ Prompts/
│  ├─ 00_AGENTEN_START_HIER.md
│  ├─ 03_LEBENSLAUF_REGELN.md
│  ├─ 04_ANSCHREIBEN_REGELN.md
│  ├─ 05_EMAIL_NACHRICHT_REGELN.md
│  ├─ 06_ROLLENLOGIK.md
│  ├─ 07_WAHRHEIT_UND_GRENZEN.md
│  ├─ 08_HTML_CSS_DESIGNREGELN.md
│  ├─ 09_QUALITAETSCHECK.md
│  ├─ 10_DATEI_UND_ORDNER_REGELN.md
│  └─ 11_TECHNISCHER_CHECK_WORKFLOW.md
├─ Tools/
│  ├─ Neue-Bewerbung.ps1
│  ├─ neue-bewerbung.sh
│  ├─ Pruefe-Bewerbung.ps1
│  ├─ Layoutcheck-Bewerbung.ps1
│  └─ Exportiere-PDF.ps1
├─ Vorlagen/
│  ├─ Designreferenz-Lebenslauf.html
│  ├─ Designreferenz-Anschreiben.html
│  └─ README.md
└─ Private.example/
```

## Private lokale Struktur

```text
Private/
├─ Daten/
│  ├─ README.md
│  ├─ 01_PERSOENLICHE_DATEN.md
│  └─ 02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md
├─ Bewerbungen/
│  └─ FIRMA/
│     ├─ YYYY-MM-DD--ROLLENNAME/
│     └─ _Arbeitsdateien/
│        └─ YYYY-MM-DD--ROLLENNAME/
├─ Bewertungen/
├─ LebenslaufUniversal/
└─ Archiv/
```

`Private/` ist ignoriert und darf nicht in Git aufgenommen werden.

## Prompt-System

Der zentrale Einstieg ist:

```text
Prompts/00_AGENTEN_START_HIER.md
```

Diese Datei legt Rolle, Arbeitsablauf, relevante Dateien, finale Ausgabe und technische Abschlusschecks fest.

Die Spezialregeln sind getrennt:

| Datei | Verantwortung |
| --- | --- |
| `03_LEBENSLAUF_REGELN.md` | Aufbau, Priorisierung, deutscher CV-Standard, A4-Seitenstrategie |
| `04_ANSCHREIBEN_REGELN.md` | Struktur, Ton und Grenzen des Anschreibens |
| `05_EMAIL_NACHRICHT_REGELN.md` | kurze Versandnachricht |
| `06_ROLLENLOGIK.md` | Ableitung von Zielrolle, Recruiter-Strategie und Profilgewichtung |
| `07_WAHRHEIT_UND_GRENZEN.md` | keine erfundenen Angaben, ehrliche Einordnung von Grundlagen und Praxis |
| `08_HTML_CSS_DESIGNREGELN.md` | feste A4-Geometrie, Firefox-Druck, HTML/CSS-Regeln |
| `09_QUALITAETSCHECK.md` | inhaltliche und technische Checkliste |
| `10_DATEI_UND_ORDNER_REGELN.md` | private Ordner, Dateinamen, Slugs, Arbeitsdateien |
| `11_TECHNISCHER_CHECK_WORKFLOW.md` | statischer Prüfer, Layout-Check, PDF-Export und robuste Shell-Regeln |

Änderungen sollten in der fachlich passenden Datei erfolgen, nicht alles in `00_AGENTEN_START_HIER.md`.

## Datenfluss einer Bewerbung

1. Stellenbeschreibung kommt vom Nutzer.
2. Agent liest private Daten aus `Private/Daten/`.
3. Agent trennt dabei Datei `01` als Quelle für Identität/Kontakt und Datei `02` als Quelle für fachliche CV-Daten.
4. Agent liest Prompt-Regeln aus `Prompts/`.
5. Agent erkennt Firma, Rolle, Anforderungen, Muss-Kriterien, Kann-Kriterien und Risiken.
6. Agent legt Rollenstrategie und Lebenslaufstrategie fest.
7. Ordner wird unter `Private/Bewerbungen/` erstellt.
8. Originale Stellenbeschreibung wird als `Stellenbeschreibung.md` gesichert.
9. Analyse wird als `Analyse.md` gespeichert.
10. Lebenslauf und Anschreiben werden als HTML erstellt.
11. E-Mail-Nachricht wird als Markdown erstellt.
12. Offene Fragen werden dokumentiert, falls nötig.
13. Qualitätscheck wird gespeichert.
14. Statischer technischer Check wird ausgeführt.
15. Optional Layout-Check.
16. Optional PDF-Export.

## Finale Dateinamen

Lebenslauf und Anschreiben werden nach Bewerbername benannt, nicht nach Firma:

```text
Lebenslauf - NACHNAME.VORNAME.html
Anschreiben - NACHNAME.VORNAME.html
Lebenslauf - NACHNAME.VORNAME.pdf
Anschreiben - NACHNAME.VORNAME.pdf
```

`NACHNAME.VORNAME` kommt aus:

```text
Private/Daten/01_PERSOENLICHE_DATEN.md
```

Wenn Vorname oder Nachname fehlen, darf keine finale Datei mit Platzhalter erzeugt werden.

## Ordner- und Slug-Regeln

Firmen- und Rollenordner werden technisch bereinigt:

- Leerzeichen werden Bindestriche
- Umlaute werden umgewandelt
- Sonderzeichen werden entfernt oder ersetzt
- mehrere Trennzeichen werden geglättet

Beispiel:

```text
Müller & Partner GmbH
-> Mueller-und-Partner-GmbH
```

Die Regeln stehen in `Prompts/10_DATEI_UND_ORDNER_REGELN.md` und sind in den Ordnerhelfern gespiegelt.

## Tools im Überblick

### `Tools/Neue-Bewerbung.ps1`

Erstellt unter Windows die Ordnerstruktur für eine neue Bewerbung.

Wichtige Parameter:

- `-Firma`
- `-Rolle`
- `-Datum`
- `-StellenbeschreibungPath`
- `-BewerbungenRoot`

Das Skript erstellt finale Ordner und Arbeitsordner. Entwürfe werden nur unter `_Arbeitsdateien` abgelegt.

### `Tools/neue-bewerbung.sh`

Bash-Variante des Ordnerhelfers.

Wichtige Parameter:

- `--firma`
- `--rolle`
- `--datum`
- `--stellenbeschreibung-path`
- `--bewerbungen-root`

Die Struktur soll zur PowerShell-Variante kompatibel bleiben.

### `Tools/Pruefe-Bewerbung.ps1`

Statischer Mindestcheck für finale Bewerbungsordner.

Beispiel:

```powershell
.\Tools\Pruefe-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLE"
```

Exitcodes:

- `0`: Prüfung bestanden
- `1`: Fehler gefunden

Das Skript ist bewusst unabhängig von `rg` und Browsern, damit der wichtigste Abschlusscheck stabil bleibt.

### `Tools/Layoutcheck-Bewerbung.ps1`

Optionale Browser-Prüfung mit Screenshots.

Beispiel:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLE"
```

Nützliche Parameter:

- `-Browser auto`
- `-Browser chrome`
- `-Browser edge`
- `-Browser firefox`
- `-NurVorbereiten`
- `-Pdf`
- `-OutputRoot`

Screenshots und Browser-Profile müssen unter `_Arbeitsdateien` landen, nicht im finalen Bewerbungsordner.

### `Tools/Exportiere-PDF.ps1`

Automatischer PDF-Export nach erfolgreichem statischem Check.

Beispiel:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLE"
```

Nützliche Parameter:

- `-Browser auto`
- `-Browser chrome`
- `-Browser edge`
- `-MitLayoutcheck`
- `-NichtUeberschreiben`
- `-MinPdfBytes`

Das Skript nutzt Chrome oder Edge Headless, erzeugt PDFs im finalen Bewerbungsordner und prüft Existenz, Größe und PDF-Header.

## HTML- und CSS-Standard

Finale HTML-Dateien müssen eigenständig funktionieren:

- CSS direkt im HTML
- keine externen Fonts
- keine Skripte
- keine CDNs
- feste A4-Seitencontainer
- `@page { size: A4; margin: 0; }`
- `.page` mit `width: 210mm` und `height: 297mm`
- `overflow: hidden` nur auf der äußeren `.page`

Ein Einseiten-Dokument darf nicht nur `min-height: 297mm` verwenden. Wenn Inhalt nicht passt, muss fachlich gekürzt oder auf zwei explizite A4-Seiten umgestellt werden.

## Qualitätsstrategie

Es gibt zwei Arten von Qualität:

Fachliche Qualität:

- Stellenpassung
- keine erfundenen Angaben
- glaubwürdiger Quereinstieg
- Recruiter-Lesbarkeit
- ATS-freundliche Begriffe
- angemessene Gewichtung der privaten Profildaten

Technische Qualität:

- Pflichtdateien vorhanden
- Dateinamen korrekt
- keine sichtbaren Platzhalter
- A4-Geometrie korrekt
- keine externen Abhängigkeiten
- PDF-Export nur nach erfolgreicher Prüfung

Fachliche Regeln stehen vor allem in `Prompts/03` bis `Prompts/09`. Technische Regeln stehen vor allem in `Prompts/08`, `Prompts/10` und `Prompts/11`.

## Browser- und PDF-Details

Der automatische PDF-Export nutzt Chrome oder Edge Headless. Firefox bleibt für manuelle Druckvorschau und manuelle PDF-Erzeugung geeignet, ist aber für CLI-PDF-Export weniger zuverlässig.

Wichtig:

- Ein Browser-Prozess gilt nur als Erfolg, wenn die erwartete Datei existiert.
- Eine Screenshot- oder PDF-Datei muss eine sinnvolle Größe haben.
- PDFs werden zusätzlich auf `%PDF-`-Header geprüft.
- Stille Browser-Prozesse ohne Ausgabedatei sind Fehler.

## Umgang mit `rg` und PowerShell

Für Dateisuche bevorzugt das Projekt `rg`.

Unter PowerShell keine Pfad-Wildcards wie diese verwenden:

```powershell
rg "MUSTER" "ORDNER/*.html"
```

Stattdessen:

```powershell
rg -g "*.html" "MUSTER" "ORDNER"
```

Die PowerShell-Prüftools vermeiden diese Abhängigkeit für kritische Checks.

## Git- und Datenschutzregeln

Vor Commits:

```powershell
git status --short
```

Erwartet sind nur öffentliche Dateien wie:

```text
Prompts/...
Tools/...
Vorlagen/...
README.md
Private.example/...
```

Nicht im Commit auftauchen dürfen:

```text
Private/...
Bewerbungen/...
Bewertungen/...
LebenslaufUniversal/...
Archiv/...
```

Wenn `git status --short --ignored` `!! Private/` zeigt, ist das normal.

## Erweiterungspunkte

| Ziel | Datei |
| --- | --- |
| Hauptablauf ändern | `Prompts/00_AGENTEN_START_HIER.md` |
| Lebenslaufregeln ändern | `Prompts/03_LEBENSLAUF_REGELN.md` |
| Regeln für Anschreiben ändern | `Prompts/04_ANSCHREIBEN_REGELN.md` |
| E-Mail-Regeln ändern | `Prompts/05_EMAIL_NACHRICHT_REGELN.md` |
| Rollenlogik ändern | `Prompts/06_ROLLENLOGIK.md` |
| Wahrheitsregeln ändern | `Prompts/07_WAHRHEIT_UND_GRENZEN.md` |
| HTML/CSS-Regeln ändern | `Prompts/08_HTML_CSS_DESIGNREGELN.md` |
| Qualitätscheck ändern | `Prompts/09_QUALITAETSCHECK.md` |
| Datei- und Ordnerregeln ändern | `Prompts/10_DATEI_UND_ORDNER_REGELN.md` |
| technische Abschlusslogik ändern | `Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md` |
| Ordnererstellung unter Windows ändern | `Tools/Neue-Bewerbung.ps1` |
| Ordnererstellung unter Linux ändern | `Tools/neue-bewerbung.sh` |
| statischen Check ändern | `Tools/Pruefe-Bewerbung.ps1` |
| Layout-Check ändern | `Tools/Layoutcheck-Bewerbung.ps1` |
| PDF-Export ändern | `Tools/Exportiere-PDF.ps1` |
| Designreferenzen ändern | `Vorlagen/Designreferenz-Lebenslauf.html`, `Vorlagen/Designreferenz-Anschreiben.html` |

## Empfohlener Entwickler-Workflow

1. Änderungen an Prompt, Tool oder Vorlage machen.
2. Mit einer privaten Testbewerbung prüfen.
3. Statischen Check ausführen.
4. Optional Layout-Check ausführen.
5. Optional PDF-Export ausführen.
6. `git status --short` prüfen.
7. Sicherstellen, dass keine privaten Dateien im Commit landen.

PowerShell-Syntaxcheck für Tools:

```powershell
$files = @(
  "Tools/Pruefe-Bewerbung.ps1",
  "Tools/Layoutcheck-Bewerbung.ps1",
  "Tools/Exportiere-PDF.ps1"
)

foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $file).Path,
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null

  if ($errors.Count -gt 0) {
    $errors
    exit 1
  }
}
```

## Bekannte Grenzen

- Die technischen Prüf- und Exporttools sind aktuell PowerShell-basiert.
- Der automatische PDF-Export unterstützt Chrome und Edge, nicht Firefox.
- Eine echte manuelle Sichtprüfung der finalen PDFs bleibt sinnvoll, besonders bei neuen Designs oder zweiseitigen Lebensläufen.
- Die Qualität der Bewerbung hängt weiterhin von gepflegten privaten Profildaten ab.
