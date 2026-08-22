<!-- cspell:words Regressionsfälle Regressionstest Regressionstests Regressionssuite Browsertests Browserprozesse Kindprozesse Referenzworkflow ShellCheck -->

# Änderungsprotokoll

Alle wesentlichen Änderungen am Projekt werden in dieser Datei dokumentiert. Die Struktur orientiert sich an „Keep a Changelog“ und verwendet die im Projekt geführten Versionsnummern.

## Unveröffentlicht

### Hinzugefügt

- Plattformneutraler Abhängigkeits-Bootstrap für Linux x86_64 mit APT, DNF/YUM, Pacman und Zypper sowie Windows PowerShell 5.1/winget. PowerShell 7.6 wird auf nicht direkt paketierten Linux-Systemen über ein gepinntes, SHA-256-geprüftes offizielles Archiv benutzerlokal bereitgestellt; `setup-ubuntu.sh` bleibt als Kompatibilitätsalias erhalten.

- Gemeinsame Chromium-Druckvorprüfung für Layoutcheck und PDF-Export: jedes vollständige Original-HTML wird auf A4, PDF-Struktur und die exakte Übereinstimmung von expliziten `.page`-Containern und Druckseiten geprüft. `Layoutcheck-Bericht.json` verwendet dafür Schema 3.
- `Pruefstand.json` Schema 2 hält laufende, bestandene und fehlgeschlagene Finalisierungsstufen mit bereinigten Fehlerdaten fest. Die Statusausgabe zeigt den letzten technischen Versuch und erkennt hashabweichende Eingaben als veraltet.
- Der CLI-Dispatcher normalisiert einzelne Pfade und kommagetrennte Pfadlisten gegen das ursprüngliche Aufrufverzeichnis, bevor er ein Fachwerkzeug startet.

- Phase-6-Effizienz: hashgebundener privater `Pruefstand.json` für die Finalisierungsstufen, `--neu-pruefen`, Finalisierungsbericht Schema 7 und feste Reihenfolge Dialog, Stammdaten, statisch, Inhalt, DOM/Layout, PDF und ATS.
- `bewerbung.ps1 kontext` erzeugt einen privaten, quellenhashgebundenen `Kontextmanifest.json`-Entwurf. Der Rollout bleibt bis zu einer erfolgreichen realen Promptmatrix bewusst im Modus `vollkontext`.
- Schema-1-Testberichte enthalten Laufzeitaggregate, Kategorien und langsame Tests. `bewerbung.ps1 test-baseline` erzeugt aus drei erfolgreichen ungefilterten Berichten eine öffentliche Baseline; Laufzeitabweichungen sind zunächst nicht blockierende Warnungen.

- Phase-5-Architektur: wiederverwendbare Matrix- und Evidenzindex-Verträge, versionierte read-only Migration mit privaten Entwürfen, Hash-Recheck, Rollback und Schema-1-Migrationsbericht sowie `bewerbung.ps1 migrieren`. Matrix-Schemata 1 bis 4 und Evidenzindex-Schema 1 bleiben ohne automatische Umschreibung kompatibel.
- `Console App.md` als kompakte, ausdrücklich nicht operative Roadmap wiederhergestellt; aktuelle Prompts, Werkzeuge und `AGENTS.md` bleiben die maßgeblichen Quellen.

- Phase-4-Testsystem: vier synthetische Rollen-Fixtures für Softwareentwicklung, kaufmännische Sachbearbeitung, IT-Support-Quereinstieg und soziale Betreuung mit Umfang A bis D, Schema-5-Erwartungen und isoliertem Fixture-Runner.
- Explizite Testkategorien `schnell`, `vollstaendig` und `browser` sowie Prompt-Suiten `prompt-pr` und `prompt-vollstaendig`; jeder Lauf kann einen bereinigten Schema-1-Bericht mit Kategorie, Dauer, Ergebnis und Fehlerklasse schreiben.
- Maschinenlesbare Agenten-/Modellmatrix mit fest gepinnten Codex-, OpenCode-, Claude-Code- und Gemini-CLI-Versionen; Codex und OpenCode verwenden in der PR-Canary dasselbe OpenAI-Modell. Echte Prompt-Regressionsläufe isolieren Git-Repository, Benutzerprofile und Credentials und prüfen Dateimutationen deterministisch.
- Getrennte Windows-/Ubuntu-Browserjobs, Windows-Smoke bei Pull Requests, gestufter Ubuntu-Job sowie Schema-1-Stabilitätsnachweis und Validator für die drei erforderlichen Paritätsläufe.

- Phase-3-Bewerbungsqualität: Matrix-Schema 5 mit maschinenlesbarer Anschreibenstrategie, Arbeitgebernutzen- und Evidenz-IDs, strukturiertem Quellenregister, vollständiger Evidenzdisposition sowie konservativem Sprach-, Floskel- und Wiederholungswarnsystem. Der Inhaltsprüfbericht verwendet dafür Schema 6; Matrix-Schemata 1 bis 4 bleiben kompatibel.

