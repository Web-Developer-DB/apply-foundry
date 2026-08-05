# Übergabeplan: gleichwertiger Windows-/Linux-Betrieb

Stand: 2026-07-21  
Status: **nur Planung; noch keine Portierungsänderungen umgesetzt**

Hinweis vom 05.08.2026: Der agentenunabhängige Root-Einstieg und die anbieterneutrale Fähigkeitenprüfung sind inzwischen in `AGENTS.md` und `Prompts/00_AGENTEN_START_HIER.md` umgesetzt. Das stellt noch keine technische Linux-Parität her; insbesondere bleiben die unten geplanten Module, Browseranpassungen und vollständigen Linux-Prüfläufe offen.

## 1. Ziel und Definition von „gleichwertig"

Das Repository soll auf Windows und Linux denselben vollständigen Bewerbungsworkflow bieten:

1. Bewerbung und privaten Arbeitsordner anlegen.
2. Stammdaten, Inhalt und Dateistruktur prüfen.
3. jede explizite A4-Seite als Screenshot rendern und die Layoutdichte prüfen.
4. genau zwei PDFs erzeugen und technisch validieren.
5. die PDF-Textschicht per ATS-Prüfung kontrollieren.
6. nach einer echten Sichtprüfung atomar nach `Versand/` und `Intern/` veröffentlichen.

Gleichwertig bedeutet: gleiche fachliche Regeln, gleiche Sicherheitsgrenzen, gleiche Pflichtartefakte, gleiche Berichts-Schemata und vergleichbare Exitcodes. PDF- und PNG-Dateien müssen wegen unterschiedlicher Browser-/Fontversionen nicht binär identisch sein, aber dieselben strukturellen und qualitativen Prüfungen bestehen.

Die Agentenlogik muss das Betriebssystem vor dem ersten Toolaufruf erkennen:

- Windows: PowerShell-Aufrufe verwenden.
- Linux: Bash-Einstieg verwenden; dieser ruft die plattformneutrale PowerShell-7-Kernlogik auf.
- Während eines Laufs nicht zwischen den Skriptfamilien wechseln.
- Fehlt eine Pflichtabhängigkeit, klar abbrechen; keinen stillen Teilworkflow als erfolgreich melden.

## 2. Bewusste Architekturentscheidung

Die vorhandenen umfangreichen `.ps1`-Prüfer bleiben die **eine kanonische Fachimplementierung**. Sie werden mit PowerShell 7 (`pwsh`) wirklich plattformneutral gemacht. Unter Linux kommt ein dünner Bash-Dispatcher hinzu, der GNU-artige Optionen in die bestehenden PowerShell-Parameter übersetzt.

Damit werden nicht mehrere tausend Zeilen Prüf-, Hash-, Staging-, PDF- und ATS-Logik ein zweites Mal in Bash dupliziert. Das bestehende `Tools/neue-bewerbung.sh` wird nach Herstellung der Parität nur noch ein kompatibler Einstieg in die kanonische Implementierung; seine derzeit abweichende JSON- und Ordnerlogik darf nicht dauerhaft parallel weiterleben.

Vorgesehene neue Bausteine:

- `Tools/Common/Platform.psm1`: Plattform-, Pfad-, Prozess-, Browser- und Runtime-Helfer.
- `Tools/Common/PngTools.psm1`: dependency-freie, plattformneutrale PNG-Auswertung für die Dichteprüfung.
- `Tools/bewerbung.sh`: Linux-Dispatcher für alle Workflow-Schritte.
- `Tools/Pruefe-Umgebung.ps1`: Preflight für Runtime, Browser, Schreibrechte, Temp-Verzeichnis und Fonts.
- `Tests/Bash/test-bewerbung-cli.sh`: Tests des Linux-Dispatchers und seiner Exitcode-/Argumentweitergabe.

