# Bewerbungs-Agent als installierbare Console App

## 1. Zweck und Status dieses Dokuments

Dieses Dokument ist die verbindliche, entscheidungsfertige Implementierungsspezifikation für eine installierbare Terminal-Anwendung des bestehenden Bewerbungs-Agenten. Es richtet sich an ein nachfolgendes Codex-Modell und soll die Implementierung ohne weitere grundlegende Produkt- oder Architekturentscheidungen ermöglichen.

Die geplante Anwendung heißt zunächst **Bewerbungs-Agent**. Sie stellt den bestehenden lokalen Bewerbungsworkflow über eine einfach installierbare Console App bereit. Der Workflow selbst wird nicht neu erfunden, sondern über die vorhandenen Prompts, PowerShell-Werkzeuge, Tests, Checkpoints und Freigaberegeln gesteuert.

Vor Beginn der Implementierung muss das ausführende Modell:

1. `AGENTS.md` vollständig lesen und beachten.
2. Den aktuellen Git-Status prüfen und vorhandene Änderungen des Benutzers schützen.
3. Bei Änderungen an Workflow-Verträgen `Prompts/00_AGENTEN_START_HIER.md` und nur die jeweils relevanten Promptmodule laden.
4. Keine echten privaten Bewerberdaten in Tests, Logs oder öffentliche Projektbereiche übernehmen.
5. Nach funktionalen Änderungen `CHANGELOG.md` aktualisieren und die passenden Tests ausführen.

## 2. Produktziel

Der Anwender soll:

1. die Anwendung unter Windows installieren oder als portable ZIP entpacken,
2. sie über das Startmenü oder `bewerbungs-agent.exe` öffnen,
3. sich einmal mit seinem bestehenden Codex-/OpenAI-Konto anmelden,
4. Bewerbungsaufträge in natürlicher Sprache eingeben,
5. den vollständigen vorhandenen Bewerbungsworkflow benutzen können,
6. weder Visual Studio Code noch eine separate Codex-, Node.js- oder PowerShell-Installation benötigen.

### Festgelegte Prioritäten

1. Windows-MVP für eine kleine geschlossene Testgruppe.
2. Möglichst wenige Änderungen an der bestehenden Workflow-Logik.
3. Vollständig lokale Speicherung der Bewerbungsdaten.
4. Nutzung des vorhandenen Codex-Logins statt separater API-Schlüssel.
5. Terminaloberfläche statt Desktop-GUI.
6. Linux-Unterstützung nach Stabilisierung der Windows-Version.

### Nicht Bestandteil des MVP

- grafische Desktopoberfläche oder Electron
- integrierter Dokumenteditor
- automatische Bewerbungssendung
- Cloudspeicherung oder Synchronisierung
- Teamkonten
- automatische Telemetrie
- API-Schlüsselmodus
- lokale Modelllaufzeit
- frei auswählbare Modelle
- automatische Online-Aktualisierung
- macOS-Paket
- öffentliche Plugin-Schnittstelle

Diese Punkte dürfen das Windows-MVP nicht verzögern.

## 3. Verbindliche Architekturentscheidung

### 3.1 Technischer Aufbau

Die Anwendung wird als TypeScript-/Node.js-Console-App in einem neuen Verzeichnis entwickelt:

```text
ConsoleApp/
```

