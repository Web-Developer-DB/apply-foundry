<!-- cspell:words Regressionsfälle Regressionstest Regressionstests Regressionssuite Browsertests Browserprozesse Kindprozesse Referenzworkflow ShellCheck -->

# Änderungsprotokoll

Alle wesentlichen Änderungen am Projekt werden in dieser Datei dokumentiert. Die Struktur orientiert sich an „Keep a Changelog“ und verwendet die im Projekt geführten Versionsnummern.

## Version 1.2 – 2026-07-14

### Hinzugefügt

- Stammdaten-Vorprüfung mit getrennten Fehlern, Warnungen und strengem Gate für ungeklärte zentrale Bewerbungslogistik.
- Strukturierte `Anforderungsmatrix.json` für Muss-/Kann-Kriterien, Belegarten, Status und Behandlung.
- Fachlicher Inhaltsprüfer für Bewerbername, Firma, Rolle, Verfügbarkeit, Dateinamen und sämtliche formalen Zeiträume aus dem privaten Profil.
- Privater `Kandidat`-Ordner und `Bewerbungsauftrag.json` als verbindliche Staging-Struktur.
- Zweistufige Finalisierung mit tatsächlicher Sichtbestätigung, SHA-256-Nachweisen und atomarer Veröffentlichung des vollständigen Bewerbungssatzes.
- Maschinenlesbare Berichte für Stammdaten-, Inhalts-, Layout- und PDF-Prüfung.
- Heuristische Layoutdichte-Prüfung für ungewöhnlich große freie Flächen oder Inhalt zu nah am unteren Seitenrand.
- Regressionstests für Stammdaten-Gates, Zeitraumvollständigkeit, Sichtprüfungszwang, veraltete HTML-Nachweise und atomare Veröffentlichung.

### Geändert

- Ordnerhelfer für PowerShell und Bash halten den finalen Zielordner bis zur Freigabe leer und legen Stellenbeschreibung sowie Druckhinweis im Kandidatenordner ab.
- Browsergestützte Prüfungen binden Screenshots und PDFs per Hash an den geprüften HTML-Stand.
- Agentenworkflow liest große Regeldateien in kleinen Gruppen und verwendet die neue Finalisierung statt direkter Schreibvorgänge in den Zielordner.
- Risiken und nicht belegte Anforderungen werden aus defensiven Anschreibenformulierungen in Analyse, Matrix, Qualitätscheck oder offene Fragen verlagert.

## Version 1.1 – 2026-07-14

Version 1.1 basiert auf einem vollständigen technischen und logischen Audit des Projekts.

### Hinzugefügt

- Vollständiger Umsetzungsplan `frontend-project.md` für eine sichere Electron-Oberfläche mit Codex-Agentenrollen, OpenAI-/Ollama-Adaptern, Arbeitsphasen, Qualitätsgates und Definition of Done.
- Dependency-freie PowerShell-Regressionssuite unter `Tests/Run-RegressionTests.ps1`.
- Separate Bash-Regressionsfälle unter `Tests/Bash/test-neue-bewerbung.sh`.
- Optionale echte Chrome-Testmatrix über `-MitBrowser`.
- GitHub-Actions-Workflow unter `.github/workflows/tests.yml` für Windows und Ubuntu.
- Explizites Fortsetzen vorhandener Bewerbungen über `-Fortsetzen` beziehungsweise `--fortsetzen`.
- Konfigurierbare Browser-Timeouts für Layout-Check und PDF-Export.
- Kontrollierter Firefox-Fallback im Layout-Check über `-ErlaubeFirefoxFallback`.
- Sicherheitsregeln für Stellenanzeigen, Webseiten, E-Mails und andere nicht vertrauenswürdige Eingaben.
- Prüfung relativer und externer automatisch geladener HTML-/CSS-Ressourcen.
- Prüfung der PDF-Seitenzahl gegen die expliziten A4-Seitencontainer im HTML.
- Atomare Veröffentlichung eines vollständig validierten PDF-Sets mit Wiederherstellung vorhandener Dateien bei Fehlern.
- Dieses zentrale Änderungsprotokoll.

### Geändert