PowerShell 7 wird auf beiden Systemen die Referenzruntime. Der bisher behauptete Fallback auf Windows PowerShell 5.1 wird entfernt, weil bereits verwendete APIs aus modernem .NET stammen. Vor der Implementierung auf dem Ziel-Linux ist die konkrete unterstützte Mindestversion anhand der vorhandenen `ZLibStream`- und Pfad-APIs festzulegen und anschließend mit `#requires` sowie im Preflight durchzusetzen.

## 3. Aktueller Ausgangszustand

Am 2026-07-21 wurde unter Windows folgender Baseline-Test ausgeführt:

```powershell
.\Tests\Run-RegressionTests.ps1
```

Ergebnis: **31 bestanden, 0 fehlgeschlagen**. Darin war die bestehende Bash-Regressionssuite enthalten. Die optionalen echten Browserfälle (`-MitBrowser`) wurden bei dieser Baseline nicht ausgeführt.

Die wichtigsten bekannten Lücken sind:

| Bereich | Aktueller Befund |
| --- | --- |
| Browsererkennung | `Exportiere-PDF.ps1` und `Layoutcheck-Bewerbung.ps1` kennen im Wesentlichen Windows-Pfade und `chrome.exe`/`msedge.exe`; typische Linux-Namen wie `google-chrome`, `chromium` oder `microsoft-edge` fehlen. |
| Browserprozess | `Start-Process -WindowStyle Hidden` ist Windows-zentriert; Timeouts beenden unter Linux nicht zuverlässig den ganzen Browserprozessbaum. |
| Layoutdichte | `System.Drawing.Common` ist unter modernem .NET/Linux kein verlässlicher Weg. Der Fehler wird derzeit nur zur Warnung, wodurch Linux qualitativ schwächer wäre. |
| Ordnerhelfer | PowerShell prüft standardmäßig die Stammdaten; das große Bash-Duplikat tut dies nicht und erzeugt JSON selbst. Beide Wege können auseinanderlaufen. |
| Persistente Pfade | `Bewerbungsauftrag.json` speichert absolute, betriebssystemspezifische Pfade. Ein unter Windows angelegter Auftrag ist nach einem Umzug zu Linux nicht zuverlässig nutzbar. |
| Pfadsicherheit | Mehrere Prüfungen verwenden Stringpräfixe und pauschal `OrdinalIgnoreCase`; Linux ist case-sensitive und kennt Symlinks als häufigen Pfadbestandteil. |
| Tests | Die vollständige PowerShell-Suite läuft in CI nur auf Windows. Ubuntu führt nur ShellCheck und den Bash-Ordnerhelfertest aus. |
| Browsertests | Der Test-Runner sucht Chrome ausschließlich unter einem festen Windows-Pfad; die sechs Browserfälle laufen in CI derzeit nirgends verbindlich. |
| Shell-Dateimodus | Beide vorhandenen `.sh`-Dateien stehen in Git auf Modus `100644`, also nicht ausführbar. |
| Fonts | Die HTMLs bevorzugen Arial/Helvetica. Arial ist auf Linux typischerweise nicht vorhanden; dadurch können Zeilenumbrüche und Seitendichte abweichen. |
| Instruktionen | README und Prompts beschreiben den vollständigen Abschlussworkflow fast ausschließlich mit `.ps1`-Befehlen und erklären Linux noch als Alpha. |

## 4. Umsetzungsphasen

### Phase 0 – Linux-Baseline erfassen

Nach dem Umgebungswechsel zuerst **nichts ändern**, sondern im Repository ausführen und Ergebnisse notieren:

```bash
git status --short
uname -a
cat /etc/os-release
bash --version
pwsh -NoLogo -NoProfile -Command '$PSVersionTable | Format-List PSVersion,PSEdition,Platform,OS'
command -v bash
command -v pwsh
command -v google-chrome
command -v google-chrome-stable
command -v chromium
command -v chromium-browser
command -v microsoft-edge
command -v microsoft-edge-stable
command -v firefox
git ls-files -s Tools Tests
```