- Phase-2-Zuverlässigkeitsverträge: gemeinsame atomare UTF-8-/JSON-Schreibfunktionen mit begrenzten Dateisperr-Wiederholungen, pfadgebundene Checkpoint-Aktualisierung und gemeinsame JSON-, Umfangs-, Slug- und Unicode-Textverträge.
- Hashgebundene Sichtfreigaben mit neuer `freigabe`-CLI, eindeutiger Freigabe-ID, Artefaktsatzbindung und aktuellen Nachweis-Hashes für individuelle und universelle Finalisierungen.
- ATS-Schema 2 mit Unicode-normalisiertem Token-Multiset sowie geordneten Bigramm-/Trigramm-Metriken, stabiler Tokenisierung technischer Begriffe und vollständiger Artefaktbindung.
- Regressionstests für Freigabe-Manipulationen, atomare Unterbrechungen, Dateisperren, parallele Zustandsupdates und Token-/N-Gramm-Abgleich.

- Matrix-Schema 4 mit hash- und zeilengebundener `stellenanzeigeAbdeckung`, verbindlichen Stellen-Fundstellen sowie einem privaten `Evidenzindex.json` für quellgebundene Profilbelege. Matrix-Schemata 1 bis 3 bleiben lesbar.
- Browserseitige DOM-Geometrieprüfung für jede isolierte A4-Seite. Scrollüberlauf und sichtbare Elemente außerhalb der festen Seite blockieren die technische Vorbereitung.
- Private Dialogtransaktion mit Mutex, geflushten temporären Dateien, Sicherungen und automatischer Wiederherstellung eines unterbrochenen Profil-/Auftragscommits.
- Matrix-Schema 3 mit verbindlicher `recruiterStrategie` für priorisierte Anforderungen, belegte Profilhighlights, wahre Transferbrücken, begründete Auslassungen und sichtbare Dokumentanker.
- Maschinenlesbare `recruiterCoverage` im Schema-5-Inhaltsprüfbericht einschließlich Zieldokument-, Seite-1-, Highlight-, Transfer- und Substanzprüfung.
- Optionales, ausschließlich privates `Private/Daten/Passfoto.png` für individuelle Lebensläufe sowie das idempotente Subcommand `bewerbung.ps1 passfoto`, das einen markierten HTML-Block ohne Ausgabe der Bilddaten befüllt oder entfernt.
- Gemeinsame PNG-Header-, Base64- und Bytegleichheitsprüfung für Passfoto-Einbettung, Inhaltsbericht, Finalisierungsnachweis, Manifest und dateibasierte Statusrekonstruktion.
- Gemeinsamer Dispatcher `Tools/bewerbung.ps1` einschließlich `universal-neu`, `universal-status` und `universal-finalisieren`; GNU-Langoptionen gelten auf Windows und Linux gleich.
- Eigenständiger, statusfähiger Universal-Lebenslauf-Prozess mit `universal-neu`, `universal-status` und `universal-finalisieren` vollständig unter `Private/Bewerbungen/_Universal-Lebenslauf/`.
- Privater, hashgebundener `Workflow-Checkpoint.json` für effiziente Fortsetzungen ohne Rohchat- oder Quellkopien. Der Ordnerhelfer und die Finalisierung aktualisieren die passenden Phasengrenzen automatisch.
- Dünner Linux-Launcher `Tools/bewerbung.sh`, Kompatibilitätswrapper `Tools/neue-bewerbung.sh` sowie ein ausschließlich opt-in verwendbares `Tools/setup-ubuntu.sh` für Ubuntu 24.04 x86_64.
- Gemeinsame PowerShell-Module für portable Schema-5-Auftragspfade, symlinksichere Pfadvalidierung, OS- und Browsererkennung, begrenzte native Prozesse mit Timeout sowie dependency-freie PNG-Auswertung.
- Read-only-Preflight `Tools/Pruefe-Umgebung.ps1` und eine feste browserfreie CI-Matrix auf `windows-2025` und `ubuntu-24.04`; Browser-Smokes laufen zunächst getrennt, manuell und zeitgesteuert.

### Geändert

- Repository- und Produktidentität auf **Apply Foundry** (`apply-foundry`) umgestellt: README, GitHub-Links, Console-App-Roadmap und die README-Visualisierung verwenden jetzt den neuen Namen.
- Kompatibilitätsdokumentation ergänzt: Codex in der ChatGPT-Desktop-App und OpenCode sind unter Windows als empfohlen dokumentiert; Linux und macOS bleiben bis zu einem eigenen Lauf ausdrücklich ungetestet.
- `README.md`, `Prompts/README.md` und `Vorlagen/README.md` dokumentieren den aktuellen unveröffentlichten Stand einschließlich Druckvorprüfung, Berichtsschemata, Finalisierungsstatus und aufrufortunabhängiger Pfadnormalisierung.
- `bewerbung.ps1 tests --suite ...` ist die gemeinsame Schnittstelle; `-MitBrowser` bleibt als Browseralias lesbar. README, technischer Workflow und Agenten-Kompatibilitätsübersicht dokumentieren die schnelle/vollständige Teilung, die OpenCode-Canary und den Alpha-Status von Ubuntu bis zur Promotion.

