# Qualitätscheck

Vor der finalen Ausgabe muss der Agent diese Punkte prüfen und das Ergebnis als `Qualitaetscheck.md` speichern.

## Inhalt

- Ist die Bewerbung klar auf die Stellenbeschreibung zugeschnitten?
- Wurde das Bewerbungsprofil aus Stellenbeschreibung und privaten Daten abgeleitet, nicht aus öffentlichen Beispielprompts?
- Sind die wichtigsten Anforderungen der Stelle sichtbar?
- Sind irrelevante Profilteile für die konkrete Zielrolle entfernt oder reduziert?
- Sind die rollennahen Kenntnisse aus den privaten Profildaten sichtbar genug?
- Sind Zusatzkenntnisse nur enthalten, wenn sie für die Zielrolle einen Recruiter-Nutzen haben?
- Sind passende Projekte, Praxisbelege oder Erfahrungsbeispiele ausreichend sichtbar?
- Sind alle Angaben wahr und durch die Profildaten gedeckt?
- Gibt es keine erfundenen Arbeitgeber, Zeiträume, Zertifikate, Branchen, Tools oder Verantwortlichkeiten?
- Sind die wichtigsten Keywords natürlich enthalten?
- Wirkt der Text recruiterfreundlich und nicht KI-generiert?
- Wirkt der Lebenslauf wie ein deutscher tabellarischer CV und nicht wie eine Portfolio- oder Skill-Dashboard-Seite?

## Rollen- und Recruiter-Strategie

- Wurde Zielrolle, Branche oder Arbeitsfeld korrekt erkannt?
- Wurde die Firmengröße oder Organisationsart berücksichtigt, falls sie aus der Stellenbeschreibung ableitbar ist?
- Sind bei großen oder standardisierten Arbeitgebern Rollenpassung und Muss-Anforderungen besonders schnell sichtbar?
- Sind bei kleinen oder breiten Arbeitgebern nützliche Allrounder- und Zusatzkenntnisse sinnvoll, aber nicht ausufernd eingebunden?
- Lenkt kein Abschnitt von der Zielrolle ab?
- Sind bewusst weggelassene Inhalte in `Analyse.md` oder `Qualitaetscheck.md` kurz begründet?

## Lebenslauf

- Ist der Lebenslauf scanbar?
- Entspricht die Struktur einem modernen deutschsprachigen Lebenslauf und nicht nur einem Skill- oder Projektprofil?
- Ist die Reihenfolge passend zur Zielrolle?
- Sind Berufserfahrung oder berufliche Stationen klar sichtbar?
- Sind Ausbildung, Studium oder berufliche Bildung berücksichtigt, sofern entsprechende Daten vorhanden sind?
- Ist Schulbildung enthalten oder bewusst und nachvollziehbar weggelassen?
- Sind Weiterbildungen, Zertifikate und Qualifikationen sinnvoll platziert?
- Verdrängen Projekte, private Praxis, Zusatzkenntnisse oder Skill-Listen keine formalen CV-Stationen?
- Sind Kompetenzen sauber gruppiert und nicht als vollständige Inventarliste dargestellt?
- Werden Kompetenzen bevorzugt als klare Gruppen/Zeilen dargestellt statt als unruhige Tag-Wolke?
- Ist die Länge angemessen?
- Sind zusätzliche oder nicht-klassische Kenntnisse professionell und korrekt eingeordnet?
- Sind vorhandene Erfahrung, Grundlagen und Entwicklungsfelder sprachlich klar getrennt?
- Sind auffällige Lücken, Rollenwechsel oder aktuelle Phasen nachvollziehbar behandelt oder in `Offene_Fragen.md` dokumentiert?
- Sind Kontaktdaten korrekt?
- Sind Vorname und Nachname für die finalen Dateinamen eindeutig aus `Private/Daten/01_PERSOENLICHE_DATEN.md` übernommen?
- Enthalten finale Versanddateien den Bewerbernamen statt des Firmennamens?
- Sind finale sichtbare Platzhalter vollständig entfernt?
- Sind fehlende Daten stattdessen in `Offene_Fragen.md` dokumentiert?

## A4-Fit-Check

