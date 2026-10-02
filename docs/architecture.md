# Architektur und Entwicklung

## Projektprinzipien

- Ein Python-3.11+-Kern aus Standardbibliothek statt plattformgetrennter Workflowimplementierungen.
- Ein kanonischer Bewerbungsworkflow in `AGENTS.md` und `Prompts/`, keine doppelten Agentenanweisungen.
- Private Daten nur unter `Private/`; öffentliche Tests verwenden ausschließlich synthetische Fixtures.
- Fail-closed bei unsicheren Pfaden, fehlenden Fähigkeiten, nicht aktuellen Artefakten und ungeklärter Sichtfreigabe.
- Keine versteckte Installation oder externe Übermittlung im Bewerbungsworkflow.

## Architektur

| Bereich | Aufgabe |
| --- | --- |
| [`AGENTS.md`](../AGENTS.md) | Routing, Sicherheitsgrenzen und Arbeitsregeln für Agenten |
| [`Prompts/README.md`](../Prompts/README.md) | kanonischer Bewerbungsworkflow und schrittbezogene Regeln |
| [`Tools/bewerbung.py`](../Tools/bewerbung.py) | plattformneutraler CLI-Dispatcher |
| `Tools/apply_foundry/` | Python-Kern für Aufträge, Verträge, Browser, PDF, ATS und Finalisierung |
| [`Tools/setup.py`](../Tools/setup.py) | read-only Setupplanung und bestätigte Systeminstallation |
| `Tests/` | synthetische Vertrags-, Browser-, Setup- und Promptregressionen |
| [`Private.example/README.md`](../Private.example/README.md) | private Strukturvorlage ohne Nutzerdaten |

## Prompt-System und Dateiverträge

[`Prompts/00_AGENTEN_START_HIER.md`](../Prompts/00_AGENTEN_START_HIER.md) ist der Einstieg für Bewerbungsaufträge. Die Module `01` bis `11` werden erst bei ihrem jeweiligen Arbeitsschritt geladen. Technische Verträge betreffen unter anderem:

- feste A4-HTML-Seiten und kontrollierte Chromium-Druckvorprüfung,
- strukturierte, hashgebundene private Aufträge, Matrix- und Evidenzdateien,
- Layout-, PDF-, ATS- und Finalisierungsberichte,
- persönliche Sichtfreigabe mit aktuellem Artefaktsatz,
- strikte Trennung zwischen privatem Arbeitsordner, `Versand/` und `Intern/`.

Bei zweiseitigen Lebensläufen erzwingt der statische Prüfer pro Seite einen `data-cv-page-header`, pro fachlicher Rubrik eine dokumentweit eindeutige `data-cv-section`-Kennung und einen `<footer class="page-footer">`. Die Dichtemessung schließt den Footerbereich aus und blockiert ungewöhnlich große freie Inhaltsflächen vor der Sichtfreigabe.

## Tests und CI

Die schnelle browserfreie Prüfung:

```bash
python3 -m unittest discover -s Tests/Python -p 'test_*.py'
python3 Tools/bewerbung.py tests --suite vollstaendig
```

Die vollständige synthetische Regression einschließlich Browser, PDF und ATS:

```bash
python3 Tools/bewerbung.py tests --mit-browser
```

Die CI-Workflows, etwa [`tests.yml`](../.github/workflows/tests.yml), prüfen Python-Verträge auf Windows, Linux und macOS, die Python-3.11-Mindestversion, die Browser-Smokes sowie die Linux-Distributionskompatibilität. Promptregressionen bleiben von den erforderlichen Zugangsdaten abhängig und verwenden bereinigte synthetische Arbeitskopien.

## Empfohlener Entwickler-Workflow

1. Vor Tests oder Reparaturen `python3 Tools/setup.py --all --dry-run --format json` ausführen.
2. Nur betroffene Prompts, Tools und Tests lesen und ändern.
3. Keine privaten Daten nachverfolgen, in Logs schreiben oder als Testfixture verwenden.
4. Bei funktionalen Änderungen [`CHANGELOG.md`](../CHANGELOG.md) aktualisieren.
5. Passende browserfreie Tests und bei Browseränderungen die vollständige Browserregression ausführen.

---

## Agenteneinstieg und Nachweisstand

Das Repository definiert einen gemeinsamen Workflow. Codex nutzt `AGENTS.md`; `CLAUDE.md` und `GEMINI.md` binden diese Regeln ein. `opencode.json` deaktiviert das Teilen und enthält keinen eigenen Workflow.

Codex, Claude Code, Gemini CLI und OpenCode sind in der [Promptregressions-Konfiguration](../Tests/PromptRegression/models.json) vorgesehen. Ein Eintrag oder Adapter ist kein erfolgreich ausgeführter Modelltest. Die [Dialogtestszenarien](../Tests/Interaktiver-Bewerbungsdialog.md) trennen deterministische Vertragsprüfungen von echten Modellsitzungen. Ein gespeicherter vollständiger Modelltestnachweis für alle vier Umgebungen liegt im aktuellen Repository nicht vor.

Der normale Nutzer benötigt keine CLI-Kenntnisse. Der Agent bedient die Werkzeuge unter den verfügbaren Berechtigungen und prüft benötigte Fähigkeiten. Modellzugang und Agenteninstallation sind externe Voraussetzungen; das Setup installiert keine Agenten, Plugins oder API-Zugänge.

## Weitere Dokumentation

- [Technischer Workflow und Freigabe](technical-workflow.md)
- [Plattformen und Setup](platform-support.md)
- [Synthetische README-Beispiele](../Tests/Fixtures/Readme/README.md)
- [Console-App-Roadmap](console-app.md)

[Zurück zur README](../README.md#entwicklung)