- Die Veröffentlichung akzeptiert ausschließlich einen aktuellen `Sichtfreigabe.json`-Nachweis, der Freigabe-ID, vorbereiteten Finalisierungsbericht und den unveränderten Artefaktsatz bindet. Das bisherige `--visuell-geprueft` bleibt nur als Kompatibilitätsargument lesbar und erteilt keine Berechtigung; vorbereitete Altstände müssen neu vorbereitet werden.
- Finalisierungsberichte verwenden für individuelle Bewerbungen Schema 7 und für den Universal-Lebenslauf Schema 2. ATS-Berichte verwenden Schema 2 und dokumentieren Token-/N-Gramm-Abdeckung, fehlende Tokens und Artefakt-Hashes.
- Berichte und Zustandsdateien werden über die gemeinsamen atomaren Schreib- und Sperrverträge aktualisiert; ein fehlgeschlagener oder unterbrochener Austausch lässt die vorherige vollständige Datei bestehen.

- Neue Bewerbungen erzeugen Schema-4-Entwürfe für Anforderungsmatrix und Evidenzindex. Erfüllte oder teilweise erfüllte Anforderungen sowie sichtbare Profilhighlights benötigen nun validierte Evidenz-IDs; `NICHT BEHAUPTEN` und `EINARBEITUNGSZIEL` können keine Direktbelege sein.
- Der Bewerbungsworkflow arbeitet verbindlich in der Reihenfolge Stellenanforderungen, stärkste Profilbelege, wahre Transferbrücken, Inhaltsentwurf und erst danach Layout. Pauschale Obergrenzen für Projekte, Kompetenzgruppen und relevante Inhaltsblöcke wurden durch Recruiter-Relevanz und Belegsubstanz ersetzt.
- Lebenslauf und Anschreiben werden als ergänzende Belegträger geprüft: wichtige Technologien benötigen Anwendungskontext, Projekte und Stationen benennen Aufgabe, eingesetzte Kenntnisse und eigenen Beitrag, und ungewöhnliche Leerfläche löst zuerst eine Inhaltsprüfung aus.
- Neue Bewerbungen erhalten Matrix-Schema 3; vorhandene Matrix-Schemata 1 und 2 bleiben ohne automatische Migration kompatibel.
- Individuelle Lebensläufe binden ein vorhandenes Passfoto vollständig als private PNG-Datenressource ein und passen dessen Darstellung an das konkrete Design an. Fehlt die Datei, entstehen weder Rückfrage noch Fotoplatz; universelle Lebensläufe bleiben stets unverändert.
- Zweiseitige Lebensläufe markieren Seitenköpfe und fachliche Abschnitte semantisch; ein Abschnitt darf nicht technisch über zwei Seiten geteilt werden. Der universelle Softwareentwicklungs-Lebenslauf bindet zusätzlich seine exakte recruiterfreundliche Abschnittsfolge.
- Technische Vorbereitung und Veröffentlichung führen `passfoto` nur bei tatsächlicher Verwendung als optionalen fünften Quellnachweis. Hinzufügen, Ändern oder Löschen der Datei entwertet bestehende technische und persönliche Sichtnachweise.
- Die Agenten-, E-Mail- und Technikhinweise benennen jetzt explizit den privaten Kandidatenpfad, die vier inhaltlich erforderlichen Nachweise, den aus `firmaSlug` abgeleiteten Markdown-Dateinamen der E-Mail, die feste A4-CSS-Geometrie und `bewerbung.ps1 finalisieren` als einzigen Standardweg. Dadurch dürfen lokale Modelle weder Dummy-Dateien noch HTML-E-Mails oder lose Direkt-Exporte als zulässige Abkürzung interpretieren.
- PowerShell 7.6 Core ist die einzige fachliche Implementierung. Bash enthält keine Bewerbungs-, JSON-, Hash- oder Dateilogik und benötigt dafür weder `jq`, Python, Node noch externe SHA-Werkzeuge.
- Neue `Bewerbungsauftrag.json` verwenden Schema 5 und speichern Ziel-, Arbeits- und Kandidatenpfad portabel relativ zu `BewerbungenRoot`. Altaufträge der Schemata 1 bis 4 bleiben ohne automatische Migration lesbar.
- Layout-, PDF-, ATS- und Finalisierungsnachweise erhalten einen Runtime-Fingerprint; ein Plattformwechsel entwertet technische Nachweise, aber weder Auftrag noch Kandidatenbestand.
- Chrome, Edge und Chromium werden plattformabhängig gesucht; ein ausdrücklich angegebener Browserpfad wird auf Existenz, Version und Chromium-Engine geprüft. Firefox bleibt auf Layoutdiagnosen beschränkt.
- Designvorlagen verwenden zusätzlich `Liberation Sans`, und alle ausführbaren PowerShell-Werkzeuge verlangen PowerShell 7.6 Core.
- Die öffentliche CLI vereinheitlicht Exitcode `0` für Erfolg, `1` für fachliche oder technische Laufzeitfehler und `2` für ungültige beziehungsweise unsichere CLI-Eingaben, nicht unterstützte Umgebungen oder eine fehlende Kernruntime.
- Die Statusrekonstruktion meldet den Checkpoint ausschließlich bei exakter Artefaktbindung als aktuell und verwendet bei jeder Abweichung weiterhin die fachlichen Originaldateien als Quelle.
- Das Ubuntu-Setup installiert nur nach ausdrücklicher Auswahl PowerShell 7.6 aus der Microsoft-Quelle, Google Chrome Stable aus der Google-Quelle und/oder `fonts-liberation2`; `--dry-run`, Bestätigung und idempotente Erkennung verhindern stille Systemänderungen.
- Der dependency-freie PNG-Leser verarbeitet die erwarteten nicht-interlaced 8-Bit-Grau-, RGB- und RGBA-Screenshots mit Filtern 0 bis 4. Windows-/Ubuntu-Parität wird über Seitenzahl, A4-Geometrie, Dichte-, Hash- und ATS-Prüfung statt binär identischer Ausgaben bewertet.