Sie verwendet den offiziellen Codex TypeScript SDK als eingebettete Agentenlaufzeit. Der SDK unterstützt das Starten und Fortsetzen von Threads. Die zur Implementierungszeit geprüfte SDK-Version wird im Lockfile und in `package.json` exakt festgelegt; es wird keine ungebundene `latest`-Abhängigkeit verwendet. Referenz: [offizielle Codex-SDK-Dokumentation](https://developers.openai.com/codex/codex-sdk).

Die logische Architektur lautet:

```text
Terminalbenutzer
    ↓
Console UI und Befehlsparser
    ↓
Sitzungs- und Workflowsteuerung
    ↓
Codex-SDK-Adapter
    ↓
AGENTS.md und vorhandene Promptmodule
    ↓
Tools/bewerbung.ps1
    ↓
Private/Daten und Private/Bewerbungen
```

### 3.2 Bestehende Workflow-Engine bleibt maßgeblich

Die Console App darf folgende Logik nicht duplizieren:

- Bewerbungsarten und Dokumentauswahl
- Stammdatenprüfung
- Kandidaten- und Arbeitsordnerverwaltung
- Qualitätsprüfung
- Layoutprüfung
- PDF-Erstellung
- ATS-Prüfung
- Freigabeprozess
- Versandordner-Regeln
- Workflow-Checkpoint
- Tokenbericht
- Datenschutz-, Wahrheits- und Sichtprüfungsregeln

Diese Funktionen bleiben in `AGENTS.md`, `Prompts/`, `Tools/` und den vorhandenen Tests definiert. Die Console App ist die benutzerfreundliche Hülle und Orchestrierungsschicht.

### 3.3 Umgang mit `Dev_App_Electron`

Der historische Branch `Dev_App_Electron` wird nicht vollständig in den Hauptbranch gemergt. Er ist ausschließlich eine Referenzquelle für bereits erprobte, frameworkunabhängige Komponenten.

Gezielt zu prüfen und gegebenenfalls zu portieren sind:

- Codex-SDK-Adapter
- Authentifizierungsprüfung
- Codex-Fehlerklassifizierung
- Ereignisabbildung
- sichere Umgebungsvariablen
- Runtime-Pfadermittlung
- Runtime-Integritätsprüfung
- Windows-Prozessüberwachung mit Job Object
- Tests für Abbruch und Prozessbaum-Bereinigung

Electron-, React- und GUI-Abhängigkeiten dürfen nicht übernommen werden.

## 4. Zielstruktur

```text
ConsoleApp/
├── package.json
├── package-lock.json
├── tsconfig.json
├── README.md
├── src/
│   ├── main.ts
│   ├── cli/
│   │   ├── console-app.ts
│   │   ├── command-parser.ts
│   │   ├── command-registry.ts
│   │   ├── readline-controller.ts
│   │   ├── renderer.ts
│   │   └── terminal-capabilities.ts
│   ├── application/
│   │   ├── application-controller.ts
│   │   ├── session-controller.ts
│   │   ├── workflow-controller.ts
│   │   ├── startup-controller.ts
│   │   └── shutdown-controller.ts
│   ├── codex/
│   │   ├── codex-client.ts
│   │   ├── codex-sdk-adapter.ts
│   │   ├── auth-controller.ts
│   │   ├── auth-probe.ts
│   │   ├── event-mapper.ts
│   │   ├── error-classifier.ts
│   │   ├── safe-environment.ts
│   │   └── thread-store.ts
│   ├── runtime/
│   │   ├── runtime-bootstrap.ts
│   │   ├── runtime-manifest.ts
│   │   ├── runtime-paths.ts
│   │   ├── dependency-check.ts
│   │   ├── process-supervisor.ts
│   │   └── platform.ts
│   ├── workspace/
│   │   ├── workspace-manager.ts
│   │   ├── workspace-seeder.ts
│   │   ├── workspace-upgrader.ts
│   │   ├── workspace-manifest.ts
│   │   └── private-data-guard.ts
│   ├── workflow/
│   │   ├── command-builder.ts
│   │   ├── checkpoint-reader.ts
│   │   ├── status-reconstructor.ts
│   │   └── workflow-contracts.ts
│   ├── diagnostics/
│   │   ├── diagnostics-runner.ts
│   │   ├── log-writer.ts
│   │   └── redaction.ts
│   └── shared/
│       ├── errors.ts
│       ├── exit-codes.ts
│       └── result.ts
├── native/
│   └── windows-process-supervisor/
├── scripts/
│   ├── prepare-runtime.ps1
│   ├── create-portable-package.ps1
│   ├── create-installer.ps1
│   └── verify-package.ps1
├── installer/
│   └── BewerbungsAgent.iss
└── tests/
    ├── unit/
    ├── integration/
    ├── package/
    └── fixtures/
```

Die Struktur darf nur aus einem konkreten technischen Grund geändert werden. Abweichungen müssen in der Console-App-Dokumentation und bei funktionaler Relevanz in `CHANGELOG.md` begründet werden.

## 5. Öffentliche Bedienoberfläche

### 5.1 Programmstart

Der primäre Einstieg lautet:

```powershell
bewerbungs-agent.exe
```

Unterstützte Startargumente:

```powershell
bewerbungs-agent.exe --workspace "C:\Pfad\Zum\Arbeitsordner"
bewerbungs-agent.exe --diagnose
bewerbungs-agent.exe --version
bewerbungs-agent.exe --help
```

Ohne Argumente startet die interaktive Terminaloberfläche.

### 5.2 Interaktive Befehle

| Befehl | Verhalten |
|---|---|
| `/neu` | Beginnt einen neuen Bewerbungsauftrag über den kanonischen Workflow. |
| `/fortsetzen` | Rekonstruiert und setzt einen bestehenden Auftrag fort. |
| `/status` | Zeigt den belegbaren Workflowstatus aus Originalartefakten und Checkpoint. |
| `/daten` | Startet beziehungsweise erklärt die Stammdatenprüfung. |
| `/diagnose` | Prüft Runtime, PowerShell, Browser, Schriften, Workspace und Schreibrechte. |
| `/login` | Startet den Codex-Anmeldevorgang oder zeigt den vorhandenen Loginstatus. |
| `/logout` | Meldet das anwendungseigene Codex-Profil ab. |
| `/abbruch` | Bricht den aktuell laufenden Agentenschritt und dessen Kindprozesse kontrolliert ab. |
| `/hilfe` | Zeigt Befehle, Datenschutzinformationen und typische Abläufe. |
| `/beenden` | Beendet die Anwendung kontrolliert. |

Nicht mit `/` beginnende Eingaben werden als natürliche Benutzeranweisung an die aktuelle Codex-Sitzung übergeben.

Unbekannte Slash-Befehle werden nicht an das Modell weitergeleitet. Stattdessen erscheint eine lokale Fehlermeldung mit passenden Befehlsvorschlägen.

### 5.3 Terminaldarstellung

Die Ausgabe unterscheidet sichtbar:

- Benutzereingabe
- Agentenantwort
- laufenden Arbeitsschritt
- Werkzeugausführung
- Warnung
- Fehler
- erforderliche persönliche Prüfung
- erfolgreich abgeschlossenen Schritt

ANSI-Farben werden nur verwendet, wenn das Terminal sie unterstützt. Bei Ausgabeumleitung oder deaktivierten Farben bleibt die Darstellung vollständig lesbar.

Die Terminalausgabe und technische Logs dürfen keine vollständigen Prompts, Zugangsdaten, Authentifizierungstoken oder unnötigen privaten Inhalte enthalten.

## 6. Start- und Einrichtungsablauf

Beim ersten Start führt die Anwendung diese Schritte in der angegebenen Reihenfolge aus:

1. Plattform und Prozessorarchitektur erkennen.
2. Anwendungsverzeichnisse anlegen.
3. Runtime-Manifest und SHA-256-Prüfsummen kontrollieren.
4. Verwalteten Arbeitsbereich anlegen oder prüfen.
5. Vorhandene private Daten erkennen, aber niemals überschreiben.
6. Codex-Anmeldestatus prüfen.
7. Bei fehlender Anmeldung den Login anbieten.
8. `Tools/bewerbung.ps1 diagnose` ausführen.
9. Diagnoseergebnis verständlich darstellen.
10. Erst bei ausreichenden Voraussetzungen die normale Eingabeaufforderung öffnen.

Ein Fehler in einem optionalen Bestandteil wie Bash darf den Windows-Betrieb nicht verhindern. Fehlende Pflichtbestandteile wie eine beschädigte Agenten-Runtime, unzureichende PowerShell-Version oder fehlende Schreibrechte blockieren den Workflow und führen zu einer konkreten Reparaturempfehlung.

## 7. Windows-Installation und lokale Verzeichnisse

### 7.1 Installationsort

Die normale benutzerbezogene Installation verwendet:

```text
%LOCALAPPDATA%\Programs\BewerbungsAgent\
```

Administratorrechte sind nicht erforderlich.

### 7.2 Anwendungsdaten

Konfiguration, Logs, Runtime-Zustand und das isolierte Codex-Profil liegen unter:

```text
%LOCALAPPDATA%\BewerbungsAgent\
├── config/
├── codex-home/
├── logs/
├── runtime/
└── updates/
```

`CODEX_HOME` wird für die Anwendung ausschließlich auf den anwendungseigenen Ordner `codex-home` gesetzt. Eine vorhandene globale Codex-Konfiguration des Benutzers wird weder gelesen noch verändert, soweit dies technisch durch die Codex-Runtime gewährleistet werden kann.

### 7.3 Arbeitsbereich

Der Standardarbeitsbereich liegt unter:

```text
%USERPROFILE%\Documents\Bewerbungs-Agent\
```

Darin befindet sich eine verwaltete Kopie der Workflowdateien:

```text
AGENTS.md
Prompts/
Tools/
Vorlagen/
Private.example/
Private/
README.md
CHANGELOG.md
```

`Private/` wird niemals automatisch überschrieben, zurückgesetzt, gelöscht oder durch eine Aktualisierung ersetzt.

Über `--workspace` darf der Benutzer einen anderen Arbeitsbereich auswählen. Der Pfad wird normalisiert, auf Schreibbarkeit und Eignung geprüft und anschließend in der lokalen Konfiguration gespeichert.

### 7.4 Portable Variante

Zusätzlich zum Installer wird eine portable ZIP-Datei erzeugt. Sie enthält Anwendung, Node-Runtime, Codex-Runtime, `rg`, PowerShell und öffentliche Workflowdateien.

Private Daten gehören niemals in das portable Distributionsarchiv. Persönliche Zustände werden auch bei der portablen Variante standardmäßig unter `%LOCALAPPDATA%\BewerbungsAgent` und im ausgewählten Dokumente-Arbeitsbereich gespeichert.

## 8. Mitgelieferte Laufzeiten und Abhängigkeiten

Das Windows-Paket enthält:

- kompilierte Console App
- passende Node.js-LTS-Runtime
- fest gepinnte Codex-Runtime
- `rg`
- portable PowerShell-Version ab 7.6
- benötigte native Windows-Prozessüberwachung
- öffentliche Workflowdateien des Projekts

Chrome wird nicht mitgeliefert. Für Rendering und PDF-Prüfung verwendet die Anwendung einen kompatiblen, bereits installierten Browser in dieser Reihenfolge:

1. Microsoft Edge
2. Google Chrome
3. kompatibles Chromium

Die vorhandene Browsererkennung in den PowerShell-Werkzeugen bleibt die fachliche Quelle. Die Console App zeigt lediglich das Diagnoseergebnis an.

Jede ausgelieferte Binärdatei wird im Runtime-Manifest mit relativer Position, Version, Plattform, Architektur, Größe und SHA-256-Prüfsumme registriert. Der Start wird bei beschädigten Pflichtdateien abgebrochen.

## 9. Codex-Anmeldung und Modell

### 9.1 Anmeldung

Die Anwendung prüft den Status über die mitgelieferte Codex-Runtime. Ist der Benutzer nicht angemeldet, wird ein interaktiver Login gestartet.

Anmeldeinformationen werden nicht von der Console App gelesen, kopiert oder selbst gespeichert. Die Verwaltung übernimmt ausschließlich die Codex-Runtime innerhalb des isolierten `CODEX_HOME`.

Das MVP erhält:

- kein Eingabefeld für API-Schlüssel
- keine selbst entwickelte OAuth-Implementierung
- keinen Cloud-Backend-Dienst
- keine gemeinsame Benutzerverwaltung

### 9.2 Modellwahl

Es wird kein möglicherweise veralteter Modellname im Quellcode fest verdrahtet. Standardmäßig verwendet die Anwendung das vom SDK beziehungsweise Konto bereitgestellte geeignete Codex-Modell.

Eine spätere konfigurierbare Modellauswahl darf erst ergänzt werden, wenn die offizielle SDK-Schnittstelle und die zulässigen Modellnamen zur Implementierungszeit erneut geprüft wurden.

## 10. Codex-Sitzung und Kontextverwaltung

### 10.1 Laufende Sitzung

Beim normalen Start wird eine Codex-Sitzung für den ausgewählten Arbeitsbereich erzeugt. Innerhalb eines laufenden Programmstarts werden aufeinanderfolgende natürliche Eingaben in demselben Thread verarbeitet.

`/neu` beendet den logischen Bezug zum vorherigen Auftrag und erzeugt einen neuen Thread. Vorhandene Projektartefakte werden dadurch nicht gelöscht.

### 10.2 Fortsetzung nach Neustart

Die Anwendung darf sich nicht ausschließlich auf einen gespeicherten Chatverlauf verlassen.

Bei `/fortsetzen` rekonstruiert sie den belegbaren Stand aus:

- `Bewerbungsauftrag.json`
- `Workflow-Checkpoint.json`
- Kandidatendateien
- Prüfberichten
- Sichtprüfungsstatus
- Versandordner
- weiteren Originalartefakten des kanonischen Workflows

Ein SDK-Thread darf zusätzlich fortgesetzt werden, wenn eine gültige Thread-ID vorhanden ist. Der fachliche Workflowstatus stammt trotzdem aus den Projektdateien und niemals allein aus dem Modellgedächtnis.

### 10.3 JSON-Zustand nach Arbeitsschritten

Die vorhandene Checkpoint-Architektur wird weiterverwendet. Die Console App führt keine zweite, konkurrierende Zustandsdatei ein.

Nach sinnvollen Workflowgrenzen verwendet der Agent den bestehenden Einstieg:

```powershell
Tools/bewerbung.ps1 checkpoint
```

`Workflow-Checkpoint.json` enthält nur:

- Workflow-Schritt
- Status
- relevante relative Pfade
- Dateigrößen
- SHA-256-Werte
- technische Zeitangaben

Nicht gespeichert werden:

- vollständige Chatverläufe
- Kopien privater Quelldokumente
- geheime Zugangsdaten
- vollständige Modellprompts
- unnötige Kopien sämtlicher Ergebnisse früherer Zyklen

Dadurch wird Kontext effizient wiederverwendet, ohne bei jedem Arbeitsschritt eine immer größere JSON-Datei vollständig neu an das Modell zu übertragen.

## 11. Agentenstart und Workflowsteuerung

Für jeden neuen Codex-Thread wird ein kurzer technischer Startauftrag erzeugt. Dieser enthält keine Kopie sämtlicher Promptmodule, sondern weist den Agenten an:

1. `AGENTS.md` zu beachten.
2. Bei Bewerbungsaufträgen `Prompts/00_AGENTEN_START_HIER.md` zu laden.
3. Danach nur das für den aktuellen Schritt benötigte Promptmodul zu lesen.
4. Vorhandene Checkpoints und Prüfdateien weiterzuverwenden.
5. Private Daten nur unter `Private/` zu verarbeiten.
6. Keine Dateien zu versenden oder hochzuladen.
7. Die persönliche Freigabegrenze einzuhalten.

Der Agent arbeitet mit dem ausgewählten Workspace als Arbeitsverzeichnis.

### Festgelegte SDK-Sicherheitskonfiguration

Für das MVP gilt:

- Sandbox: `workspace-write`
- Schreibzugriff nur im verwalteten Workspace und in notwendigen temporären Verzeichnissen
- keine allgemeine Dateisystemfreigabe
- Websuche für den eingebetteten Agenten deaktiviert
- Werkzeug-Netzwerkzugriff deaktiviert
- keine automatische Bestätigung von Veröffentlichungen oder Versandvorgängen
- Prozessausführung über kontrollierte Runtime-Pfade
- Bereinigungslogik bei Abbruch und Programmende

Die Verbindung der Codex-Runtime zum Modell bleibt technisch erforderlich. Sie ist nicht mit einem allgemeinen Werkzeug-Netzwerkzugriff gleichzusetzen.

## 12. Prozessverwaltung und Abbruch

Unter Windows wird der Codex-Prozess zusammen mit allen von ihm gestarteten Kindprozessen einem Windows Job Object zugeordnet.

`/abbruch`, `Ctrl+C`, ein schwerer Laufzeitfehler und das normale Programmende müssen:

1. den aktuellen SDK-Lauf abbrechen,
2. verbleibende Kindprozesse beenden,
3. offene Logdateien schließen,
4. den letzten belastbaren Checkpoint unverändert erhalten,
5. keine halbfertigen Dateien fälschlich als freigegeben markieren,
6. zur Eingabeaufforderung zurückkehren oder kontrolliert beenden.

Ein einzelnes `Ctrl+C` bricht zunächst nur den laufenden Agentenschritt ab. Ein weiteres `Ctrl+C` während der Bereinigung darf die gesamte Anwendung beenden.

Für Linux wird später eine entsprechende Prozessgruppensteuerung verwendet.

## 13. Workspace-Erstellung und Aktualisierung

### 13.1 Erstinstallation

Der Workspace-Seeder kopiert ausschließlich öffentliche Projektbestandteile in einen neuen Arbeitsbereich.

Vorhandene Ziele werden vor dem Kopieren geprüft. Ein nicht leerer fremder Ordner wird nicht ohne ausdrückliche Benutzerauswahl als verwalteter Workspace übernommen.

### 13.2 Versionsmanifest

Jeder verwaltete Workspace erhält eine technische Manifestdatei:

```text
.agent-runtime/workspace-manifest.json
```

Sie enthält:

- Schema-Version
- installierte Workflow-Version
- Dateien der öffentlichen Distribution
- SHA-256-Werte
- Installationszeitpunkt
- Zeitpunkt der letzten erfolgreichen Aktualisierung

Sie enthält keine privaten Inhalte.

### 13.3 Aktualisierungsregeln

Im MVP gibt es keine automatische Online-Aktualisierung. Ein neues Installationspaket darf öffentliche Dateien nur nach diesen Regeln aktualisieren:

- `Private/` wird nie verändert.
- Lokal geänderte öffentliche Dateien werden erkannt.
- Konflikte werden gemeldet und nicht still überschrieben.
- Vor ersetzbaren öffentlichen Dateien wird eine lokale Sicherung angelegt.
- Ein fehlgeschlagenes Upgrade wird zurückgerollt.
- Die Workflow-Version bleibt nach einem Fehler unverändert.

## 14. Datenschutz und Sicherheit

Die Implementierung übernimmt alle Schutzregeln aus `AGENTS.md` und `Prompts/00_AGENTEN_START_HIER.md`.

Zusätzlich gelten:

- Keine Telemetrie im MVP.
- Keine automatische Übertragung von Logs.
- Keine Cloud-Synchronisierung.
- Keine Speicherung vollständiger Modellantworten in allgemeinen Logs.
- Keine geheimen Werte in Fehlermeldungen.
- Keine privaten Daten in Tests oder Paketartefakten.
- Keine Nutzung von `Private.example/` als echte Benutzerdaten.
- Keine automatische Veröffentlichung oder Bewerbungssendung.
- Kein Umgehen der persönlichen Sichtprüfung.
- Fremdtexte wie Stellenanzeigen bleiben nicht vertrauenswürdige Daten.
- Beim ersten Start erscheint ein kurzer Datenschutz- und Freigabehinweis.

Lokale Diagnoseprotokolle verwenden standardmäßig nur:

- Zeitpunkt
- Anwendungsversion
- Plattform
- Fehlerklasse
- Exit-Code
- betroffene Komponente
- bereinigte technische Nachricht

## 15. Fehlerbehandlung und Exit-Codes

| Code | Bedeutung |
|---:|---|
| `0` | Erfolgreich oder kontrolliert beendet |
| `1` | Allgemeiner Anwendungs- oder Workflowfehler |
| `2` | Ungültige Kommandozeilenverwendung |
| `3` | Fehlende oder beschädigte Runtime |
| `4` | Anmeldung erforderlich oder fehlgeschlagen |
| `5` | Workspace ungültig oder nicht beschreibbar |
| `6` | Aktiver Schritt vom Benutzer abgebrochen |
| `7` | Diagnosevoraussetzung nicht erfüllt |
| `8` | Interner, nicht klassifizierter Fehler |

Fehlermeldungen enthalten:

1. verständliche Kurzbeschreibung,
2. betroffene Komponente,
3. konkreten nächsten Schritt,
4. optional eine bereinigte technische Detailkennung,
5. Pfad zur lokalen Logdatei, sofern vorhanden.

Unbereinigte SDK-Ausnahmen werden nicht direkt an den Benutzer ausgegeben.

## 16. Windows-Paketierung

### 16.1 Installer

Als Installer wird Inno Setup verwendet. Er erstellt eine benutzerbezogene Installation mit:

- Programminstallation unter `%LOCALAPPDATA%\Programs`
- Startmenüeintrag
- optionaler Desktopverknüpfung
- Deinstallationsroutine
- Versionsanzeige
- Lizenz- und Datenschutzhinweis
- optionaler Aufnahme in den Benutzer-PATH

Die PATH-Anpassung ist standardmäßig deaktiviert und nur eine auswählbare Installationsoption.

### 16.2 Portable Paketierung

Das portable ZIP erhält dieselben Runtime- und Integritätsprüfungen wie die installierte Variante.

### 16.3 Signierung

Für die kleine geschlossene Testgruppe darf die erste Beta unsigniert sein. Die Dokumentation weist deutlich auf eine mögliche Windows-SmartScreen-Warnung hin.

Eine öffentliche Freigabe setzt Code-Signierung für Installer und Hauptprogramm voraus.

### 16.4 Paketprüfung

Jeder Release-Build wird in einem frischen Windows-Benutzerprofil geprüft, in dem Folgendes nicht vorausgesetzt wird:

- globales Node.js
- globales Codex
- Visual Studio Code
- Projekt-Checkout
- Administratorrechte

Ein installierter Edge oder Chrome bleibt für Browser- und PDF-Prüfungen eine Voraussetzung.

## 17. Linux-Plan

Linux wird nicht parallel zum ersten Windows-MVP fertiggestellt. Die Architektur wird von Beginn an plattformneutral gehalten.

Nach dem Windows-Test folgen:

1. Unterstützung für Ubuntu 24.04 x64.
2. `.deb`-Paket.
3. Optionales portables `tar.gz`.
4. Prozessgruppensteuerung statt Windows Job Object.
5. Nutzung der vorhandenen `Tools/bewerbung.sh`.
6. Integration von `Tools/setup-ubuntu.sh` als dokumentierte, ausdrücklich bestätigte Einrichtungshilfe.
7. Wiederholte echte Browser- und PDF-Prüfung.

Linux bleibt gemäß dem vorhandenen Projektvertrag im Alpha-/Beta-Status, bis drei aufeinanderfolgende vollständige Browser-Evidenzläufe erfolgreich dokumentiert wurden.

## 18. Teststrategie

### 18.1 Unit-Tests

Mindestens folgende Komponenten erhalten isolierte Tests:

- Slash-Befehlsparser
- Startargumente
- Exit-Code-Zuordnung
- Fehlerklassifizierung
- Log-Bereinigung
- sichere Umgebungsvariablen
- Runtime-Pfadermittlung
- Manifest- und Hashprüfung
- Workspace-Pfadnormalisierung
- Schutz von `Private/`
- Checkpoint-Lesen
- Statusrekonstruktion
- ANSI-Erkennung
- Thread-Metadaten
- Abbruchzustände

### 18.2 Integrationstests

Abzudecken sind:

- Start mit gültiger Runtime
- Start mit beschädigter Runtime
- Start ohne Login
- erkannter Loginstatus
- neuer Codex-Thread
- mehrere Eingaben in einem Thread
- `/neu` erzeugt einen neuen Thread
- `/fortsetzen` mit vorhandenem Checkpoint
- `/fortsetzen` mit veraltetem Checkpoint
- `/status` ohne Bewerbung
- `/diagnose` auf Windows
- PowerShell-Aufruf mit Leerzeichen im Pfad
- Abbruch eines laufenden Schritts
- Kindprozessbereinigung
- Workspace-Upgrade ohne private Änderungen
- Upgrade-Konflikt bei lokal geänderter öffentlicher Datei

### 18.3 Bestehende Regressionstests

Die vollständige vorhandene PowerShell-Test-Suite bleibt ein Release-Gate. Die Console App darf keinen bestehenden Workflowtest brechen.

Die vorhandenen Tests für Workflow-Checkpoint, Datenschutz, Finalisierung, Browserprüfung und Dateiverträge bleiben maßgeblich.

### 18.4 Paket-Smoke-Tests

Das tatsächlich gebaute Installations- beziehungsweise portable Paket muss geprüft werden. Ein Lauf direkt aus dem TypeScript-Quellverzeichnis reicht nicht aus.

Pflichtszenarien:

1. Anwendung installieren.
2. Anwendung aus dem Startmenü öffnen.
3. Diagnose ausführen.
4. Login starten beziehungsweise vorhandenen Login erkennen.
5. Natürlichen Testauftrag ohne private Echtdaten ausführen.
6. PowerShell-Werkzeug starten.
7. Laufenden Prozess abbrechen.
8. Anwendung neu starten.
9. Status aus Checkpoint rekonstruieren.
10. Anwendung deinstallieren.
11. Kontrollieren, dass private Workspace-Daten erhalten bleiben.

### 18.5 Datenschutztests

Automatisierte Tests prüfen, dass:

- keine Testfixture reale private Daten enthält,
- Logs bekannte Geheimnismuster redigieren,
- Paketarchive kein `Private/` enthalten,
- Workspace-Upgrades `Private/` nicht verändern,
- vollständige natürliche Eingaben nicht im Diagnoseprotokoll landen,
- `Tokenverbrauch.json` nicht in Versandartefakte aufgenommen wird.

## 19. Implementierungsphasen und Gates

### Phase 0 – Ausgangszustand sichern

- Aktuellen Hauptbranch und nicht eingecheckte Änderungen prüfen.
- Bestehenden PowerShell-Teststand dokumentieren.
- `Dev_App_Electron` nur als Referenz analysieren.
- Keine privaten Dateien lesen oder kopieren.
- Öffentliche Runtime-Komponenten identifizieren.

**Gate:** Die bestehenden Tests laufen vor Beginn weiterhin vollständig erfolgreich.

### Phase 1 – Console-App-Grundgerüst

- `ConsoleApp/` anlegen.
- TypeScript-, Build- und Testkonfiguration erstellen.
- Startargumente und interaktive Readline-Schleife implementieren.
- Befehlsparser und lokale Hilfe ergänzen.
- Stabile Exit-Codes einführen.

**Gate:** Die Console App startet und verarbeitet alle lokalen Slash-Befehle zunächst als kontrollierte Stubs.

### Phase 2 – Runtime und Workspace

- Plattformabhängige Pfade implementieren.
- Manifest- und Hashprüfung ergänzen.
- Workspace-Seeding implementieren.
- `Private/`-Schutz implementieren.
- Bestehende Diagnose anbinden.

**Gate:** Ein frischer Workspace wird korrekt angelegt; ein vorhandenes `Private/` bleibt bytegenau unverändert.

### Phase 3 – Codex-Integration

- Fest gepinnte SDK-Version aufnehmen.
- Sicheren SDK-Adapter implementieren.
- Loginstatus und Login/Logout ergänzen.
- Ereignisausgabe im Terminal implementieren.
- Threadstart und Threadfortsetzung ergänzen.

**Gate:** Ein authentifizierter SDK-Lauf kann im verwalteten Workspace eine harmlose Testdatei erzeugen und danach kontrolliert beendet werden.

### Phase 4 – Workflow-Anbindung

- Startinstruktion an `AGENTS.md` und den kanonischen Workflow anbinden.
- `/neu`, `/fortsetzen`, `/status` und `/daten` vollständig implementieren.
- Checkpoint-Verhalten prüfen.
- Persönliche Freigabegrenzen in der Terminaldarstellung sichtbar machen.

**Gate:** Ein synthetischer Bewerbungsworkflow ohne Echtdaten kann bis `bereit_zur_sichtpruefung` durchlaufen und stoppt dort korrekt.

### Phase 5 – Prozesssicherheit

- Windows-Prozesssupervisor übernehmen und anpassen.
- `/abbruch` und `Ctrl+C` implementieren.
- Absturz- und Cleanup-Tests ergänzen.
- Log-Redaktion abschließen.

**Gate:** Nach jedem Abbruch existieren keine verwaisten Codex-, PowerShell-, Browser- oder Hilfsprozesse.

### Phase 6 – Windows-Paketierung

- Node-, Codex-, `rg`- und PowerShell-Runtime paketieren.
- Runtime-Manifest erzeugen.
- Portable ZIP erstellen.
- Inno-Setup-Installer erzeugen.
- Paket-Smoke-Tests ausführen.

**Gate:** Die App funktioniert auf einem sauberen Windows-Testsystem ohne globale Entwicklungswerkzeuge.

### Phase 7 – Geschlossene Beta

- Wenige Testnutzer einsetzen.
- Lokale, freiwillig bereitgestellte Fehlerberichte auswerten.
- Fehler nach Schwere klassifizieren.
- Datenschutz- und Freigabeprobleme vor Komfortfunktionen priorisieren.

**Gate:** Keine offenen kritischen Fehler bei Datenverlust, privaten Daten, Login, Prozessbereinigung oder Freigabestatus.

### Phase 8 – Linux

- Plattformadapter fertigstellen.
- `.deb` und `tar.gz` bauen.
- Ubuntu-Browserprüfungen ausführen.
- Drei aufeinanderfolgende vollständige Evidenzläufe dokumentieren.

## 20. Abnahmekriterien für das Windows-MVP

Das MVP gilt als fertig, wenn alle folgenden Aussagen nachweislich wahr sind:

- Installation ohne Administratorrechte funktioniert.
- Visual Studio Code ist nicht erforderlich.
- Eine separate Codex-Installation ist nicht erforderlich.
- Eine separate Node.js-Installation ist nicht erforderlich.
- Der Benutzer kann sich mit Codex anmelden.
- Die Anwendung startet im Terminal.
- Alle definierten Slash-Befehle funktionieren.
- Natürliche Spracheingaben werden im aktiven Thread verarbeitet.
- Der bestehende PowerShell-Workflow wird verwendet und nicht dupliziert.
- Checkpoints ermöglichen die Fortsetzung nach einem Neustart.
- Private Daten bleiben ausschließlich unter `Private/`.
- Vorhandene private Dateien werden bei Installation und Upgrade nicht überschrieben.
- Die Anwendung versendet und veröffentlicht nichts.
- Die persönliche Sichtprüfung bleibt ein zwingendes Gate.
- Ein laufender Schritt kann ohne verwaiste Prozesse abgebrochen werden.
- Installer und portable ZIP bestehen die Paket-Smoke-Tests.
- Alle vorhandenen Workflowtests und neuen Console-App-Tests sind erfolgreich.
- `CHANGELOG.md` und die technische Dokumentation sind aktualisiert.

## 21. Verbindliche Arbeitsanweisung für die spätere Implementierung

Das implementierende Codex-Modell arbeitet in dieser Reihenfolge:

1. `AGENTS.md` lesen.
2. Diese Datei vollständig lesen.
3. Aktuellen Git-Status prüfen.
4. Bestehende Änderungen des Benutzers schützen.
5. Relevante vorhandene Dateien gezielt untersuchen.
6. Den historischen Electron-Branch nur dateiweise als Referenz verwenden.
7. Vor jeder Phase die betroffenen Tests bestimmen.
8. Änderungen mit kleinen, nachvollziehbaren Patches durchführen.
9. Keine echten privaten Daten für Tests verwenden.
10. Nach funktionalen Änderungen `CHANGELOG.md` aktualisieren.
11. Nach jeder Phase die vorgesehenen Gates ausführen.
12. Keine Phase als abgeschlossen kennzeichnen, wenn ihr Gate nicht nachweislich bestanden ist.
13. Nicht ausführbare Plattformprüfungen und ihre Gründe ausdrücklich dokumentieren.
14. Keine geschätzten Tokenzahlen als gemessene Werte ausgeben.

## 22. Dokumentationspflege

Diese Datei bleibt die Architektur- und Implementierungsquelle für die Console App. Der spätere Umsetzungsfortschritt wird in einer separaten Fortschrittsdatei dokumentiert, damit ursprüngliche Entscheidungen und tatsächlicher Stand klar voneinander getrennt bleiben.

Wenn sich eine grundlegende Entscheidung ändert, muss diese Datei zusammen mit Begründung, Auswirkungen, Migration und angepassten Tests aktualisiert werden.
