# Qualitätscheck

Vor der finalen Ausgabe muss der Agent diese Punkte prüfen und das Ergebnis als `Qualitaetscheck.md` speichern.

## Inhalt

- Ist die Bewerbung klar auf die Stellenbeschreibung zugeschnitten?
- Sind die wichtigsten Anforderungen der Stelle sichtbar?
- Sind irrelevante Profilteile für die konkrete Zielrolle entfernt oder reduziert?
- Sind die rollennahen Kenntnisse aus den privaten Profildaten sichtbar genug?
- Sind passende Projekte oder Praxisbelege ausreichend sichtbar?
- Sind alle Angaben wahr und durch die Profildaten gedeckt?
- Gibt es keine erfundenen Arbeitgeber, Zeiträume oder Zertifikate?
- Sind die wichtigsten Keywords natürlich enthalten?
- Wirkt der Text recruiterfreundlich und nicht KI-generiert?

## Lebenslauf

- Ist der Lebenslauf scanbar?
- Ist die Reihenfolge passend zur Zielrolle?
- Sind Skills sauber gruppiert?
- Ist die Länge angemessen?
- Sind private IT-Kenntnisse professionell formuliert?
- Sind Kontaktdaten korrekt?
- Sind finale sichtbare Platzhalter vollständig entfernt?
- Sind fehlende Daten stattdessen in `Offene_Fragen.md` dokumentiert?

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
- Keine externen Abhängigkeiten.
- Dateinamen folgen dem Schema `Lebenslauf--FIRMA.html` und `Anschreiben--FIRMA.html`.
- Keine sichtbaren Marker wie `[ergänzen]`, `{{FIRMA}}`, `TODO` oder `DOKUMENT NOCH NICHT FINAL`.
- Firefox-Druckansicht wurde gedanklich oder praktisch geprüft.
- Die Druckansicht entspricht den sichtbaren Browser-Proportionen.
- Der Print-Modus verkleinert Schrift, Spaltenbreiten oder Abstände nicht heimlich gegenüber der Browseransicht.
- Bei Einseiten-Lebenslauf oder Einseiten-Anschreiben erzeugt Firefox keine erste Seite nur mit Kopfbereich und keine zweite Seite nur mit Hauptinhalt.
- Bei bewusst zweiseitigem Lebenslauf existieren zwei explizite A4-Seitencontainer statt eines automatisch umbrechenden langen Containers.
- `@page` ist widerspruchsfrei und nutzt in finalen Dateien `margin: 0`.
- `html`, `body` und `.page` haben im Print-Modus die A4-Geometrie `210mm x 297mm`.
- `overflow: hidden` wird nur auf der äußeren A4-Seitenfläche genutzt, nicht auf einzelnen Textblöcken.
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
- bewusst weggelassene Inhalte
- offene Daten oder Risiken
- verwendete Designvorlage, falls vorhanden