### Behoben

- Ubuntu-Regressionsläufe respektieren exklusive Dateisperren nun auch beim atomaren Ersetzen und starten parallele PowerShell-Worker ohne das ausschließlich unter Windows verfügbare `-WindowStyle`; der Bash-Dispatcher-Test erwartet die verbindliche absolute Pfadnormalisierung.
- Mehrseitige Layouts werden vor dem eigentlichen Export gegen zusätzliche Druckseiten abgesichert; CSS-Vorschauabstände über `.page + .page` können eine Fußzeile nicht mehr unbemerkt auf eine Restseite verschieben. Direkte Layout- und PDF-Diagnosen erkennen kanonische Kandidatenordner ohne verschachtelte `_Arbeitsdateien`-Ausgaben.
- Finalisierungsstufen erfassen Unterwerkzeugfehler kontrolliert im privaten Prüfstand, statt den Zustand durch einen vorzeitigen Prozessabbruch unvollständig zu lassen.
- Relative Auftragspfade werden bei direkter statischer Prüfung und beim PDF-Export gegen das tatsächliche Aufrufverzeichnis aufgelöst und nicht mehr doppelt unter `Private/Bewerbungen` angehängt.

- Verwaiste README- und Workflowverweise auf gelöschte Archiv- beziehungsweise Bash-Testdateien wurden entfernt; die frühere Bash-Fachsuite ist durch Dispatcher-, Kompatibilitäts- und Setup-Tests ersetzt.
- Die ShellCheck-Ausnahme für die beabsichtigt literale PowerShell-Versionsabfrage steht vor dem vollständigen `if`-Block und verursacht keine Parserfehler mehr.
- Vertrags-, Bericht-, Artefakt-, Publish- und Rollbackpfade werden unmittelbar vor Lesen oder Schreiben erneut symlinksicher geprüft; Verzeichnis- und interne Link-Aliasse können keine regulären Dateien oder fremden Bewerbungsziele mehr maskieren.
- Browserprofile und transiente PNG-/PDF-Ausgaben verwenden kurze, GUID-isolierte private Runroots und werden erst nach Frische-, Struktur- und Hashprüfung atomar an den endgültigen Ort übernommen.
- Headless-Chrome-Export und Layoutcheck verwenden unter verwalteten Windows-Umgebungen zusätzliche GPU-/Sandbox-Kompatibilitätsflags, damit Chrome bei deaktivierter GPU zuverlässig PDF- und PNG-Ausgaben erzeugt.
- Der Layoutcheck isoliert den tatsächlich ausgewählten A4-Seitencontainer statt ihn über fehleranfällige `nth-of-type`-Regeln auszublenden; relative Berichtspfade werden nicht mehr versehentlich unter dem Ausgabeordner verschachtelt.
- Browserprofile und leere `.browser-tmp`-Wurzeln werden mit begrenzten Wiederholungen bereinigt. Nach Freigabe eines Universal-Lebenslaufs bleibt nur das hashgebundene Aktivpaket; der datierte Arbeitsordner wird vollständig entfernt.
- Der atomare Austausch einer Universal-Aktivfassung stellt bei einem Verifikationsfehler die vorherige Fassung wieder her und kann nach einer isoliert fehlgeschlagenen Arbeitsordnerbereinigung idempotent fortgesetzt werden.

### Tests und Verifikation

- Die neue lokale schnelle Suite wurde mit 21 von 21 synthetischen Fällen bestanden; die vollständige browserfreie Suite mit 96 von 96 Fällen und die Windows-Browser-Suite mit 106 von 106 Fällen. Der gezielte Schema-5-Rollenfixture-Lauf bestand mit allen vier Rollen und vollständiger Evidenz-/Quellen-Coverage. Echte Prompt-CI-Läufe benötigen die jeweilige Runner-/Secret-Ausstattung und wurden in dieser Umgebung nicht behauptet.