- Passt ein Einseiten-Lebenslauf vollständig in eine A4-Seite?
- Erzeugt Firefox bei einem Einseiten-Lebenslauf in der Druckvorschau genau eine Seite?
- Wenn eine Seite nicht sauber reicht: wurde bewusst ein strukturierter zweiseitiger Lebenslauf erstellt?
- Ist unten kein Inhalt abgeschnitten?
- Wurden bei Platzproblemen zuerst fachlich irrelevante Inhalte gekürzt, bevor Layout verdichtet wurde?
- Sind fachfremde Zusatzkenntnisse, Nebenprojekte oder lange Skill-Listen entfernt, wenn sie für diese Stelle keinen Nutzen haben?
- Bleiben Berufserfahrung, Ausbildung/Studium/berufliche Bildung, Schulbildung und wichtige Weiterbildungen trotz Kürzung sichtbar, sofern Daten vorhanden sind?
- Ist die Schrift auch nach Layoutoptimierung professionell lesbar?
- Gibt es keine versteckten Inhalte durch `overflow: hidden`?
- Wird `overflow: hidden` nur auf der äußeren A4-Seitenfläche genutzt und nicht auf Textabschnitten?
- Nutzt ein finaler Einseiten-Lebenslauf `height: 297mm` auf `.page` statt nur `min-height: 297mm`?
- Wenn zwei Seiten nötig sind: gibt es zwei explizite A4-Seitencontainer statt eines zufälligen Umbruchs?
- Wirkt Seite 2 bewusst strukturiert und nicht wie ein abgeschnittener Rest?

## Anschreiben

- Passt das Anschreiben zur Rolle?
- Ist es maximal eine A4-Seite?
- Gibt es konkrete Belege?
- Enthält es keine Floskeln?
- Enthält es keine Übertreibungen?
- Werden keine Unternehmensdetails erfunden?

## E-Mail-Nachricht

- Ist die Nachricht kurz und professionell?
- Wird die Stelle korrekt genannt?
- Wird auf Anlagen hingewiesen?
- Ist die Anrede passend oder neutral?

## HTML/CSS

- CSS ist im HTML integriert.
- A4-Druck ist berücksichtigt.
- Keine abgeschnittenen Inhalte.
- Keine fixen problematischen Höhen in Textbereichen.
- Einseiten-Dokumente verwenden eine feste A4-Seite und erzeugen keinen automatischen Firefox-Umbruch.
- Zweiseitige Dokumente verwenden explizite `.page`-Container, nicht einen langen Container mit Browser-Autoumbruch.
- Keine externen Abhängigkeiten.
- Finale Versanddateien folgen dem Schema `Lebenslauf - NACHNAME.VORNAME.html` und `Anschreiben - NACHNAME.VORNAME.html`.
- Keine sichtbaren Marker wie `[ergänzen]`, `{{FIRMA}}`, `TODO` oder `DOKUMENT NOCH NICHT FINAL`.
- Firefox-Druckansicht wurde gedanklich oder praktisch geprüft.
- Die Druckansicht entspricht den sichtbaren Browser-Proportionen.
- Der Print-Modus verkleinert Schrift, Spaltenbreiten oder Abstände nicht heimlich gegenüber der Browseransicht.
- Bei Einseiten-Lebenslauf oder Einseiten-Anschreiben erzeugt Firefox keine erste Seite nur mit Kopfbereich und keine zweite Seite nur mit Hauptinhalt.
- Bei bewusst zweiseitigem Lebenslauf existieren zwei explizite A4-Seitencontainer statt eines automatisch umbrechenden langen Containers.
- `@page` ist widerspruchsfrei und nutzt in finalen Dateien `margin: 0`.
- `html`, `body` und `.page` haben im Print-Modus die A4-Geometrie `210mm x 297mm`.
- Für Einseiter hat `.page` auch außerhalb des Print-Modus eine feste Höhe von `297mm`, damit Bildschirm- und Druckansicht dieselbe Seitenlogik zeigen.
- `overflow: hidden` wird nur auf der äußeren A4-Seitenfläche genutzt und darf keinen relevanten Inhalt verdecken.
- Browser-Kopf- und Fußzeilen sind als Nutzer-/Druckdialog-Einstellung dokumentiert.
- `Druck-Hinweis.md` liegt im Bewerbungsordner.

## Ablage

- Finale Dateien liegen im finalen Bewerbungsordner `Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/`.
- Temporäre Dateien und Entwürfe liegen nur unter `Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/`.
- Es liegen keine losen temporären Dateien direkt unter `Private/Bewerbungen/`.
- Es liegen keine echten persönlichen Daten in öffentlichen Ordnern wie `Prompts/`, `Vorlagen/`, `Tools/` oder `Private.example/`.

## Abschlussnotiz

Am Ende von `Qualitaetscheck.md` kurz festhalten:

- gewählte Profilstrategie
- vermutete Recruiter-Strategie und ggf. Firmengröße
- bewusst weggelassene Inhalte
- offene Daten oder Risiken
- verwendete Designvorlage, falls vorhanden
