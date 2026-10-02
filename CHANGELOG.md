# Änderungsprotokoll

## Unreleased

- Die README führt neue Nutzer direkt über einen kurzen Dialog-Quickstart zu persönlich geprüften Unterlagen. Agentenkompatibilität, synthetische Designbeispiele, Datenschutz und Versanddateien stehen im Nutzerbereich; Architektur, technische Prüfungen, Plattformdetails und die bisherige EU-AI-Act-Einordnung sind unter `docs/` vertieft. Die Console-App-Roadmap liegt jetzt unter `docs/console-app.md`; `Vorlagen/` behält seinen etablierten Namen.
- Vier ausschließlich synthetische README-Abbildungen werden aus öffentlichen Testquellen reproduzierbar erzeugt. Die Dokumentationsprüfungen beziehen die neuen Seiten, Bilder und Sprungmarken ein.
- Historische Einordnung des Plattformvertrags: Tag `v2.0` (`81c0e06`, 24. August 2026) deklarierte x64 und ARM64. Erst Commit `ee8d3dd` vom 28. August 2026 beschränkte Runtime, Setup, Manifest und CI auf x64. Die historischen Releaseangaben bleiben erhalten; aktueller Support und noch nicht bestätigte Browserstabilität werden getrennt dokumentiert.

- Finale Bewerbungs-PDFs erhalten und prüfen jetzt ausschließlich sichtbare `https://`-Portfolio-/Profillinks und `mailto:`-E-Mail-Links. Die statische HTML-Prüfung trennt diese passiven Dokumentlinks von weiterhin gesperrten Nachladepfaden; der PDF-Exportbericht bindet erwartete und tatsächlich vorhandene Linkannotationen an den PDF-Hash.
- Die Finalisierung prüft Chromium vor dem Layout mit einer lokalen A4-Druckprobe, validiert Dichteausnahmen vor jedem Browserstart und entscheidet über die Dichtesperre vor PDF-Export und ATS. Dadurch werden Sandboxfehler und blockierte Layouts ohne unnötige Folgeläufe beendet; es gibt keinen Firefox-Fallback und keinen unsicheren lokalen Sandbox-Bypass.

## 2.0 – 2026-08-24

### Python-3.11+-Major

- Der Layout-Gate für zweiseitige Lebensläufe prüft nun verpflichtend Seitenköpfe, eindeutige Abschnittskennungen und `page-footer`-Fußzeilen. Die Dichtemessung schließt Fußzeilen aus und sperrt bei mehr als 55 mm ungewöhnlicher freier Fläche die Sichtfreigabe. Eine agentenseitig begründete Ausnahme ist ausschließlich über `finalisieren --dichteausnahme-begruendung` mit hashgebundenem Nachweis möglich.

- Ein einziger Standardbibliothekskern unter `Tools/apply_foundry/` unterstützt
  laut dem historischen v2.0-Tag Windows, Linux und macOS auf x64 und ARM64.
  Die spätere Beschränkung auf x64 ist unter `Unreleased` eingeordnet;
  diese ursprüngliche Deklaration ist kein Nachweis vollständiger Browserstabilität.
- `Tools/bewerbung.py`, `Tools/neue-bewerbung.py` und `Tools/setup.py` sind die
  kanonischen Python-Einstiege. POSIX- und CMD-Dateien sind ausschließlich
  Bootstrap- oder Kompatibilitätsstarter.
- Setup-Schema 3 beschreibt den installierbaren Plan für APT, DNF/YUM, Pacman,
  Zypper, winget und Homebrew. Installierbar bleiben nur Python, Browser,
  Schrift und ShellCheck nach bestätigter Berechtigung.
- Diagnose-Schema 4 beschreibt die Python-Runtime generisch. Bestehende private
  Aufträge und Artefakte bleiben lesbar; technische Nachweise werden nach einem
  Runtimewechsel neu erzeugt.
- Browserprozesse verwenden plattformgerechte Prozessgruppen und Timeouts;
  Windows-Pfadvergleiche sind case-insensitiv.
- Der ATS-Leser verarbeitet PDF-Objekte bytebasiert und bindet komprimierte
  Streams an `/Length`, damit Binärdaten nicht an zufälligen `endstream`-Bytes
  abgeschnitten werden.
- Tests und CI verwenden Python auf Windows, Linux und macOS. Die Matrix deckt
  im historischen v2.0-Tag x64, ARM64 und die Python-3.11-Mindestversion ab; Browsernachweise bleiben
  bis zu drei dokumentierten grünen Läufen je Zielprofil Vorschau.
- Die plattformneutralen Runtime- und Linux-Sandbox-Vertragstests laufen nun
  auch auf Windows und macOS korrekt. Auf GitHub-Windows-Runnern wird der
  Setup-Dry-run nur ausgeführt, wenn der projektvertraglich vorgeschriebene
  Paketmanager `winget` tatsächlich vorhanden ist; der Paketweg bleibt durch
  die vollständige synthetische Vertragssuite abgedeckt.
- Die Pfadverträge akzeptieren die festen macOS-Systemaliase `/var`, `/tmp`
  und `/etc` nach `/private`, sperren jedoch weiterhin alle
  benutzersteuerbaren symbolischen Links. Font- und Snap-Vertragstests
  normalisieren nun die jeweiligen Windows-/macOS-Pfaddarstellungen.

### Dokumentation

- README, Agentenregeln, Prompts, Kompatibilitätsübersicht, Beispiele und
  Roadmap dokumentieren ausschließlich den Python-Kern und die aktuellen
  Setup-/Freigabeverträge.
- Die README ist wieder ein vollständiger deutschsprachiger Leitfaden für
  Nutzung und Entwicklung: Schnellstart, Dialog, Artefakte, lokale Freigabe,
  Dichtesperre, Architektur, Python-Tests und die aktuelle CI sind auf den
  gemeinsamen Python-Kern ausgerichtet.
- Veraltete Runtime- und Legacy-Verweise wurden vollständig entfernt.