- Die browserfreie Regression bestand nach Phase 2 mit 90 von 90 synthetischen Fällen. Die gezielten browserabhängigen Smoke-, Layout-, Universal-, Finalisierungs- und PDF-Fälle bestanden mit 9 von 9; die nach der Artefaktbindungs-Nachschärfung erneut ausgeführten Universal- und individuellen Finalisierungsfälle bestanden mit 4 von 4.
- Schema-4-Regressionsfälle prüfen Quellenbindung von Stellenanforderungen und Profilbelegen, fehlende explizite Stellenabdeckung, erfundene Evidenzreferenzen sowie die Wiederherstellung einer simulierten unterbrochenen Dialogtransaktion. Ein Browserfall prüft zusätzlich, dass DOM-Überlauf trotz fester A4-Geometrie abgewiesen wird.
- Die vollständige lokale PowerShell-/Chromium-Regression bestand nach der Phase-1-Änderung mit 96 synthetischen Fällen und 0 Fehlern.
- Schema-3-Regressionsfälle prüfen vollständige Recruiter-Abdeckung, fehlende beziehungsweise falsch platzierte Anker, ehrliche Salesforce-Transferbrücken, erfundene Direktpraxis sowie den Unterschied zwischen unnötig dünnem und dokumentiert schmalem Profil. Promptaudits verhindern erneut eingeführte pauschale Projektobergrenzen.
- Synthetische Passfoto-Fälle decken fehlende, gültige, beschädigte, abweichende und doppelte Einbettungen, idempotente Verarbeitung, Universal-Snapshot-Schutz, optionale Manifestbindung und die Entwertung nach Quellenänderungen ab.
- Die vollständige browserfreie PowerShell-Suite bestand lokal unter Windows mit 84 von 84 synthetischen Fällen. Die fokussierten realen Chromium-Regressionsfälle für Runtime-Auflösung sowie Universal-Vorbereitung, Aktivierung und Arbeitsordnerbereinigung bestanden mit 2 von 2 Fällen.
- Bash-Syntax sowie Dispatcher-/Kompatibilitätstests bestanden unter Git Bash. Die Ubuntu-24.04-WSL-Tests für Parser, OS-Abweisung, Herkunft, Dry-run und Idempotenz bestanden ohne Paketinstallation.
- Ein vollständiger PowerShell-/Browserlauf unter Ubuntu wurde lokal noch nicht ausgeführt. Die feste CI-Matrix und die getrennten Browser-Smokes sind eingerichtet; Ubuntu bleibt bis zu den dokumentierten Nachweisen Alpha.

## Version 1.8.0 - 2026-08-06

### Hinzugefügt

- Providerneutrale Root-Konfiguration `opencode.json`, die OpenCode-Sitzungsfreigaben deaktiviert, den nativen `AGENTS.md`-Einstieg unverändert nutzt und Modell sowie Provider für OpenCode, Editor-Integrationen und `ollama launch opencode` offenlässt.
- Read-only-Werkzeug `Tools/Ermittle-Bewerbungsstatus.ps1`, das den letzten oder ausdrücklich genannten Bewerbungsstand aus Auftrag, Dialog, Matrix, Kandidaten, technischen Berichten, Hashnachweisen und Manifest rekonstruiert und die nächsten benötigten Promptmodule maschinenlesbar ausgibt.

### Geändert

- Der kanonische Ablauf speichert die vollständige Stellenbeschreibung vor dem Profildialog, trennt vorläufige Kriterien von der erst nach der Strategie finalisierten Matrix und setzt den Dialogstatus vor der technischen Finalisierung nachvollziehbar auf abgeschlossen.
- Bewerbungsaufträge mit ausdrücklich genanntem Dokumentumfang überspringen unnötige Auswahlfragen. Auswahl B bedeutet ausschließlich Universal-Lebenslauf, Anschreiben und E-Mail; Universal-Lebenslauf plus Anschreiben ohne E-Mail wird korrekt als freie Auswahl E gespeichert.
- Neue fachliche Angaben gelten ohne weitere Nachfrage standardmäßig nur für den aktuellen Auftrag. Eine Frage zur dauerhaften Speicherung entsteht nur auf ausdrücklichen Wunsch des Nutzers.
- E-Mail-only verwendet einen kompakten Profil- und Matrixabgleich. Kriterien werden normalisiert und dedupliziert; Benefits, Werbeaussagen und rein beschreibende Aufgaben erzeugen keine künstlichen Eignungspunkte.
- `stretch` bleibt eine transparente Risikoeinstufung und kein automatisches Bewerbungsverbot. Bei ausdrücklichem Bewerbungswunsch wird `nicht_bewerben` nur durch einen ebenso ausdrücklichen Stopp gesetzt.
- Qualitätsregeln referenzieren die fachlichen Einzelmodule, prüfen nur die tatsächlich ausgewählten Dokumente und verwenden kompakte Kriterien-IDs statt wiederholter Volltexte.
- Chrome beziehungsweise Edge ist durchgängig der verbindliche Browser für maschinelle Layout- und PDF-Nachweise; Firefox bleibt höchstens eine klar gekennzeichnete manuelle Diagnosevorschau.
- Der Finalisierer vermeidet einen redundanten statischen Vorlauf: Bei HTML-Aufträgen übernimmt der PDF-Export den ersten statischen Check, während der abschließende statische und fachliche Check nach der automatischen Berichtsergänzung erhalten bleibt.
- Agenten laden den vollständigen Bewerbungsworkflow nur für Bewerbungs-, Daten-, Fortsetzungs- oder workflowbezogene Entwicklungsaufträge und nicht mehr für jede reine technische Projektfrage.

