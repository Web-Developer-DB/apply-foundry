# Änderungsprotokoll

## 2.0 – 2026-08-24

### Python-3.11+-Major

- Der Layout-Gate für zweiseitige Lebensläufe prüft nun verpflichtend Seitenköpfe, eindeutige Abschnittskennungen und `page-footer`-Fußzeilen. Die Dichtemessung schließt Fußzeilen aus und sperrt bei mehr als 55 mm ungewöhnlicher freier Fläche die Sichtfreigabe. Eine agentenseitig begründete Ausnahme ist ausschließlich über `finalisieren --dichteausnahme-begruendung` mit hashgebundenem Nachweis möglich.

- Ein einziger Standardbibliothekskern unter `Tools/apply_foundry/` unterstützt
  Windows, Linux und macOS auf x64 (Intel/AMD); ARM64 ist vorerst nicht Teil
  des freigegebenen Umfangs.
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
  x64 und die Python-3.11-Mindestversion ab; Browsernachweise bleiben
  bis zu drei dokumentierten grünen Läufen je Zielprofil Vorschau.
- Die plattformneutralen Runtime- und Linux-Sandbox-Vertragstests laufen nun
  auch auf Windows und macOS korrekt. Auf GitHub-Windows-Runnern wird der
  Setup-Dry-run nur ausgeführt, wenn der projektvertraglich vorgeschriebene
  Paketmanager `winget` tatsächlich vorhanden ist; der Paketweg bleibt durch
  die vollständige synthetische Vertragssuite abgedeckt.

### Dokumentation

- README, Agentenregeln, Prompts, Kompatibilitätsübersicht, Beispiele und
  Roadmap dokumentieren ausschließlich den Python-Kern und die aktuellen
  Setup-/Freigabeverträge.
- Die README ist wieder ein vollständiger deutschsprachiger Leitfaden für
  Nutzung und Entwicklung: Schnellstart, Dialog, Artefakte, lokale Freigabe,
  Dichtesperre, Architektur, Python-Tests und die aktuelle CI sind auf den
  gemeinsamen Python-Kern ausgerichtet.
- Veraltete Runtime- und Legacy-Verweise wurden vollständig entfernt.
