# Roadmap: Apply Foundry als installierbare Console App

> Status: **Konzept / nicht implementiert**  
> Dokumenttyp: **Roadmap**  
> Verbindlichkeit: **nicht operativ und nicht maßgeblich für den Bewerbungsworkflow**

Diese Datei beschreibt mögliche Zukunftsschritte für eine lokale Terminal-Anwendung. Sie ist keine operative Agentenanweisung, keine aktuelle Produktzusage und keine verbindliche Implementierungsspezifikation. Maßgeblich sind ausschließlich `AGENTS.md`, `Prompts/00_AGENTEN_START_HIER.md`, die jeweils zuständigen Promptmodule sowie die tatsächlich vorhandenen Werkzeuge und Tests.

## Zielbild

Eine optionale lokale Console App könnte den bestehenden Bewerbungsworkflow über eine verständliche Terminaloberfläche starten und fortsetzen. Die fachliche Logik bliebe in den vorhandenen Prompts und Python-Werkzeugen. Private Daten würden ausschließlich lokal verarbeitet; automatische Übermittlung oder Veröffentlichung bliebe ausgeschlossen.

## Nicht-Ziele

- keine neue fachliche Bewerbungslogik neben `Prompts/` und `Tools/`
- keine automatische Bewerbungssendung, Cloudspeicherung oder Telemetrie
- keine verpflichtende Desktop-GUI
- keine Übernahme globaler Agenten- oder Authentifizierungskonfigurationen
- keine Paketierung oder Modellbindung ohne späteren, separat geprüften Beschluss

## Mögliche Architektur

Eine spätere Umsetzung könnte aus einer dünnen Terminaloberfläche, einem Sitzungsadapter, einer sicheren Workspace-Verwaltung und einem Prozess-/Cleanup-Controller bestehen. Sie muss den kanonischen Python-Dispatcher `python3 Tools/bewerbung.py` verwenden und vorhandene Checkpoints, Prüfberichte, Hashbindungen und Freigabegates unverändert respektieren.

## Grobe Roadmap

1. Anforderungen und unterstützte Laufzeiten anhand der aktuellen Werkzeuge prüfen.
2. Ein kleines lokales CLI-Grundgerüst mit Hilfe, Diagnose und stabilen Exitcodes entwickeln.
3. Workspace-, Prozess- und Datenschutzgrenzen synthetisch testen.
4. Den bestehenden Workflow über den Dispatcher anbinden, ohne Verträge zu duplizieren.
5. Paket- und Abbruchtests auf einem sauberen Testsystem durchführen.
6. Eine begrenzte interne Erprobung mit ausschließlich synthetischen Daten auswerten.

## Qualitätsgates

Eine Umsetzung dürfte erst als belastbar gelten, wenn die vollständige Python-Suite, die synthetischen Rollen-Fixtures, die Browserprüfung, die Cleanup-Prüfungen und die Datenschutztests erfolgreich sind. Ein CLI-Test direkt aus dem Quellverzeichnis wäre kein ausreichender Paketnachweis.

## Offene Entscheidungen

Vor einer Implementierung müssten Laufzeit, Authentifizierungsmodell, unterstützte Plattformen, Paketierungsform, Updateverfahren und die genaue Prozessisolierung erneut anhand der dann aktuellen technischen Möglichkeiten entschieden werden. Keine dieser Entscheidungen ist durch diese Roadmap vorweggenommen.