Optionale Programme dürfen bei `command -v` fehlen; entscheidend ist, welcher Chromium-basierte Browser tatsächlich vorhanden ist. Danach die unveränderte Baseline probieren:

```bash
bash -n Tools/neue-bewerbung.sh
bash -n Tests/Bash/test-neue-bewerbung.sh
bash Tests/Bash/test-neue-bewerbung.sh
pwsh -NoLogo -NoProfile -File Tests/Run-RegressionTests.ps1
```

Falls ShellCheck vorhanden ist:

```bash
shellcheck Tools/neue-bewerbung.sh Tests/Bash/test-neue-bewerbung.sh
```

Jeden Linux-Fehler mit Befehl, Exitcode und Ausgabe festhalten. Keine Prüfung abschwächen, nur damit die Baseline grün wird.

### Phase 1 – Runtime und gemeinsame Plattformhelfer

1. Eine verbindliche PowerShell-7-Mindestversion festlegen; kein Fallback auf `powershell.exe`.
2. `#requires` in allen ausführbaren `.ps1`-Tools und im Test-Runner ergänzen.
3. `Tools/Common/Platform.psm1` anlegen und dort zentral implementieren:
   - sichere Erkennung von Windows/Linux;
   - aktuelle `pwsh`-Executable bestimmen;
   - OS-gerechten Pfadvergleich bereitstellen;
   - kanonische Pfadauflösung einschließlich vorhandener Symlinks;
   - sicheren Kindpfad über relative Pfade statt bloßem Stringpräfix prüfen;
   - native Prozesse mit einer echten Argumentliste starten;
   - stdout/stderr und Exitcode erfassen;
   - bei Timeout den kompletten Prozessbaum beenden und auf das Ende warten;
   - Browserkandidaten inklusive tatsächlichem Programm und Engine zurückgeben.
4. `Tools/Pruefe-Umgebung.ps1` hinzufügen. Der Check muss verständlich zwischen Pflicht, optional und nicht unterstützt unterscheiden und darf keine Pakete selbst installieren.
5. Alle Defaultpfade aus einzelnen Segmenten mit `Join-Path`/`Path.Combine` bauen. Keine nativen Programme mit unnormalisierten Backslash-Pfaden aufrufen.

Wichtig für Pfade:

- Pfad-Containment muss auf Linux case-sensitive und auf Windows case-insensitive prüfen.
- Für Dateinamen des veröffentlichten Pakets dürfen Case-only-Dubletten weiterhin plattformübergreifend verboten werden, damit ein Linux-Ergebnis auch auf Windows kopierbar bleibt.
- Für noch nicht existierende Ziele den real aufgelösten Elternordner prüfen.
- Symlinks dürfen keinen Schreib- oder Veröffentlichungsweg aus `Private/Bewerbungen/` herausführen.
- Pfade mit Leerzeichen, Umlauten und Bindestrichen müssen als einzelne native Argumente erhalten bleiben.

### Phase 2 – alle PowerShell-Tools plattformneutral machen

Folgende Tools auf das gemeinsame Modul umstellen:

- `Tools/Neue-Bewerbung.ps1`
- `Tools/Pruefe-Stammdaten.ps1`
- `Tools/Pruefe-Bewerbungsinhalt.ps1`
- `Tools/Pruefe-Bewerbung.ps1`
- `Tools/Layoutcheck-Bewerbung.ps1`
- `Tools/Exportiere-PDF.ps1`
- `Tools/Pruefe-ATS.ps1`
- `Tools/Finalisiere-Bewerbung.ps1`

Dabei insbesondere:

