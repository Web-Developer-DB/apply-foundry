<!-- cspell:words Regressionsfälle Regressionstest Regressionstests Regressionssuite Browsertests Browserprozesse Kindprozesse Referenzworkflow ShellCheck -->

# Änderungsprotokoll

Alle wesentlichen Änderungen am Projekt werden in dieser Datei dokumentiert. Die Struktur orientiert sich an „Keep a Changelog“ und verwendet die im Projekt geführten Versionsnummern.

## Version 1.5 - 2026-08-04

### Hinzugefügt

- Zentrale `AGENTS.md` als kompakte Routing-, Sicherheits- und Moduserkennungsschicht für AGENTS-kompatible Coding-Agenten.
- Minimaler Gemini-Adapter `GEMINI.md`, der die zentrale `AGENTS.md` importiert, ohne fachliche Regeln zu duplizieren.
- Anbieterneutraler, privater Nutzungsbericht `Tokenverbrauch.json` mit den Messbereichen `lebenslauf`, `gesamte_bewerbung` und `technische_vorbereitung`.
- Neues Werkzeug `Tools/Aktualisiere-Tokenbericht.ps1`, das nur ausdrücklich als maschinenlesbar verfügbar gekennzeichnete Laufzeitwerte übernimmt und andernfalls `unavailable` mit Nullwerten schreibt.
- Regressionstests für Agenteneinstieg, Gemini-Import, Betriebsmodi, Sichtprüfungszwang, Token-Schätzverbot, Berichtsschema, Nichtverfügbarkeit, sensible Felder sowie Ausschluss aus Versand und Manifest.
- README-Prüfung für vorhandene lokale Markdown-Ziele und definierte interne Anker.

### Geändert

- Der Agentenstart lädt Promptmodule bedarfsgerecht statt vorsorglich das vollständige Prompt-System in den Kontext zu übernehmen.
- Der Bewerbungsworkflow zeigt den Tokenbericht nach dem Lebenslauf-Kandidaten und nach der technischen Vorbereitung, ohne den Arbeitsablauf oder die Finalisierung zu blockieren.
- `Finalisierungsbericht.json` verwendet Schema 3 und kann auf den separaten, nicht hashgebundenen Tokenbericht als Diagnose- und Kostenartefakt verweisen.
- README und Promptdokumentation beschreiben den automatischen Einstieg für kompatible Agenten, den manuellen Fallback, den Unterschied zu einem Betriebssystem-Autostart sowie die Grenzen exakter Tokenmessung.

### Sicherheit

- Tokenwerte werden weder geschätzt noch aus Textlängen oder Teilwerten berechnet.
- `Tokenverbrauch.json` bleibt im privaten Arbeitsordner, enthält keine Prompts oder Bewerbungsinhalte und gelangt nicht nach `Versand/`, `Intern/` oder `Manifest.json`.
- Eine lokale Veröffentlichung verlangt weiterhin eine neue eindeutige persönliche Sichtprüfungsbestätigung für den unveränderten vorbereiteten Stand.

## Version 1.4 - 2026-08-03

### Hinzugefügt

- Zwei verbindliche Dokumentmodi: `vollbewerbung` sowie `anschreiben_mit_universalem_lebenslauf`.
- SHA-256-gebundene Übernahme einer freigegebenen Universal-Lebenslauf-HTML in den Anschreiben-Modus.
- Neues Promptmodul `01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md` mit Auswahl-, Ablage- und Versandregeln.
- Regressionstests für unveränderte Universal-Snapshots, fehlende Zielrolle im universellen Lebenslauf und abweichende Eignungskennzahlen.

### Geändert

- PowerShell- und Bash-Ordnerhelfer erzeugen Schema-3-Aufträge mit eindeutigem Dokumentmodus.
- Im Anschreiben-Modus erzeugen die Ordnerhelfer keinen Lebenslaufentwurf, sondern kopieren die freigegebene Universalquelle hashgleich in den Kandidatenordner.
- Die Zielrolle wird bei Vollbewerbungen in allen drei Dokumenten geprüft; im Anschreiben-Modus nur in Anschreiben und E-Mail-Betreff.
- README, Agentenworkflow, Lebenslauf-, Anschreiben-, Qualitäts- und Dateiregeln beschreiben beide Betriebsarten ausdrücklich.

### Behoben

- Der Agentenprompt nennt jetzt die vollständige Parameterform für `Pruefe-Bewerbungsinhalt.ps1`; dadurch wird der nicht existierende Parameter `-Arbeitsordner` vermieden.
- Manuell abweichende Eignungswerte in `Analyse.md` oder `Qualitaetscheck.md` werden gegen die maschinelle Matrixberechnung geprüft und blockiert.
- Die exakte Zielrollenbezeichnung einschließlich Zusätzen wie `(m/w/d)` wird bereits bei der Auftragsanlage verlangt.
- Ein universeller Lebenslauf wird nicht mehr versehentlich stellenbezogen verändert, wenn der Nutzer ausdrücklich nur ein neues Anschreiben wünscht.

