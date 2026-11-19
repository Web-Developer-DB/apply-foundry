# Promptprüfung für GPT-6.1 und GPT-6.2

Stand: 19. November 2026. Untersuchte Ausgangsfassung: Commit `9d7d174`.

## Ergebnis und Aussagegrenze

Untersucht wurden `AGENTS.md`, alle zwölf operativen Promptmodule `00` bis `11`,
der Promptindex, die Agentenadapter und die bestehende Promptregression.
Private Bewerberdaten und echte Bewerbungsdateien wurden dafür nicht gelesen
oder verändert.

Die Regeln sind nicht allein wegen ihres Alters ungeeignet. Ein großer Teil
beschreibt weiterhin notwendige Produktanforderungen: wahrheitsgemäße Belege,
private Ablage, strukturierte Aufträge, druckbare Dokumente und persönliche
Freigabe. Eine explizite Aufforderung zur Ausgabe ausführlicher interner
Denkschritte wurde in den untersuchten Modulen nicht gefunden.

Konkreten Änderungsbedarf liefern widersprüchliche Quellenregeln, zu pauschale
Belegvorsicht, fehlende kanonische Abläufe, doppelte Befehle und teils starre
Arbeitsanweisungen. Diese Befunde wurden direkt korrigiert. Die neue Fassung
ist eine begründete, technisch geprüfte Verbesserung der Instruktionsbasis;
eine empirisch optimale Textqualität für GPT-6.1 oder GPT-6.2 ist damit noch
nicht nachgewiesen.

## Offizielle Quellen und ihre Übertragung

Die folgenden Quellen wurden am 19. November 2026 geprüft. Ihre Empfehlungen
sind Ausgangspunkte; die Anwendung auf diesen Bewerbungsworkflow ist eine
Projektentscheidung.