### Behoben

- Der bisherige Widerspruch zwischen B und E bei „Universal-Lebenslauf plus Anschreiben ohne E-Mail“ ist beseitigt.
- Eine ausdrücklich gewünschte Bewerbung kann nicht mehr allein wegen der Eignungskategorie `stretch` unbemerkt auf `nicht_bewerben` wechseln.
- Stellenbeschreibung, Strategie und gewichtete Matrix entstehen nun in einer Reihenfolge, die Quellenverlust, doppelte Bewertung und voneinander abweichende Zwischenstände verhindert.
- Fortsetzungen müssen den Arbeitsstand nicht mehr durch breit gestreutes erneutes Einlesen rekonstruieren, sofern das neue Statuswerkzeug verfügbar ist.

### Sicherheit und Datenschutz

- OpenCode-Sharing ist im Repository standardmäßig deaktiviert; `opencode.json` enthält keine privaten Inhalte, Promptkopien, Zugangsdaten oder fest verdrahteten Cloudanbieter.
- Die frühe lokale Sicherung der Stellenbeschreibung bleibt von Kandidaten- und Versandfreigaben getrennt. Private Daten werden weiterhin ausschließlich unter `Private/` verarbeitet.
- Technische Prüfungen dürfen nur tatsächlich erzeugte Chrome-/Edge-Nachweise behaupten; optionale manuelle Browseransichten ersetzen weder Hashbindung noch persönliche Sichtprüfung.

### Tests und Verifikation

- Regressionstests decken OpenCode-Konfiguration, korrigiertes A–E-Routing, Standardentscheidung `nur_auftrag`, Matrix-Deduplizierung, E-Mail-only, Chromium-Vertrag, Statusrekonstruktion und die fehlende Promptduplizierung ab.
- Die lokale OpenCode-Konfiguration wurde mit isoliertem Benutzerprofil aufgelöst; OpenCode `1.18.10` übernahm `share: disabled`, ohne Provider oder Modell aus dem Repository zu erzwingen. Ollama `0.32.6` wurde erkannt.
- Am 06.08.2026 bestanden 61 von 61 Tests der Kern-Regressionssuite und 68 von 68 Tests der lokal freigegebenen Chrome-Browsermatrix. Der vorangegangene Browserlauf in der verwalteten Sandbox scheiterte ausschließlich am Chrome-Prozessstart.
- Ein neuer realer Dialoglauf mit einem lokalen Ollama-Modell wurde nicht ausgeführt; der frühere `qwen3.5:9b`-Versuch bleibt wegen Zeitüberschreitung ausdrücklich nicht bestanden.

## Version 1.7.0 - 2026-08-05

### Hinzugefügt

- Zentraler, agentenunabhängiger Bewerbungsdialog in `Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md` mit Auswahl A–E, Zahlen- und Freitextantworten, direkter Übernahme eindeutiger Aufträge und höchstens einer vereinfachten Wiederholung bei Mehrdeutigkeit.
- Schema 4 für `Bewerbungsauftrag.json` mit verbindlichem `dokumentumfang`, E-Mail-only-Bestätigung sowie normalisierten `dialog.rueckfragen` und `dialog.angaben` für eine Fortsetzung ohne Chatverlauf.
- Relevanzfilter für Profilrückfragen, höchstens drei voneinander unabhängige Fragen pro Dialogrunde und wahrheitsgemäße Klassifikation von belegter, teilweiser, übertragbarer, fehlender, widersprüchlicher oder möglicherweise vorhandener Erfahrung.
- `Tools/Pruefe-Dialogstatus.ps1` für Umfangs-, Rückfrage-, Widerspruchs-, Speicher- und Rohchatprüfungen vor der Dokumenterstellung.
- `Tools/Uebernehme-Dialogangabe.ps1` für die kontrollierte Kennzeichnung als nur auftragsbezogen oder die ausdrücklich bestätigte, hashgebundene Übernahme in ein zulässiges privates Profilziel mit Wiederherstellung bei erkannten Schreibfehlern.
- Dokumentierter Katalog der neun Nutzerfälle unter `Tests/Interaktiver-Bewerbungsdialog.md` mit getrenntem Status für deterministische Verträge, dokumentierte Sprachszenarien und nicht ausgeführte reale Modelltests.

### Geändert

