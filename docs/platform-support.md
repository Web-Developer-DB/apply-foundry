# Plattformunterstützung und Setup

## Aktueller Entwicklungsstand

Der aktuelle Produktivkern unterstützt ausschließlich **Windows x64, Linux x64 und macOS Intel x64**. ARM64, darunter Apple Silicon, ist nicht freigegeben. Mobile Plattformen und BSD-Systeme gehören nicht zum Projektvertrag.

Der Architekturvertrag ist im [Abhängigkeitsmanifest](../Tools/dependencies.json), im [Setup](../Tools/setup.py) und in der [Runtimeprüfung](../Tools/apply_foundry/runtime.py) umgesetzt: Zulässig sind x86_64 beziehungsweise amd64. Ein erkanntes ARM64-System wird nicht dadurch unterstützt, dass ein Browser auf dieser Architektur verfügbar wäre.

## Nachweisstand

Die Python-Vertrags-CI ist für Windows, Linux und macOS x64 konfiguriert, ergänzt um die Python-3.11-Mindestversion. Die Browser-Smoke-Matrix prüft Chromium-Druck, A4-Geometrie und ATS. Eine konfigurierte Matrix beweist keine ausgeführten grünen Läufe.

Der [gespeicherte Browserstabilitätsnachweis](../Tests/Stabilitaetsnachweise/browser-smoke.json) enthält derzeit keine dokumentierte Folge von drei grünen Läufen je Zielprofil. Der vollständige Browserworkflow bleibt deshalb **Vorschau**. Für Linux werden außerdem mehrere Distributionsfamilien geprüft. Die [Kompatibilitätsübersicht](../Tests/Agenten-Kompatibilitaet.md) beschreibt die Zielprofile.

## Voraussetzungen und erlaubte Paketwege

| Plattform | Paketweg | Referenzschrift |
| --- | --- | --- |
| Windows x64 | ausschließlich winget | Arial |
| Linux x64 | APT, DNF/YUM, Pacman oder Zypper | Liberation Sans |
| macOS Intel x64 | ausschließlich Homebrew | Arial oder Liberation Sans |

Alle Plattformen benötigen System-Python 3.11+. Für HTML-Dokumente kommt ein lokal verfügbarer Chrome-, Edge- oder Chromium-Browser hinzu. ShellCheck ist optional für zusätzliche Shell-/CI-Prüfungen. Eine reine E-Mail benötigt keine Browser-, PDF- oder ATS-Erzeugung.

Vor Start-, Reparatur- oder Testaufträgen prüft der Agent read-only:

```bash
python3 Tools/setup.py --all --dry-run --format json
python3 Tools/bewerbung.py diagnose --als-json
```

Ein angezeigter Installationsplan ist keine erfolgte Installation. Änderungen werden ausschließlich nach sichtbarem Plan und bestätigter Berechtigung mit `--yes` ausgeführt. Pacmans erster `-Syu`-Lauf kann das vollständige System aktualisieren; diese breitere Änderung muss vorher erkennbar sein.

Das Setup installiert nur Python, Chromium-Browser, Systemschrift und optional ShellCheck aus den deklarierten Paketwegen. PyPI, virtuelle Umgebungen, Snap, AUR, zusätzliche Paketquellen, Agenten-Plugins und Editor-Erweiterungen sind kein Installationsweg. Unbekannte Paketmanager, Ubuntu-Snap und macOS ohne Homebrew erhalten eine präzise manuelle Voraussetzung. Es gibt keinen Firefox-Fallback für den verbindlichen PDF-Export und keinen unsicheren lokalen Sandbox-Bypass.

Fehlt Python, dienen die POSIX- und CMD-Starter ausschließlich dem ausdrücklich autorisierten Runtime-Bootstrap mit `--runtime --yes`; danach delegieren sie an den Python-Kern.

Nach einem Runtime- oder Plattformwechsel bleiben bestehende Aufträge lesbar. Technische Nachweise müssen für die neue Umgebung neu erzeugt werden. Die vorhandenen Prüf- und Freigabegates bleiben verbindlich.

## Release v2.0 und spätere Einschränkung

| Stand | Deklarierter Architekturumfang |
| --- | --- |
| Tag v2.0, Commit `81c0e068bc0727b42f1b3f2c52a94bc7c929cca9`, 24. August 2026 | x64 und ARM64 in Manifest, Runtime/Setup und CI-Konfiguration |
| Commit `ee8d3dd9247ff5fba6aeffea15208800bb6a055f`, 28. August 2026 | Beschränkung auf x64; ARM64 aus Runtime/Setup, Manifest und CI-Matrizen entfernt |
| Aktueller Entwicklungsstand | ausschließlich x64 |

Der [historische GitHub-Release-Text](https://github.com/Web-Developer-DB/apply-foundry/releases/tag/v2.0) beschreibt den Stand des Tags. Die [Änderung des Architekturvertrags](https://github.com/Web-Developer-DB/apply-foundry/commit/ee8d3dd9247ff5fba6aeffea15208800bb6a055f) erfolgte danach. Aus der damaligen Deklaration oder CI-Konfiguration folgt kein hier belegter vollständiger Browserstabilitätsnachweis auf ARM64.

Die Releasehistorie wird erhalten; für einen neuen Start ist der aktuelle Vertrag maßgeblich. Weitere Änderungen stehen im [Changelog](../CHANGELOG.md).

[Zurück zur README](../README.md#plattformstatus)