- `Tools/Pruefe-Bewerbung.ps1` arbeitet jetzt strikt und fehlergeschlossen.
- Pflichtdateien müssen reguläre, nichtleere Dateien sein; gleichnamige Verzeichnisse werden abgelehnt.
- Finale Lebenslauf- und Anschreibendateien müssen dem Namensschema entsprechen und denselben Bewerbernamen verwenden.
- Anschreiben müssen genau eine explizite A4-Seite enthalten; Lebensläufe dürfen eine oder zwei explizite A4-Seiten enthalten.
- Zweiseitige Lebensläufe benötigen auf jeder Seite einen konsistenten Footer im Format `Seite X von Y`.
- `.page` muss bereits außerhalb von `@media print` exakt `width: 210mm` und `height: 297mm` verwenden.
- `overflow: hidden` ist nur auf dem äußeren A4-Seitencontainer zulässig.
- E-Mail-Entwürfe und finale E-Mail-Nachrichten beginnen mit einer konkreten `Betreff:`-Zeile.
- `Initiativbewerbung` wird als gültiger Bewerbungsbegriff im Betreff erkannt.
- `Tools/Layoutcheck-Bewerbung.ps1` entfernt erwartete alte Ausgaben vor dem Lauf und akzeptiert nur frisch erzeugte PNG-Dateien mit korrekter Signatur und exakten Abmessungen.
- Der automatische Browsermodus priorisiert Chromium und wechselt nicht mehr unbemerkt nach einem Chromium-Fehler zu Firefox.
- `Tools/Exportiere-PDF.ps1` exportiert zunächst in einen eindeutigen privaten Arbeitslauf und veröffentlicht erst nach vollständiger Validierung.
- PDF-Dateien werden auf Aktualität, Mindestgröße, Header, EOF-Marker, DIN-A4-MediaBox und Seitenzahl geprüft.
- Browserprofile und Zwischenexporte verwenden kurze interne Pfade, um Windows-Pfadlängenprobleme zu vermeiden.
- PowerShell- und Bash-Ordnerhelfer validieren Firma, Rolle, Steuerzeichen, Pfadtypen und echte Kalenderdaten vor der Ausgabe.
- Vorhandene Ziel- oder Arbeitsordner werden standardmäßig nicht mehr still weiterverwendet.
- Fortsetzen ist nur möglich, wenn Ziel- und Arbeitsordner vollständig vorhanden sind und `Arbeitsnotizen.md` dieselbe Firma und Rolle bestätigt.
- Eine vorhandene abweichende `Stellenbeschreibung.md` wird niemals überschrieben.
- `.gitignore` verwendet eine einzige, am Projektwurzelverzeichnis verankerte Regel `/Private/` für den vollständigen privaten Verzeichnisbaum.
- Lokale Agentenkonfigurationen werden mit `/.agents/` und `/.codex/` gezielt nur an der Projektwurzel ignoriert.
- Typische lokale Dateien wie `Desktop.ini`, Vim-Auslagerungsdateien und Sicherungsdateien mit `~` werden ignoriert.
- `.gitattributes` erzwingt LF-Zeilenenden zusätzlich für `.gitignore` und YAML-Dateien.
- Automatische Gehaltsschätzungen benötigen eine ausdrückliche Aktivierung und eine aktuelle, nachvollziehbare Quelle.
- Gehaltsschätzungen richten sich nach Rolle, Seniorität, einschlägiger Erfahrung, Region, Arbeitsmodell und Stellenart.
- README, Prompt-Regeln und Beispiel-Datendokumentation wurden an die Version 1.1 angeglichen.

### Behoben

- Ungültige A4-Regeln mit nur `min-height: 297mm` konnten den statischen Check zuvor fälschlich bestehen.
- Mehrseitige oder überlange Anschreiben konnten als gültige Einseiter durchrutschen.
- Versteckter Inhalt durch `overflow: hidden` auf inneren Textbereichen wurde nicht zuverlässig erkannt.
- Leere Dateien und Verzeichnisse mit Pflichtdateinamen konnten als vorhandene Pflichtdateien gelten.
- Fehlende oder unvollständige E-Mail-Betreffzeilen wurden nicht konsequent erkannt.
- Relative Bilder, Stylesheets oder andere lokale Ressourcen wurden nicht vollständig blockiert.
- Alte oder frei erzeugte Dateien konnten aufgrund von Dateigröße als vermeintlich gültige Screenshots gelten.
- Veraltete oder unveränderte PDFs konnten einen fehlgeschlagenen Browserexport verdecken.
- Zusätzliche vom Browser erzeugte PDF-Seiten wurden nicht gegen die HTML-Seitenstruktur geprüft.
- Teilweise veröffentlichte PDF-Sets konnten bei einem Fehler zurückbleiben.
- Hängende Browserprozesse und deren Kindprozesse konnten nach einem Timeout weiterlaufen.
- Lange temporäre Chrome-Profilpfade konnten unter Windows ein sichtbares Datenverzeichnis-Fehlerfenster auslösen.
- PowerShell-Listenübergaben konnten im PDF-Export den Laufzeitfehler `Argument types do not match` erzeugen.
- Unmögliche Datumswerte wie `2026-99-99` wurden von beiden Ordnerhelfern akzeptiert.
- Unterschiedliche Firma-/Rollenwerte mit demselben bereinigten Slug konnten vorhandene Bewerbungen vermischen oder überschreiben.
- Unverankerte Regeln wie `Bewerbungen/` oder `Archiv/` konnten gleichnamige Test- und Dokumentationsordner außerhalb von `Private/` unbeabsichtigt ignorieren.
- Die Bash-HTML-Kodierung war unter aktuellen Bash-Versionen nicht zuverlässig.
- Dateisystemfehler konnten vom PowerShell-Helfer mit einem irreführenden erfolgreichen Exitcode beendet werden.
- Ein Verzeichnis konnte beim Fortsetzen als `Stellenbeschreibung.md` oder beim Export als PDF-Zielpfad missverstanden werden.