1. lokale Kopien von `Test-IsSafeChildPath`, `Get-PowerShellExecutable`, Browsererkennung und Prozessabbruch entfernen und durch getestete gemeinsame Funktionen ersetzen;
2. direkte Pfadvergleiche mit `-eq`/`-ne` nur dort behalten, wo sie keine Pfadidentität prüfen;
3. Berichte weiterhin in UTF-8 ohne betriebssystemspezifische Zeilenannahmen schreiben;
4. Exitcodes vereinheitlichen: `0` Erfolg, `1` fachlicher/technischer Laufzeitfehler, `2` ungültige CLI-Eingabe beziehungsweise bewusst verweigerte Anlage;
5. temporäre Ordner ausschließlich unter dem vorgesehenen Arbeits- oder System-Temp-Ordner erzeugen und bei Erfolg wie Fehler sicher bereinigen;
6. Fehlermeldungen mit erkanntem OS, tatsächlich verwendetem Browserpfad und relevanter stderr-Ausgabe anreichern, ohne private Inhalte auszugeben.

### Phase 3 – portable Auftrags- und Berichtspfade

`Bewerbungsauftrag.json` auf ein neues Schema umstellen, das keine absoluten Windows-/Linux-Pfade als Identität benutzt.

Empfohlenes Schema-3-Prinzip:

- Pfade normalisiert mit `/` speichern.
- `ziel`, `arbeit` und `kandidat` relativ zu `BewerbungenRoot` speichern.
- Pfade beim Lesen gegen den tatsächlich übergebenen Arbeitsordner rekonstruieren und sicher validieren.
- Firma, Rolle, Datum und Slugs bleiben zusätzliche fachliche Identitätsmerkmale.

Kompatibilität:

1. Neu angelegte Bewerbungen schreiben nur Schema 3.
2. Schema-2-Aufträge mit alten absoluten Pfaden müssen lesbar bleiben: Die alten Pfade nicht blind verwenden, sondern die erwartete Struktur aus dem aktuellen Arbeitsordner und den Identitätsfeldern rekonstruieren.
3. Keine vorhandene private Datei still überschreiben. Falls eine dauerhafte Migration nötig ist, explizite Migration mit Backup und Bericht anbieten.
4. Alte `Finalisierungsbericht.json`-, Layout-, PDF- und ATS-Nachweise gelten nach einem Betriebssystemwechsel als laufzeitgebunden und werden vollständig neu erzeugt. Eine Veröffentlichung mit alten Windows-Nachweisen unter Linux muss verweigert werden.
5. Neue Berichte sollen Artefakte möglichst relativ zu ihrem Arbeitsordner referenzieren; Hashes und Schemafelder bleiben verbindlich.

### Phase 4 – Linux-CLI ohne doppelte Fachlogik

`Tools/bewerbung.sh` als ausführbaren Dispatcher implementieren. Vorgesehene Subcommands:

```text
diagnose
neu
stammdaten
inhalt
pruefen
layout
pdf
ats
finalisieren
tests
```

Anforderungen:

- `#!/usr/bin/env bash` und `set -euo pipefail`;
- eigener Pfad wird unabhängig vom aktuellen Arbeitsverzeichnis aufgelöst;
- verständlicher Fehler, wenn `pwsh` fehlt oder zu alt ist;
- GNU-artige Langoptionen wie `--arbeitsordner`, `--browser`, `--veroeffentlichen`, `--visuell-geprueft`, `--visuelle-freigabe-notiz` und `--mit-layoutcheck`;
- Werte unverändert als einzelne Argumente an PowerShell weitergeben;
- unbekannte/fehlende Optionen mit Exitcode 2 ablehnen;
- Exitcode des kanonischen Tools unverändert zurückgeben;
- keine Ausgabe per `eval` oder zusammengesetzter Shell-Befehlszeile ausführen;
- keine automatische Paketinstallation und kein automatisches `--no-sandbox`.

