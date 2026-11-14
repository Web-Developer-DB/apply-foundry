# Synthetische README-Beispiele

Diese öffentlichen Quellen enthalten ausschließlich fiktive Angaben. Es wird
kein Inhalt aus dem privaten Arbeitsbereich gelesen. Die Diagramme sind
schematische Darstellungen; Lebenslauf und Anschreiben sind Designvorschauen
aus den [vorhandenen Referenzen](../../../Vorlagen/README.md).

Die Beispiele sind keine Kandidaten einer echten Bewerbung und besitzen
keinen Freigabe- oder fachlichen Prüfnachweis. Ihre sichtbare Kennzeichnung
gehört zum Bild. Sie dürfen nicht als echte Bewerbung verwendet werden.

## Synthetischer Workflow-Test

Die Bildfolge in der README beruht auf einem von einem Agenten ausgeführten
Testlauf in einer temporären Projektkopie auf Linux x64. Das angepasste
Browser-Smoke-Fixture verwendete fiktive Angaben für Max Muster und die
Acme GmbH. Der Agent erstellte die synthetischen Testdateien und führte die
Projektwerkzeuge bis `bereit_zur_sichtpruefung` aus. Chromium erzeugte zwei
PNG-Vorschauen und PDFs. Die ATS-Prüfung meldete für beide PDFs eine
Textabdeckung von 100 Prozent.

Die Dateien `real-run/lebenslauf.png` und `real-run/anschreiben.png` sind
die unveränderten PNG-Ausgaben dieses Layoutchecks. Die Abgleichgrafik
überträgt zwei Anforderungen und den zugehörigen Profileintrag aus dem
Testlauf in eine gestaltete Darstellung. Die Ergebnisgrafik zeigt die
vorgesehene Ordnerstruktur schematisch. Im Testlauf erfolgte keine persönliche
Freigabe und keine Veröffentlichung. Ein interaktiver Agentendialog wurde
nicht aufgezeichnet.

Die drei erläuternden Grafiken lassen sich aus den gespeicherten Vorschauen
und den synthetischen Angaben erneut rendern:

```bash
python3 Tests/Fixtures/Readme/real-run/render.py
```

Das Skript verwendet einen vorhandenen Chromium-Browser und ein temporäres
Browserprofil. Der Testlauf selbst ist ein angepasster Browser-Smoke-Test
und wird durch dieses Render-Skript nicht erneut ausgeführt.

## Reproduzieren

Im Projektstamm zunächst die verfügbaren Voraussetzungen read-only prüfen:

```bash
python3 Tools/setup.py --all --dry-run --format json
python3 Tests/Fixtures/Readme/render_examples.py
```

Das Skript nutzt System-Python, einen vorhandenen Chromium-Browser und die
bestehenden Screenshot-Hilfen. Es ersetzt alle Platzhalter aus
`example-data.json`, entfernt den optionalen Foto-Platzhalter und prüft
die DOM-Geometrie auf Überlauf. Es benötigt keine Modellaufrufe und keine
zusätzlichen Pakete. Die Standardausgabe liegt unter `.github/assets/`.
Vorhandene Bilder dort werden bei diesem ausdrücklich gestarteten
Regenerierungslauf ersetzt.

Optional kann ein existierender Browser mit `--browser-path` oder ein anderes
Ausgabeverzeichnis mit `--output-dir` angegeben werden. Browserprofile und
Capture-HTML liegen nur in einem temporären Ordner. Die Bilderzeugung ist
reproduzierbar, aber PNG-Bytes können zwischen Browser- und Schriftversionen
abweichen.

- `cv-example.png`, `cover-letter-example.png`: 794 × 1123 Pixel, feste A4-Seite.
- `workflow-example.png`, `output-example.png`: 794 × 560 Pixel, schematische Übersicht.

Jedes neu erzeugte Bild muss tatsächlich visuell auf Lesbarkeit, vollständige
Darstellung und synthetische Kennzeichnung geprüft werden. Die
Screenshot-Geometrie ist keine fachliche Wahrheitsprüfung, PDF-/ATS-Prüfung
oder persönliche Bewerbungsfreigabe.

[Zurück zu den Beispielen](../../../README.md#beispiele)