- [OpenAI: Using GPT-6.2](https://developers.openai.com/api/docs/guides/latest-model):
  Kürzeanforderungen bei der Migration erneut prüfen, für längere Aufgaben
  eigenständige Fortsetzung ermöglichen und externe Texte auf ihre Leser
  ausrichten. Übertragung: genug Belegkontext erhalten und nur an echten
  Entscheidungen oder Freigaben stoppen.
- [OpenAI: Reasoning best practices](https://developers.openai.com/api/docs/guides/reasoning-best-practices):
  direkte Ziele, klare Grenzen und eindeutige Erfolgskriterien; keine
  vorgeschriebene Ausgabe interner Denkschritte. Übertragung: überprüfbare
  Strategie und Nachweise statt einer festen Abfolge von Denkoperationen.
- [OpenAI: Evaluation best practices](https://developers.openai.com/api/docs/guides/evaluation-best-practices):
  repräsentative Fälle, definierte Kriterien und wiederholte Vergleiche.
  Übertragung: lokale Vertragstests und echte Modellqualität getrennt bewerten.
- [OpenAI: GPT-6.2 Sol](https://developers.openai.com/api/docs/models/gpt-6.2-sol)
  und [GPT-6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol):
  verifizierte Zielmodell-IDs für die Testkonfiguration. Die Auswahl von Sol
  ist eine Vergleichsbasis, keine Behauptung, es liefere bessere Anschreiben
  als jede andere Variante.

Das Repository integriert kein eigenes OpenAI-API-Gesprächsmanagement. Deshalb
wurden keine API-Parameter, Caching-Mechanismen oder Reasoning-Einstellungen in
Prompts hineingeschrieben. Modellwahl, verfügbare Werkzeuge und Berechtigungen
werden von der jeweiligen Agentenumgebung beziehungsweise dem Testkatalog
gesteuert.

## Befunde je Datei

Die Befunde beziehen sich auf die genannten Abschnitte der Ausgangsfassung;
die verlinkten Dateien enthalten bereits die überarbeitete Fassung.

| Datei | Befund und mögliche Auswirkung | Entscheidung |
| --- | --- | --- |
| [AGENTS.md](../AGENTS.md) | Keine gemeinsame Trennung zwischen Ergebnisvertrag und flexibler Arbeitsweise. „Private Dateien niemals ungefragt überschreiben“ kann auch beauftragte Kandidatenkorrekturen blockieren. Der Firmenpfad und `finalisieren` nennen keine Universal-Ausnahme. | Ergebnisorientiertes Arbeiten bis zum echten Gate; Befugnis für eigene generierte Arbeitsstände präzisiert; Quellen-/Profilzustimmung geschützt; Universal-Ausnahme ausdrücklich benannt. Übergeordnete Laufzeitregeln und technische Ablehnungen bleiben wirksam. |
| [00 – Einstieg](../Prompts/00_AGENTEN_START_HIER.md) | `AGENTS.md` verweist auf „Fortsetzen ohne Chatverlauf“ und einen Universalprozess; beide fehlen als vollständige Abläufe. Die Standardfolge kann zu doppelten Einzelprüferläufen vor `finalisieren` führen. | Beide kanonischen Abläufe ergänzt und gegen den Python-Kern abgeglichen. Zuständige Module pro Phase benannt, technische Orchestrierung beim Dispatcher belassen. |
| [01 – Dialog](../Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md) | Bereits gute Regeln für eindeutigen Umfang, sparsame Rückfragen und Speicherzustimmung. Lange Menübeispiele können als wortgetreue Skripte missverstanden werden. Eine allgemeine Stoppregel kann auf optionale Angaben übergreifen. Die abschließende Kurzdefinition von B kann eine nicht genannte E-Mail ergänzen. | Fachliche Optionen und Zustände bleiben verbindlich; natürliche Formulierungen und freie eindeutige Antworten ausdrücklich zugelassen. Nicht blockierende Details dürfen entfallen; unabhängige Arbeit darf weiterlaufen. B wird nur aus einem eindeutig passenden Auftrag abgeleitet. Schema 5 bleibt unverändert. |
| [02 – Vorprüfung](../Prompts/02_VORPRUEFUNG_UND_ANFORDERUNGSMATRIX.md) | Identischer `stammdaten`-Befehl doppelt. Sichtbare Textanker sollen schon vor dem ersten Dokumententwurf final sein. | Doppelbefehl entfernt; Strategie vor Entwurf, Textanker anschließend am tatsächlichen Dokument abgleichen. Die vollständige Inhaltsprüfung bleibt vor dem Layout erforderlich. |
| [03 – Lebenslauf](../Prompts/03_LEBENSLAUF_REGELN.md) | „Nur Daten aus Private/Daten“ schließt die nach 01 erlaubten Dialogangaben aus. Pauschal vorsichtigere Belegart kann Berufspraxis herabstufen. Eine Ausnahme für `NICHT BEHAUPTEN` widerspricht 07. Vermutete Firmengröße kann zu unbelegter Positionierung führen. | Bestätigte Auftragsangaben zugelassen; konkrete Aussage und Anwendungskontext entscheiden; harte Sperre vereinheitlicht; Organisationsannahmen an belastbare Hinweise gebunden. |
| [04 – Anschreiben](../Prompts/04_ANSCHREIBEN_REGELN.md) | Quellenregel nennt nur Private/Daten. „Vollständig geprüfter“ Universal-CV vor dem ersten Anschreiben kann einen unnötigen technischen Vorablauf nahelegen. Inhaltsgliederung kann wie eine Absatzschablone wirken. | Auftragsangaben konsistent zugelassen; Quellenabgleich vor Entwurf, gemeinsame Technikprüfung danach. Inhaltsfunktionen und Leserbedarf anstelle fester Absätze erläutert. |
| [05 – E-Mail](../Prompts/05_EMAIL_NACHRICHT_REGELN.md) | „Ersetzt nicht das Anschreiben“ passt nicht uneingeschränkt zum erlaubten E-Mail-only-Auftrag. Hinweis auf „unveränderten“ Universal-CV kann interne Workflowdetails in den Versandtext bringen. | Versandzweck nach Umfang definiert; Anlagen mit normalen Dokumentnamen nennen; Zeilenzahl als Richtwert erklärt. Dateiname und Anlagenwahrheit bleiben feste Verträge. |
| [06 – Rollenlogik](../Prompts/06_ROLLENLOGIK.md) | 17 vorgeschriebene Arbeitsschritte wiederholen Profilabgleich und Matrix. Strategie soll in mehreren Dateien stehen. Pauschale Belegvorsicht wiederholt das Problem aus 03. | Durch einen Strategieauftrag mit denselben Ergebnisfeldern ersetzt. Analyse enthält Entscheidungen, Qualitätscheck das Prüfurteil. Belegkontext vereinheitlicht; Unternehmensvermutungen sind keine Tatsachen. |
| [07 – Wahrheit](../Prompts/07_WAHRHEIT_UND_GRENZEN.md) | Grundregel erlaubt scheinbar auch Bewerberbehauptungen aus der Stellenbeschreibung. Bestätigte Dialogangaben stehen erst im späteren Evidenzabschnitt. | Zuständigkeit der Quellen schon in der Grundregel eindeutig gemacht. Bewerberbelege, Arbeitgeberkontext und aktivierte Gehaltsschätzung getrennt; Belegkontexte auf Aussageebene präzisiert. |
| [08 – Design](../Prompts/08_HTML_CSS_DESIGNREGELN.md) | Feste A4- und Druckregeln sind reale Werkzeugverträge. Das Einseitenbeispiel enthält den Vorschauhintergrund außerhalb von `@media screen` und weicht beim Fontstack vom übrigen Projekt ab. | Verträge erhalten; Beispielhintergrund auf Bildschirmansicht begrenzt und Liberation Sans ergänzt. Freiraum bei nichtvertraglichen Designmaßen erklärt. |
| [09 – Qualitätscheck](../Prompts/09_QUALITAETSCHECK.md) | Check verlangt immer zwei bis vier Anschreibenargumente, obwohl 02/04 ein schmales Profil mit einem Argument erlauben. Veralteter Parameter `-VisuelleFreigabeNotiz`. | Ausnahme angeglichen; gültige Freigabenotiz über `freigabe --notiz` genannt. Visuelle Prüfung und persönliche Bestätigung bleiben getrennte Pflichten. |
| [10 – Dateien](../Prompts/10_DATEI_UND_ORDNER_REGELN.md) | „Optionales Hilfsskript“ widerspricht dem verbindlichen Anlageweg. Identischer Anlagebefehl zweimal. | Verbindlichen Auftragseinstieg benannt und Doppelbeispiel entfernt. Private Ablage, Slugs, Snapshotbindung und atomare Veröffentlichung bleiben erhalten. |
| [11 – Technik](../Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md) | Hinweise auf „beide Kerne“ sind trotz gemeinsamem Python-Kern veraltet. Tokenabschlussfolge verlangt zusätzliche Berichte, obwohl 03 bei fehlenden Messdaten darauf verzichtet. Alte Modell-Canary zielt auf GPT-5.6. | Gemeinsamen Kern und bedarfsabhängige Nutzungsberichte vereinheitlicht. Unabhängige Lesezugriffe dürfen gebündelt werden; abhängige Prüfschritte bleiben geordnet. Modellmatrix aktualisiert. |

Die Adapter `CLAUDE.md`, `GEMINI.md` und `opencode.json` enthalten keine eigene
Bewerbungslogik und wurden deshalb beibehalten. Der Promptindex verweist auf
diesen Bericht und den Evaluationsplan; beide sind Entwicklerdokumentation,
keine zusätzlichen Pflichtdateien für jede Bewerbung.

## Bewusst erhaltene Produktentscheidungen

- Keine erfundenen Fakten und keine Aufwertung privater Praxis zu Berufspraxis.
- A–E-Umfang, explizites E-Mail-only-Gate und Zustimmung für dauerhafte
  Profiländerungen.
- Vollständige geforderte formale CV-Stationen sowie der gewählte
  Schulbildungsmodus. Dies sind Projektkonventionen; das Audit belegt sie nicht
  als universelle Vorgabe jedes deutschen Recruiters.
- Feste A4-Seiten, maximal zwei Lebenslaufseiten, semantischer Universalplan,
  Ressourcenbegrenzung, PDF-/ATS-Nachweise und Dichte-Gate mit begründeter
  Ausnahme. Eine Modellmigration allein rechtfertigt keine Vertragsänderung.
- Quellen- und Artefakthashes, private Ablage, keine externe Übermittlung sowie
  neue persönliche Freigabe nach jeder relevanten Änderung.

Wiederholungen kritischer Grenzen an ausführbaren Schritten wurden nicht
pauschal entfernt. Sie verhindern konkrete Fehler. Reine Doppelbefehle und
widersprüchliche zweite Definitionen wurden dagegen bereinigt.

## Verifikation und noch ausstehende Messung

Die unveränderte Ausgangsfassung bestand lokal 103 browserfreie Vertragstests.
Die überarbeitete Fassung bestand dieselbe vollständige Suite einschließlich
eines neuen Abgleichs der Prompt-Befehle mit der CLI-Registry: 104 bestanden,
0 fehlgeschlagen, 0 übersprungen. `git diff --check` meldete keine Fehler.
Die Prüfung umfasst auch lokale Dokumentlinks und bestehende Vertragsgrenzen,
aber keine semantische Bewertung neu erzeugter Bewerbungstexte.

Die Umgebung stellt Python, Chrome und Liberation Sans bereit. Das optionale
ShellCheck fehlt; Shellskripte wurden nicht verändert und keine Pakete
installiert. Es wurde kein Browser- oder Bewerbungsfinalisierungslauf als Teil
dieser Promptänderung ausgeführt.

Echte Modellvergleichsläufe wurden nicht ausgeführt: Die vom isolierten Runner
deklarierten API-Zugangsdaten sind nicht verfügbar; außerdem meldet die lokale
Codex-CLI `0.169.1` statt der im Testkatalog festgelegten
`0.148.0-alpha.15`. Der Desktop-Modellzugang wird nicht mit einem API-Credential
gleichgesetzt und die Versionsprüfung wird nicht umgangen. Die Testkataloge
sind eine vorbereitete Zielkonfiguration, kein Kompatibilitätsnachweis für die
festgelegten CLIs mit den neuen Modellen.

Der [Evaluationsplan](../Tests/PromptRegression/README.md) legt fest, wie alte
und neue Prompts unter denselben Modellen verglichen werden. Erst diese
Messung kann eine tatsächliche Qualitätsverbesserung oder einen weiteren
Änderungsbedarf belegen. Aktuell gibt es weder einen gemessenen Qualitätsgewinn
noch belastbare Aussagen zu Token- oder Kosteneinsparungen.