- Eine bloße Stellenbeschreibung oder ein allgemeiner Bewerbungswunsch startet nicht mehr ungefragt eine Vollbewerbung. Ein bereits eindeutig genannter Umfang überspringt dagegen die allgemeine Auswahlfrage.
- PowerShell- und Bash-Ordnerhelfer akzeptieren A–E, freie Kombinationen und die ausdrückliche Bestätigung eines reinen E-Mail-Auftrags und erzeugen nur passende Entwurfs- und Kandidatendateien.
- Statischer Prüfer, Inhaltsprüfung, PDF-Export, ATS-Prüfung, Finalisierung, Manifest und Prüfberichte leiten ihre erwarteten Dateien aus dem Schema-4-Dokumentumfang ab; der Layoutcheck verarbeitet den von der Finalisierung umfangsgerecht ausgewählten Kandidatenbestand.
- Ein bestätigter reiner E-Mail-Auftrag erreicht das persönliche Freigabe-Gate ohne vorgetäuschten Browserlauf; Layout-, PDF- und ATS-Berichte werden dabei als `nicht_erforderlich` geschrieben und die E-Mail muss persönlich als Text geprüft werden.
- Die dateibasierte Fortsetzung berücksichtigt Umfang, beantwortete und offene Rückfragen, nur auftragsbezogene Angaben, Speicherentscheidungen, Widersprüche sowie Hashnachweise bereits ausgeführter Profiländerungen.
- Bestehende Aufträge bis Schema 3 bleiben über die beiden alten `dokumentmodus`-Werte rückwärtskompatibel lesbar. Fehlende Dateien werden nicht als nachträglich eingeschränkter Dokumentumfang interpretiert.
- README, Promptübersicht, Datei-/Ordnerregeln, Qualitätsregeln und technischer Workflow beschreiben dynamische Ausgaben, Sicht- beziehungsweise Textprüfung und die neuen Werkzeuge und Dateiverträge.

### Behoben

- Reine E-Mail-Aufträge erzeugen erst nach ausdrücklicher Bestätigung einen Entwurf und behaupten darin keine nicht vorhandenen Bewerbungsanlagen.
- PowerShell- und Bash-Fortsetzungen behandeln den ausdrücklich gespeicherten Universalmodus in allen lesbaren Legacy-Schemata als Auswahl B und verweigern abweichende Quellpfade, Dateinamen oder Hashes.
- Der Bash-Ordnerhelfer maskiert Steuerzeichen aus CRLF-Stammdaten JSON-konform, parst den erzeugten Auftrag vor der Erfolgsmeldung und verlangt hashbare Quelldateien vor jeder Ordneranlage.
- PDF-Satz und Exportbericht sowie veröffentlichter Zielsatz und Finalisierungsbericht werden gemeinsam übernommen; bei einem Fehler wird der alte Stand wiederhergestellt oder ein verbliebener Wiederherstellungspfad ausdrücklich erhalten.
- Der Finalisierungsbericht bindet Layout-, PDF- und ATS-Bericht zusätzlich per SHA-256, prüft deren semantische Artefaktzuordnung und verweigert veraltete, unvollständige oder um fremde Kandidatendateien erweiterte Nachweise.
- Versand-PDFs müssen auch bei einem intern konsistenten Manifest exakt zu den ausgewählten HTML-Dateinamen passen; zusätzliche, abgewählte, falsch benannte oder falsch platzierte PDFs werden abgelehnt.

### Sicherheit und Datenschutz

- Neue Nutzerangaben gelten standardmäßig nur für den aktuellen Bewerbungsauftrag. Dauerhafte Änderungen werden gebündelt angeboten und benötigen die transparente Zielformulierung sowie eine eindeutige ausdrückliche Zustimmung.
- Als dauerhafte Profilziele sind ausschließlich `Private/Daten/01_PERSOENLICHE_DATEN.md` für Identität, Kontakt und globale Logistik sowie `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` für fachliche Angaben zulässig.
- Der Agentenworkflow prüft vor einer Profilübernahme auf sinngleiche Einträge; das Werkzeug verhindert im gewählten Zielabschnitt exakte Dubletten, bindet die bestätigte Formulierung an Vorher-/Nachher-Hashes und verändert keine anderen Profildateien, Universal-Lebensläufe oder Bewerbungen.
- Vor einer dauerhaften Profilzustimmung bindet ein Pending-Snapshot Zieltyp, Datei, Abschnitt, offengelegte Formulierung und Ausgangshash. Das Übernahmewerkzeug akzeptiert nur exakt diese bestätigten Werte, schließt die verknüpfte Speicherfrage atomar und leitet den verbleibenden Dialogstatus neu ab.
- Unklare oder widersprüchliche Wahrheitsebenen, fehlende Zustimmung, falsche Profilziele, geänderte Formulierungen, veraltete Hashes und erstmalige Übernahmen nach Beginn der Dokumenterstellung werden fehlergeschlossen abgelehnt.
- Der Dialogzustand speichert nur normalisierte fachliche Angaben und Entscheidungsnachweise; Rohchats, vollständige Prompts und unnötige sensible Details sind unzulässig.
- Mehrdeutige Umfangs- oder Speicherantworten bleiben fehlergeschlossen: Nach höchstens einer vereinfachten Nachfrage werden weder Kandidatendateien erzeugt noch Profildaten verändert.

### Tests und Verifikation

- Die Regressionssuite wurde um deterministische Schema-4-, Auswahl-, E-Mail-only-, Profilhash-, Deduplizierungs-, Widerspruchs-, Fortsetzungs- und Fail-closed-Verträge sowie negative Zustimmungs-, Zielbindungs-, Frage- und Statusfälle erweitert.
- Die neun Dialogszenarien trennen statische beziehungsweise fixturebasierte Nachweise ausdrücklich vom noch offenen natürlichen Sprachverhalten realer Agenten und Modelle.
- Am 05.08.2026 bestanden 59 von 59 Tests der Kern-Regressionssuite und 66 von 66 Tests der lokal freigegebenen Browser-Suite. Der separate Bash-Regressionslauf und die PowerShell-Parserprüfung bestanden ebenfalls.
- Ein realer Ollama-Dialogtest wurde nicht ausgeführt. ShellCheck und PSScriptAnalyzer waren lokal nicht installiert und werden für diesen Stand nicht als ausgeführt behauptet.