### Tests und Verifikation

- PowerShell-Parserprüfung für alle Werkzeuge.
- Vollständige dependency-freie Regressionstests für beide Dokumentmodi.
- Bash-Syntax- und Modustests für die plattformgleiche Ordneranlage.

## Version 1.3 – 2026-07-15

### Hinzugefügt

- Bewerbungsspezifischer Logistik-Snapshot in `Bewerbungsauftrag.json` mit Quellhashes, ausdrücklicher Bewerbungsentscheidung sowie Optionen für Schulbildung und Profil-Links.
- Gewichtete Anforderungsmatrix mit Kategorien, Prioritäten und maschinenlesbarer Eignungsklasse `stark`, `vertretbar_mit_risiken` oder `stretch`.
- Rollenbezogene Auswahl von GitHub-, Portfolio-, LinkedIn- und Xing-Links mit Prüfung gegen die Stammdaten und den finalen Lebenslauf.
- Optionaler Modus `recruiter_kompakt`, der Schulbildung bei erfahrenen Profilen auf eine sichtbare Abschlussangabe verdichtet, ohne berufliche oder akademische Chronologie zu kürzen.
- Dependency-freier ATS-Prüfer für Unicode-Textschicht, Pflichttexte, formale Zeiträume, HTML-zu-PDF-Textabdeckung und grundlegende Lesereihenfolge.
- Strukturierte Veröffentlichung mit `Versand/`, `Intern/` und `Manifest.json` samt Pfad-, Größen- und SHA-256-Nachweisen.
- Hashschutz für alle Kandidatendateien sowie Stammdaten, Profil, Bewerbungsauftrag und Anforderungsmatrix zwischen Vorbereitung und Veröffentlichung.
- Verpflichtende `-VisuelleFreigabeNotiz`, wenn der Layoutcheck automatische Dichte- oder Randwarnungen meldet.
- MIT-Lizenzdatei mit Copyright-Hinweis für Web-Developer-DB sowie sichtbarem Lizenzhinweis in der README.

### Geändert

- Der Layoutcheck erzeugt jetzt für jeden expliziten A4-Seitencontainer ein eigenes PNG mit `seite-X-von-Y` im Dateinamen. Zweiseitige Lebensläufe werden vollständig statt nur in der ersten Bildschirmhöhe erfasst.
- Die Dichteheuristik misst nur den nutzbaren Inhaltsbereich und ignoriert festen Footer sowie unteren Sicherheitsabstand.
- PowerShell- und Bash-Ordnerhelfer erzeugen Schema-2-Aufträge und Schema-2-Matrixentwürfe.
- Die bewerbungsspezifische Logistik hat Vorrang vor globalen Standardwerten; ältere Aufträge bleiben über den Stammdaten-Fallback kompatibel.
- Der Inhaltsprüfer validiert Entscheidung, Darstellungsoptionen, Kategorien, Gewichtungen und Profil-Link-Policy und weist verdichtete Schulzeiträume im Bericht aus.
- Die Finalisierung wiederholt die ATS-Prüfung vor der Veröffentlichung und veröffentlicht atomar eine versandfreundliche Auswahl ohne interne PDF-Dubletten.
- Agenten- und Qualitätsregeln verlangen dateiweises Schreiben und unmittelbare Validierung statt fehleranfälliger großer Sammeländerungen.
- README und Prompts stellen klar: Eine Bitte um Bewerbung im PDF-Format verlangt nicht automatisch eine einzige zusammengeführte PDF. Standard bleiben zwei getrennte Anlagen für Lebenslauf und Anschreiben.

### Behoben

- Bei zweiseitigen Lebensläufen konnte die zweite A4-Seite außerhalb des festen Screenshots liegen und dadurch ungeprüft bleiben.
- Scrollbar, Seitenkante oder Footer konnten Dichtewarnungen verfälschen.
- Änderungen an Markdown-Kandidaten, Profil, Stammdaten oder Matrix konnten nach der technischen Vorbereitung unbemerkt bleiben.
- Globale Logistikwerte mussten für einzelne Bewerbungen geändert werden und konnten dadurch andere Bewerbungen beeinflussen.
- Optisch gültige PDFs konnten ohne ausreichende maschinenlesbare Textschicht als versandfertig gelten.
- Versanddateien, HTML-Quellen und interne Prüfdokumente lagen ohne klare Trennung im selben Ordner.

### Tests und Verifikation

- 31 dependency-freie Regressionstests ohne Browser bestanden.
- Vollständige lokale Chrome-Matrix mit 37 Tests bestanden.
- Neue Regressionsfälle für Schema-2-Snapshot, Logistik-Override, Gewichtung, Link-Policy, kompakte Schulbildung, vollständige Kandidaten-/Quellhashes, Freigabenotiz, Manifest-Manipulation, Mehrseiten-Screenshots und ATS-Bericht.

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
