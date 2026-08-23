# apply-foundry

Lokaler, agentengestützter Workflow für deutsche Bewerbungsunterlagen. Aus
Stellenanzeige und gepflegten privaten Daten entstehen nur die gewählten
Dokumente; Versand findet nie automatisch statt.

Der produktive Kern ist **Python 3.11+ mit Standardbibliothek**. Er läuft auf
Windows, Linux und macOS, jeweils auf x64 und ARM64. Alle Plattformen verwenden
dieselben 23 Subcommands, GNU-Langoptionen, Exitcodes (`0` Erfolg, `1`
Laufzeit-/Fachfehler, `2` ungültige oder nicht unterstützte Umgebung) sowie
private Artefaktschemata.

## Schnellstart

1. Repository öffnen und die Agentenregeln in [AGENTS.md](AGENTS.md) beachten.
2. Vor Start, Reparatur oder Test ausschließlich den read-only Plan erzeugen:

   ```bash
   python3 Tools/setup.py --all --dry-run --format json
   python3 Tools/bewerbung.py diagnose --als-json
   ```

3. Fehlende deklarierte Komponenten erst nach sichtbarem Plan und bestätigter
   Berechtigung installieren:

   ```bash
   python3 Tools/setup.py --all --yes
   ```

4. Für einen Bewerbungsauftrag den Umfang A–E nach
   [Prompt 01](Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md) klären,
   dann den Workflow über `python3 Tools/bewerbung.py` starten.

Private Daten gehören ausschließlich unter `Private/`; `Private.example/` ist
nur eine Vorlage. Prüfergebnisse, Screenshots und interne Unterlagen werden nie
versendet. Erst eine aktuelle persönliche Sichtprüfung und die lokale Freigabe
erlauben die Veröffentlichung in `Versand/`.

## Plattformen und Setup

| Plattform | Paketweg | Schrift | Status |
| --- | --- | --- | --- |
| Windows x64/ARM64 | ausschließlich `winget` | Arial | technische Vorschau |
| Linux x64/ARM64 | APT, DNF/YUM, Pacman oder Zypper | Liberation Sans | technische Vorschau |
| macOS x64/ARM64 | ausschließlich Homebrew | Arial oder Liberation Sans | technische Vorschau |

Der Setupplan darf nur vier Komponenten behandeln: Python, Chromium-Browser,
Systemschrift und ShellCheck. Windows nutzt winget; macOS nutzt Homebrew mit
`python@3.13`, `google-chrome`, `shellcheck` und bei Bedarf
`font-liberation`; Linux bleibt bei den Paketnamen der jeweiligen Distribution.
PyPI, virtuelle Umgebungen, Snap, AUR, zusätzliche Paketquellen,
Editor-Erweiterungen und Agenten-Plugins sind ausgeschlossen.

Ist Python noch nicht vorhanden, sind `Tools/setup.sh` (POSIX) und
`Tools/setup.cmd` (Windows) die einzigen nativen Ausnahmen. Sie zeigen zuerst
den Runtime-Plan und dürfen Python nur mit `--runtime --yes` installieren;
anschließend delegieren sie vollständig an `Tools/setup.py`. Die übrigen
Starter sind reine Kompatibilitätsaliase:

| Einstieg | Zweck |
| --- | --- |
| `Tools/bewerbung.py` | kanonischer Dispatcher |
| `Tools/neue-bewerbung.py` | kompatibler Einstieg für `neu` |
| `Tools/setup.py` | kanonischer read-only Setupplan und opt-in Installer |
| `Tools/bewerbung.sh`, `Tools/neue-bewerbung.sh` | POSIX-Aliase |
| `Tools/setup-linux.sh`, `Tools/setup-ubuntu.sh` | POSIX-Setup-Aliase |
| `Tools/bewerbung.cmd`, `Tools/neue-bewerbung.cmd`, `Tools/setup.cmd` | Windows-Aliase und Runtime-Bootstrap |

Unbekannte Linux-Paketmanager sowie macOS ohne Homebrew werden nicht
heuristisch verändert; der Plan liefert eine genaue manuelle Voraussetzung.
Ein Pacman-Plan weist den ersten `-Syu`-Lauf als vollständige
Systemaktualisierung aus. Ubuntu-Snap, AUR und Communityquellen werden nie
umgangen.

## Bewerbungsworkflow