## Version 1.6 - 2026-08-05

### Hinzugefügt

- Dünner Claude-Code-Adapter `CLAUDE.md` mit echtem `@AGENTS.md`-Import und Verweis auf den kanonischen Bewerbungsworkflow.
- Anbieterunabhängige Laufzeitfähigkeitenprüfung für Datei- und Terminalzugriff, PowerShell beziehungsweise kompatible Shell, Chrome/Edge, PNG-Auswertung, Nutzungsdaten und Sandboxgrenzen.
- Dateibasierter Fortsetzungsvertrag, der die zuletzt bearbeitete Bewerbung aus Auftrag, Arbeitsnotizen, Matrix, Kandidaten, Prüfberichten, Finalisierungsbericht, Hashes und Manifest rekonstruiert, ohne Chat-Memory vorauszusetzen.
- Dokumentierte Agenten-Smoke- und Schutztests unter `Tests/Agenten-Kompatibilitaet.md`.
- Regressionstests für Claude-/Gemini-Adapter, kanonische Einzelquelle, exakte Pfadschreibweise, fünf direkte Einstiege, Fähigkeiten, Fortsetzung und eingebettete Fremdanweisungen.

### Geändert

- `AGENTS.md` ist jetzt ein kompakter, agentenunabhängiger Root-Einstieg für Vollbewerbung, Anschreiben mit Universal-Lebenslauf, Dateneinrichtung/-prüfung, Fortsetzung und Projektentwicklung.
- OpenCode nutzt die vorhandene Root-`AGENTS.md`; eine zusätzliche `opencode.json` ist nicht erforderlich und wurde deshalb nicht angelegt.
- README, Hero, Schnellstart, Voraussetzungen, Hilfebereich, Datenschutz, Entwicklerstruktur und Plattformstatus wurden von einem Codex-/VS-Code-Hauptweg auf auswählbare Agentenumgebungen umgestellt.
- README dokumentiert Codex CLI, OpenCode, `ollama launch opencode`, Claude Code, die Trennung von Agent und Modell sowie die Grenzen kleiner lokaler Modelle.
- `Prompts/README.md` und die öffentlichen Datei-/Ordnerregeln berücksichtigen Claude Code, OpenCode und Ollama ohne fachliche Regeln zu duplizieren.
- VS-Code-spezifische Überschriften im technischen Prompt wurden auf Windows/PowerShell verallgemeinert.
- Der Linux-Portierungsplan grenzt die bereits umgesetzte Agentenabstraktion von der noch offenen technischen Linux-Parität ab; der historische Frontend-Plan ist sichtbar als nicht freigegebenes Archiv markiert.
- Der standardisierte Nichtverfügbarkeitsfall lautet jetzt überall: `Tokenverbrauch: Von dieser Agentenumgebung nicht bereitgestellt.`

### Sicherheit und Datenschutz

- Fehlende Werkzeug-, Browser- oder Bildfähigkeiten müssen offen gemeldet werden; insbesondere darf kein Agent eine nicht ausgeführte PNG-Sichtprüfung vortäuschen.
- Lokale Ollama-Modellverarbeitung wird von möglichen Cloudzugriffen der Agentenumgebung und weiterer Werkzeuge abgegrenzt; `Private/` und `.gitignore` werden weiterhin nicht als Verschlüsselung dargestellt.
- Alte Sichtprüfungsbestätigungen dürfen nach Quellen-, Kandidaten- oder Screenshotänderungen auch über Sitzungsgrenzen hinweg nicht wiederverwendet werden.

### Tests und Verifikation

- PowerShell 7.6.4, Codex CLI 0.146.0-alpha.9.2, OpenCode 1.18.10, Ollama 0.32.5 und Chrome 150.0.7871.187 wurden lokal erkannt.
- Eine frische Codex-CLI-Read-only-Sitzung erkannte das Projekt über `AGENTS.md` und lud `Prompts/00_AGENTEN_START_HIER.md` selbstständig.
- Eine zweite frische Codex-Sitzung ignorierte die eingebettete Aufforderung zum Offenlegen privater Dateien und extrahierte nur sachliche Stellenanforderungen.
- Der Ollama-Launcher startete OpenCode mit einem lokalen Modellprofil bis zur Versionsausgabe; der anschließende `qwen3.5:9b`-Frischsitzungstest überschritt das 120-Sekunden-Limit und gilt nicht als bestanden.
- Die vollständige lokale Browsermatrix bestand außerhalb der verwalteten Sandbox mit 48 von 48 Tests; der vorangegangene Sandboxlauf scheiterte ausschließlich am Chrome-Prozessstart.
- Claude Code war lokal nicht installiert; IDE-, Desktop-, Claude-, Gemini- und vollständige agentenspezifische Bewerbungsdurchläufe bleiben ausdrücklich ungetestet.

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
