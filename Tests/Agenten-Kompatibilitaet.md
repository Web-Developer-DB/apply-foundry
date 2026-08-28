# Kompatibilitätsübersicht

Der produktive Bewerbungsworkflow verwendet einen Python-3.11+-Kern mit
Standardbibliothek. Unterstützt werden Windows, Linux und macOS ausschließlich
auf x64 (Intel/AMD). ARM64 ist derzeit nicht freigegeben. Die 23 CLI-Subcommands, privaten Auftragsformate, Hashbindungen und
Freigabegates sind plattformgleich.

| Ziel | Runtime und Paketweg | Status |
| --- | --- | --- |
| Windows x64 | Python, ausschließlich winget | Vorschau bis drei dokumentierte Browserläufe |
| Linux x64 | Python, APT/DNF/YUM/Pacman/Zypper | Vorschau bis drei dokumentierte Browserläufe je Zielprofil |
| macOS Intel x64 | Python, ausschließlich Homebrew | Vorschau bis drei dokumentierte Browserläufe |

Vor jedem Start, Reparatur- oder Testauftrag gilt:

```bash
python3 Tools/setup.py --all --dry-run --format json
python3 Tools/bewerbung.py diagnose --als-json
```

Installierbar sind nur Python, ein Chromium-Browser, die passende Systemschrift
und ShellCheck – ausschließlich nach einem sichtbaren Plan und bestätigter
Berechtigung. Linux verwendet Liberation Sans, Windows Arial, macOS Arial oder
Liberation Sans. Snap, AUR, PyPI, virtuelle Umgebungen, zusätzliche Quellen,
Editor-Erweiterungen und Agenten-Plugins sind ausgeschlossen.

Die CI führt die browserfreien Python-Verträge auf Windows, Linux und macOS auf
x64 aus; ein separater Python-3.11-Job schützt das Minimum. Die
Browsermatrix prüft Chromium-Druck, A4-Geometrie und ATS mit synthetischen
Fixtures. Direkte Aufrufe entfernter Legacy-Skripte sind im Major-Release nicht kompatibel.