`Tools/neue-bewerbung.sh` wird als rückwärtskompatibler dünner Wrapper auf `bewerbung.sh neu` reduziert. Seine bisherigen Optionen bleiben funktionsfähig. Die Bash- und PowerShell-Anlage erzeugen danach garantiert denselben Auftrag, dieselben Dateien und dieselben Validierungsfehler, weil nur eine Fachimplementierung existiert.

Alle `.sh`-Einstiege und Bash-Tests mit Git-Modus `100755` versionieren. `.gitattributes` erzwingt bereits LF und soll beibehalten werden.

### Phase 5 – Browser, Screenshots, Dichte und PDFs auf Linux

#### Browsererkennung

Mindestens folgende Kandidaten berücksichtigen:

- Windows Chrome: bekannte Installationspfade, `chrome`, `chrome.exe`;
- Linux Chrome: `google-chrome`, `google-chrome-stable`;
- Linux Chromium: `chromium`, `chromium-browser`, gegebenenfalls `/snap/bin/chromium`;
- Edge: `msedge`/`msedge.exe`, `microsoft-edge`, `microsoft-edge-stable`;
- Firefox für Layout: `firefox`/`firefox.exe` und bekannte OS-Pfade.

`chromium` als auswählbaren Browserwert zulassen. Im Bericht sowohl den logischen Browsernamen als auch Engine, aufgelöste Executable und Version festhalten. Für PDF bleibt eine Chromium-basierte Engine Pflicht; Firefox darf einen fehlgeschlagenen PDF-Export nicht als bestanden erscheinen lassen.

#### Prozessstart

- `ProcessStartInfo.ArgumentList` oder eine gleichwertig sichere API verwenden; keine manuell zusammengefügte Argumentzeile.
- `WindowStyle` nur Windows-spezifisch setzen oder vollständig durch den headless Prozessstart ersetzen.
- Browserprofil pro Lauf eindeutig und kurz benennen.
- bei Timeout den gesamten Prozessbaum beenden;
- nach dem Lauf prüfen, dass keine zu diesem Profil gehörenden Kinder weiterlaufen;
- stderr bei Fehlern in begrenzter Länge in den Bericht übernehmen;
- `--no-sandbox` niemals automatisch setzen. Wenn eine konkrete Umgebung es zwingend erfordert, nur über einen expliziten, dokumentierten Opt-in mit Sicherheitswarnung.

#### PNG-Dichteprüfung

`System.Drawing.Common` vollständig aus `Layoutcheck-Bewerbung.ps1` entfernen. In `PngTools.psm1` einen kleinen, getesteten PNG-Leser für Browser-Screenshots implementieren:

- PNG-Signatur und IHDR validieren;
- 8-Bit-Graustufen/RGB/RGBA der Browser-Screenshots unterstützen;
- IDAT via vorhandener .NET-ZLib-API dekomprimieren;
- PNG-Filter 0 bis 4 korrekt rückgängig machen;
- Interlace oder unbekannte Farbtypen ausdrücklich ablehnen;
- dieselbe untere Weißraumheuristik auf Windows und Linux anwenden.

Kann die Dichteprüfung im Standardlauf nicht ausgeführt werden, ist das kein stiller Linux-Qualitätsverlust: Der Layoutcheck muss fehlschlagen, außer der Nutzer hat sie mit dem bereits vorhandenen expliziten Schalter bewusst deaktiviert. Decoder-Tests mit kleinen deterministischen PNG-Fixtures ergänzen.

#### Fonts

Im Preflight mit `fc-match` beziehungsweise einem plattformgerechten Gegenstück die tatsächlich verwendete Schrift erfassen. Eine freie, auf beiden Plattformen verfügbare Schriftfamilie bevorzugen oder eine klar dokumentierte Linux-Fontabhängigkeit festlegen. Keine fremde Schrift ohne Lizenz in das Repository kopieren. Die Abnahme erfolgt visuell und über Seiten-/Dichteinvarianten, nicht über Pixelgleichheit.

### Phase 6 – Testmatrix ausbauen

#### `Tests/Run-RegressionTests.ps1`