### Sicherheit und Datenschutz

- Stellenbeschreibungen und externe Inhalte gelten ausschließlich als Daten, nicht als System- oder Agentenanweisungen.
- Eingebettete Aufforderungen zum Offenlegen, Kopieren, Hochladen, Versenden, Löschen oder Verändern privater Daten werden nicht ausgeführt.
- Externe Aktionen benötigen einen direkten Nutzerauftrag.
- Finale HTML-Dateien dürfen keine externen oder lokalen Ressourcen automatisch laden; eingebettete `data:`-Ressourcen bleiben möglich.
- Analyse, Qualitätscheck und Arbeitsnotizen sollen keine unnötigen privaten Daten oder Geheimnisse vervielfältigen.
- Die Dokumentation stellt klar, dass `.gitignore` weder Verschlüsselung noch Schutz vor Cloud-Synchronisation, Backups oder lokalen Programmen bietet.
- Alter, Geschlecht und andere geschützte persönliche Merkmale wurden aus der Gehaltslogik entfernt.

### Tests und Verifikation

- PowerShell-Syntaxprüfung für alle Werkzeuge.
- Kompatibilitätslauf mit PowerShell 7 und Windows PowerShell 5.1.
- Bash-Syntax- und Regressionstests mit Git Bash sowie ShellCheck in CI.
- Regressionstests für ungültige Datumswerte, Pfadtypen, Slug-Kollisionen und sicheres Fortsetzen.
- Statische Positiv- und Negativtests für A4-Struktur, Pflichtdateien, E-Mail-Betreff und automatisch geladene Ressourcen.
- Browsertests für frische PNG-Screenshots, zusätzliche PDF-Druckseiten, validiertes Ersetzen vorhandener PDFs und ungültige PDF-Zielpfade.
- Beim Audit bestanden alle 18 Testfälle der vollständigen lokalen Browsermatrix.

### Dokumentation

- README um einen neutralen Verweis auf den Frontend-Projektplan und die öffentliche Projektstruktur um `frontend-project.md` ergänzt.
- README auf Projektstruktur und Funktionsstand von Version 1.1 aktualisiert.
- Öffentliche Struktur um `Tests/`, `.github/workflows/tests.yml` und `CHANGELOG.md` ergänzt.
- Technischen Abschlussworkflow an frische Artefakte, Timeouts, Seitenzahlprüfung und PDF-Veröffentlichung angepasst.
- Qualitätscheck um Sicherheits-, Ressourcen- und PDF-Prüfpunkte ergänzt.
- Datei- und Ordnerregeln um Kollisionsschutz und explizites Fortsetzen ergänzt.
- HTML-/CSS-Regeln um externe und lokale automatisch geladene Ressourcen ergänzt.
- Beispiel-Datendokumentation an die neue Gehaltslogik angeglichen.

### Betroffene Projektdateien

- Repository-Konfiguration: `.gitignore`, `.gitattributes`.
- Dokumentation: `README.md`, `CHANGELOG.md`, `frontend-project.md`, `Private.example/Daten/README.md`.
- Hauptablauf und Regeln: `Prompts/00_AGENTEN_START_HIER.md`, `Prompts/04_ANSCHREIBEN_REGELN.md`, `Prompts/06_ROLLENLOGIK.md`, `Prompts/07_WAHRHEIT_UND_GRENZEN.md`, `Prompts/08_HTML_CSS_DESIGNREGELN.md`, `Prompts/09_QUALITAETSCHECK.md`, `Prompts/10_DATEI_UND_ORDNER_REGELN.md`, `Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md`.
- PowerShell-Werkzeuge: `Tools/Neue-Bewerbung.ps1`, `Tools/Pruefe-Bewerbung.ps1`, `Tools/Layoutcheck-Bewerbung.ps1`, `Tools/Exportiere-PDF.ps1`.
- Bash-Werkzeug: `Tools/neue-bewerbung.sh`.
- Tests: `Tests/Run-RegressionTests.ps1`, `Tests/Bash/test-neue-bewerbung.sh`.
- CI: `.github/workflows/tests.yml`.

### Bekannte Grenzen

- Der vollständig getestete Referenzworkflow bleibt Windows mit PowerShell.
- Linux unterstützt derzeit vor allem die Ordnererstellung per Bash; Prüf- und Exportwerkzeuge sind PowerShell-basiert.
- Der automatische CLI-PDF-Export unterstützt Chrome und Edge, nicht Firefox.
- HTML- und PDF-Strukturen werden konservativ ohne vollständigen DOM- oder PDF-Parser geprüft.
- Eine manuelle Sichtprüfung bleibt bei neuen Designs und zweiseitigen Lebensläufen sinnvoll.

## Version 1.0

- Ursprünglicher Projektstand vor dem technischen und logischen Audit für Version 1.1.