Die kanonische operative Anleitung ist
[Prompts/00_AGENTEN_START_HIER.md](Prompts/00_AGENTEN_START_HIER.md). Sie
ordnet neue Bewerbungen, Fortsetzungen, Stammdatenprüfungen und technische
Änderungen ein. Für eine neue Bewerbung wählt der Nutzer einen Umfang:

| Auswahl | Bestandteile |
| --- | --- |
| A | individueller Lebenslauf, Anschreiben, E-Mail |
| B | freigegebener Universal-Lebenslauf, Anschreiben, E-Mail |
| C | individueller Lebenslauf |
| D | Anschreiben |
| E | ausdrücklich gewählte Kombination |

Eine Stellenanzeige allein legt keinen Umfang fest. Der Workflow erfindet keine
Fakten, verändert Stammdaten nicht ohne Zustimmung und verarbeitet neue Angaben
zuerst nur auftragsbezogen. Der vollständige Abschluss läuft immer über:

```bash
python3 Tools/bewerbung.py finalisieren \
  --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLE"
```

Für HTML-Unterlagen erzeugt er Layout-Screenshots, A4-PDFs und eine
ATS-Textprüfung. Browser, PNGs und PDFs werden nur als geprüft gemeldet, wenn
der aktuelle Lauf sie tatsächlich erstellt und validiert hat. Firefox ist nur
eine Layoutdiagnose; Chrome, Edge oder Chromium sind für verbindliche PDF- und
ATS-Prüfungen erforderlich.

## Technik und Verträge

`diagnose --als-json` liefert Schema 4; der generische `coreRuntime` beschreibt
Python, Plattform, Mindestversion und Pfad. `setup.py --format json` liefert
Setup-Schema 3. Bestehende private Auftrags-, Matrix-, Evidenz-, Checkpoint-,
Freigabe- und Manifestdateien bleiben lesbar. Ein Runtime- oder Plattformwechsel
entwertet nur technische Nachweise; Auftrag und Kandidateninhalt bleiben erhalten.

Pfad- und Symlinkschutz arbeitet fail-closed. Unter Windows sind lokale
Pfadvergleiche case-insensitiv; portable Pfade in privaten Schemas bleiben
unverändert `/`-basiert. Browserprozesse werden mit sicheren Argumentlisten,
Timeouts und vollständiger Prozessbaum-Beendigung gestartet. Der interne
ATS-Leser verarbeitet PDF-Objekte bytebasiert und liest Flate-Streams anhand
ihrer `/Length`-Angabe.

## Tests und CI

Browserfreie Verträge:

```bash
python3 -m unittest discover -s Tests/Python -p 'test_*.py'
python3 Tools/bewerbung.py tests --suite vollstaendig
bash Tests/Bash/test-bewerbung-cli.sh
bash Tests/Bash/test-setup-linux.sh
```

Der Browser-Smoke ergänzt Chromium-Export, A4-Geometrie und ATS:

```bash
python3 Tools/bewerbung.py tests --suite browser
```

Die CI enthält Windows, Linux und macOS auf x64 und ARM64 sowie einen
separaten Python-3.11-Mindestversionsjob. Linux-Mehrdistributionstests prüfen
APT, DNF/YUM, Pacman und Zypper. Die Browserunterstützung bleibt je Zielprofil
Vorschau, bis drei dokumentierte vollständige grüne Browserläufe vorliegen.

## Projektstruktur

| Bereich | Inhalt |
| --- | --- |
| `Prompts/` | kanonischer Bewerbungsworkflow und Schrittregeln |
| `Tools/apply_foundry/` | plattformneutraler Python-Kern |
| `Tools/` | Python-Entrypoints und minimale Starter |
| `Tests/` | ausschließlich synthetische Vertrags-, Starter- und Browserprüfungen |
| `Private.example/` | sichere Strukturvorlage ohne Nutzerdaten |
| `Vorlagen/` | Dokumentvorlagen und Hinweise |

## Grenzen

Unterstützt sind ausschließlich Desktop-Windows, -Linux und -macOS; keine
mobilen Plattformen oder BSD-Systeme. Eine fehlende Browser- oder
Bildauswertungsfähigkeit wird offen gemeldet und darf nicht als bestandene
Prüfung ausgegeben werden. Das Projekt lädt nichts hoch und sendet keine
Bewerbungen an Unternehmen.

## Lizenz

MIT; siehe [LICENSE](LICENSE).