1. `pwsh` plattformneutral bestimmen.
2. Bash mit `Get-Command bash` suchen; keinen Scoop-/`USERPROFILE`-Pfad voraussetzen.
3. Browser über dieselbe produktive Browsererkennung suchen; keinen festen `C:\Program Files\...`-Pfad.
4. Wenn ein Browserjob ausdrücklich angefordert ist, darf ein fehlender Browser nicht nur zum Skip führen, sondern muss den dafür vorgesehenen CI-Job fehlschlagen lassen.
5. Temp-Cleanup mit kanonischem Pfad und OS-gerechter Prüfung absichern.
6. Tests für Leerzeichen, Umlaute, Case-only-Namen, Symlink-Escape und relative Auftragspfade hinzufügen.
7. Schema-2-Lesekompatibilität und Schema-3-Neuanlage testen.
8. Vorbereitung unter einem Pfad und simuliertes Öffnen unter einem anderen Root testen; alte Laufnachweise müssen verworfen, der Auftrag aber weiter nutzbar sein.
9. Nach Timeout sicherstellen, dass kein Browserprozess mit dem Testprofil übrig bleibt.

#### Bash-Tests

- den bisherigen `/tmp/*`-Zwang gegen das kanonisch aufgelöste `${TMPDIR:-/tmp}` ersetzen;
- Dispatcher-Hilfe, jedes Subcommand, fehlende Argumente, unbekannte Optionen und Exitcode-Durchleitung testen;
- Argumente mit Leerzeichen, Umlauten und führendem Bindestrich sicher testen;
- bestätigen, dass Linux-Anlage und direkter `pwsh`-Aufruf denselben normalisierten Dateibaum/JSON-Vertrag erzeugen;
- `bash -n` und ShellCheck für alle `.sh`-Dateien ausführen.

#### CI unter `.github/workflows/tests.yml`

Die Zielmatrix muss mindestens enthalten:

1. Windows: komplette PowerShell-Kernsuite.
2. Ubuntu: dieselbe komplette PowerShell-Kernsuite.
3. Ubuntu: Bash-Syntax, ShellCheck und Dispatcher-Regressionssuite.
4. Windows und Ubuntu: echte Browserfälle für Layout, mehrseitige Screenshots, PDF, ATS, Hashbindung und atomare Veröffentlichung.

Browserjobs dürfen nur strukturelle Invarianten prüfen, keine binär identischen PNG/PDF-Hashes zwischen Betriebssystemen. Die Jobs sollen Browsername und -version ausgeben, einen klaren Timeout besitzen und bei fehlender fest eingeplanter Dependency rot werden.

### Phase 7 – Agenteninstruktionen und Dokumentation

Erst nachdem die Linux-Tests tatsächlich grün sind, Linux nicht mehr als Alpha bezeichnen.

Zu ändern:

- `README.md`
- `Prompts/00_AGENTEN_START_HIER.md`
- `Prompts/02_VORPRUEFUNG_UND_ANFORDERUNGSMATRIX.md`
- `Prompts/10_DATEI_UND_ORDNER_REGELN.md`
- `Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md`
- `Private.example/Daten/README.md`
- `CHANGELOG.md`

Die README erhält eine zentrale Zuordnung statt verstreuter Windows-Sonderwege:

| Funktion | Windows | Linux |
| --- | --- | --- |
| Umgebung prüfen | `pwsh -File Tools/Pruefe-Umgebung.ps1` | `./Tools/bewerbung.sh diagnose` |
| Bewerbung anlegen | `pwsh -File Tools/Neue-Bewerbung.ps1 ...` | `./Tools/bewerbung.sh neu ...` |
| Stammdaten prüfen | `pwsh -File Tools/Pruefe-Stammdaten.ps1 ...` | `./Tools/bewerbung.sh stammdaten ...` |
| Inhalt prüfen | `pwsh -File Tools/Pruefe-Bewerbungsinhalt.ps1 ...` | `./Tools/bewerbung.sh inhalt ...` |
| statisch prüfen | `pwsh -File Tools/Pruefe-Bewerbung.ps1 ...` | `./Tools/bewerbung.sh pruefen ...` |
| Layout prüfen | `pwsh -File Tools/Layoutcheck-Bewerbung.ps1 ...` | `./Tools/bewerbung.sh layout ...` |
| PDF exportieren | `pwsh -File Tools/Exportiere-PDF.ps1 ...` | `./Tools/bewerbung.sh pdf ...` |
| ATS prüfen | `pwsh -File Tools/Pruefe-ATS.ps1 ...` | `./Tools/bewerbung.sh ats ...` |
| finalisieren | `pwsh -File Tools/Finalisiere-Bewerbung.ps1 ...` | `./Tools/bewerbung.sh finalisieren ...` |

Verbindliche Promptregel:

> Vor dem ersten Toolaufruf das Betriebssystem ermitteln. Unter Windows die PowerShell-7-Befehle, unter Linux ausschließlich `Tools/bewerbung.sh` verwenden. Beide Wege müssen denselben vollständigen Prüfumfang ausführen; ein fehlendes Linux-Tool ist ein Blocker und kein Grund, einen Pflichtcheck auszulassen.

Weitere Dokumentationsarbeit:

- Linux-Voraussetzungen und Distributionshinweise nennen, ohne feste `/home/...`-Pfade.
- Chrome **oder Chromium** in Linux-Beispielen verwenden.
- Troubleshooting für Browsererkennung, Ausführungsbit, Fonts, Sandbox und `pwsh` ergänzen.
- portable Befehle wie `git` und `rg` als `console` statt ausschließlich `powershell` markieren.
- Windows-/Linux-Beispiele für Vorbereitung und Veröffentlichung vollständig angeben.
- Die fiktiven Windows-Kenntnisse in `Private.example/Daten/02_...` nicht ändern; sie sind Bewerberdaten, keine Systemabhängigkeit.
- Vorlagen benötigen derzeit keine betriebssystemspezifische Änderung, abgesehen von einer gegebenenfalls bewusst angepassten Fontfamilie.

### Phase 8 – Endabnahme auf beiden Systemen

Auf Windows und Linux mit derselben fiktiven Fixture jeweils durchführen:

1. Preflight besteht und meldet den richtigen Browser.
2. neue Bewerbung anlegen.
3. alle Kandidatendateien vervollständigen.
4. Finalisierung vorbereiten.
5. alle Seitenscreenshots manuell öffnen und prüfen.
6. mit Sichtbestätigung veröffentlichen.
7. veröffentlichte Struktur erneut statisch prüfen.
8. Manifest und alle Berichte als JSON lesen.
9. prüfen, dass keine temporären Profile, Stagingordner oder Browserprozesse übrig sind.

Verglichen werden:

- Dateibaum und Dateinamen;
- Anzahl der HTML-, PDF- und PNG-Dateien;
- Seitenzahlen und DIN-A4-MediaBox;
- Pflichttexte und ATS-Abdeckung;
- JSON-Schema und relative Pfade;
- Status- und Exitcode-Verhalten;
- atomare Veröffentlichung und Schutz vor veralteten Hashnachweisen.

## 5. Verbindliche Abnahmekriterien

Die Portierung ist erst fertig, wenn alle Punkte erfüllt sind:

- [ ] Windows- und Ubuntu-Kernsuite sind grün.
- [ ] Browsergestützter Komplettlauf ist auf Windows und Ubuntu grün.
- [ ] Linux findet mindestens Chrome oder Chromium über die gemeinsame Erkennung.
- [ ] Layoutdichte ist auf Linux wirklich verfügbar und nicht nur als Warnung übersprungen.
- [ ] Timeout hinterlässt keinen Browserprozessbaum und kein gesperrtes Profil.
- [ ] Linux-Bash-Einstieg und Windows-PowerShell-Einstieg führen dieselbe Kernlogik aus.
- [ ] Neu erzeugte Aufträge enthalten keine OS-gebundenen absoluten Identitätspfade.
- [ ] Bestehende Schema-2-Aufträge können sicher in einer neuen Root-Position geöffnet werden.
- [ ] Alte technische Laufnachweise werden nach OS-/Root-Wechsel bewusst neu erzeugt.
- [ ] Pfade mit Leerzeichen und Umlauten funktionieren.
- [ ] Case-only-Kollisionen und Symlink-Ausbrüche werden sicher abgelehnt.
- [ ] `.sh`-Dateien sind ausführbar und alle ShellCheck-Prüfungen bestehen.
- [ ] README und Prompts wählen auf Linux verbindlich den Linux-Einstieg.
- [ ] Keine Anleitung setzt feste `C:\...`-, `/home/...`- oder einzelne Browserinstallationspfade voraus.
- [ ] `Private/` bleibt ignoriert; keine echten Bewerberdaten erscheinen im Diff.
- [ ] Windows-Baseline-Funktionalität ist nicht regressiert.

## 6. Sicherheits- und Änderungsregeln während der Umsetzung

- Vor jeder Phase `git status --short` prüfen und fremde Änderungen erhalten.
- `Private/` niemals in Tests kopieren, committen oder in Logs ausgeben; nur synthetische Fixtures verwenden.
- Keine bestehenden Bewerbungen oder Nachweise löschen. Migrationen nur explizit, mit Backup und Bericht.
- Kein `rm -rf` auf unaufgelöste Variablen; Test- und Tempziele vor dem Löschen kanonisch prüfen.
- Keine Browser-Sandbox still deaktivieren.
- Keine Systempakete ohne ausdrückliche Nutzerfreigabe installieren.
- Kleine, thematisch getrennte Änderungen vornehmen und nach jeder Phase die relevante Testsuite ausführen.
- Binäre Browserartefakte nicht versionieren.

## 7. Empfohlene Reihenfolge der Änderungen

1. Linux-Baseline und Runtimeentscheidung.
2. `Platform.psm1` samt Unit-/Regressionstests.
3. Pfad- und Prozessaufrufe aller `.ps1`-Tools migrieren.
4. Auftragsschema 3 plus Schema-2-Kompatibilität.
5. Bash-Dispatcher und Kompatibilitätswrapper.
6. Linux-Browsererkennung und sicherer Prozessbaum.
7. dependency-freie PNG-Dichteprüfung.
8. Linux-/Paritäts-/Browsertests.
9. CI-Matrix.
10. README, Prompts und Changelog.
11. realer End-to-End-Lauf auf Linux.
12. abschließender Gegenlauf auf Windows.

## 8. Technischer Portierungsauftrag für einen neuen Chat nach dem Linux-Wechsel

Dieser Text ist ausschließlich ein Entwicklungsauftrag für die noch offene Portierung, kein zweiter Bewerbungsworkflow und kein normaler Projekteinstieg:

```text
Lies zuerst vollständig LINUX-PORTIERUNGSPLAN.md und setze die dort beschriebene
Windows-/Linux-Parität um. Beginne mit Phase 0 und dokumentiere die unveränderte
Linux-Baseline. Bewahre alle vorhandenen Änderungen und Private-Daten. Nutze
PowerShell 7 als kanonische Kernlogik und Bash nur als Linux-Dispatcher; dupliziere
die Prüfregeln nicht. Arbeite phasenweise, teste nach jedem Arbeitspaket und höre
erst auf, wenn die Abnahmekriterien erfüllt oder ein echter externer Blocker
belegt ist. Installiere keine Systempakete und deaktiviere keine Browser-Sandbox
ohne meine ausdrückliche Freigabe.
```
