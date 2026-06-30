# Datei- und Ordnerregeln

## Ziel

Für jede Bewerbung wird ein eigener privater Arbeitsordner erstellt.

Alle generierten Bewerbungsdateien liegen unter `Private/`, damit das Projekt ohne private Daten auf GitHub veröffentlicht werden kann.

## Öffentliche und private Bereiche

Öffentlich:

```text
Prompts/
Vorlagen/
Tools/
Private.example/
README.md
```

Privat und ignoriert:

```text
Private/
Private/Daten/
Private/Bewerbungen/
Private/Bewertungen/
Private/LebenslaufUniversal/
Private/Archiv/
```

## Hauptordner für Bewerbungen

Alle neuen Bewerbungen werden unter diesem Ordner gespeichert:

`Private/Bewerbungen/`

## Firmenordner

Der Firmenname wird als sauberer Ordnername verwendet.

Beispiel:

```text
Muster GmbH
```

wird zu:

```text
Private/Bewerbungen/Muster-GmbH/
```

## Bewerbungsordner

Jede einzelne Bewerbung bekommt zusätzlich einen Unterordner mit Datum und Rolle:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/
```

Beispiel:

```text
Private/Bewerbungen/Muster-GmbH/2026-06-30--Sachbearbeitung/
```

Wenn die Zielrolle nicht eindeutig ist:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--Bewerbung/
```

## Pflichtdateien pro Bewerbung

In jedem Bewerbungsordner sollen am Ende mindestens diese Dateien liegen:

- `Stellenbeschreibung.md`
- `Analyse.md`
- `Lebenslauf--FIRMA.html`
- `Anschreiben--FIRMA.html`
- `Email-Nachricht--FIRMA.md`
- `Qualitaetscheck.md`
- `Druck-Hinweis.md`

Optional:
- `Offene_Fragen.md`
- `Notizen.md`
- `PDF/`, falls später PDFs erzeugt werden

## Temporäre Dateien / Arbeitsdateien

Temporäre Entwürfe, Arbeitsnotizen, Zwischenergebnisse und nicht finale HTML-Dateien dürfen nicht direkt im Projektwurzelordner oder in öffentlichen Ordnern abgelegt werden.

Sie gehören immer in den passenden privaten Firmenordner:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/
```

Beispiel:

```text
Private/Bewerbungen/Muster-GmbH/_Arbeitsdateien/2026-06-30--Sachbearbeitung/
```

Der finale Bewerbungsordner bleibt:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/
```

Regel:
- finale Dateien in den finalen Bewerbungsordner
- temporäre Dateien in `_Arbeitsdateien`
- keine losen temporären Dateien direkt unter `Private/Bewerbungen/`
- keine generierten Bewerbungsdateien in öffentlichen Projektordnern

## Optionales Hilfsskript

Ein neuer Bewerbungsordner kann unter Windows 11 mit PowerShell vorbereitet werden:

```powershell
.\Tools\Neue-Bewerbung.ps1 -Firma "Muster GmbH" -Rolle "Sachbearbeitung"
```

Unter Linux mit Bash:

```bash
bash Tools/neue-bewerbung.sh --firma "Muster GmbH" --rolle "Sachbearbeitung"
```

Beide Skripte erstellen den Firmenordner, den finalen Bewerbungsordner sowie einen Arbeitsordner unter `_Arbeitsdateien`.

Platzhalter, Warnhinweise und Entwürfe der Hilfsskripte gehören ausschließlich in `_Arbeitsdateien`. Der finale Bewerbungsordner darf durch das Hilfsskript keine unfertigen `Analyse.md`, `Email-Nachricht--FIRMA.md`, `Qualitaetscheck.md` oder `Offene_Fragen.md` Platzhalter erhalten.

## Plattformregeln

- Projektinterne Pfade werden in der Dokumentation mit `/` geschrieben.
- Unter Windows darf PowerShell mit `\` arbeiten.
- Unter Linux darf Bash mit `/` arbeiten.
- Keine absoluten Betriebssystempfade fest in Prompts, Vorlagen oder finale Bewerbungsdateien schreiben.
- Wenn ein Ausgabeordner abweichend gewählt wird, muss er vom Nutzer oder Agenten bewusst angegeben werden.
- Die Windows- und Linux-Hilfsskripte müssen dieselbe Struktur erzeugen.

## Dateinamen-Regeln

- Keine Sonderzeichen außer Bindestrich.
- Keine Umlaute in Dateinamen.
- Leerzeichen durch Bindestriche ersetzen.
- Mehrere Bindestriche innerhalb von Firmen- oder Rollen-Slugs vermeiden.
- Der doppelte Bindestrich in `YYYY-MM-DD--ROLLENNAME`, `Lebenslauf--FIRMA.html` und `Anschreiben--FIRMA.html` ist als technischer Trenner ausdrücklich erlaubt.
- Namen kurz, lesbar und eindeutig halten.

## Finale-Dateien

Das Hilfsskript darf Arbeitsdateien mit Warnhinweisen nur unter `_Arbeitsdateien` erzeugen.
Der finale Bewerbungsordner darf erst nach Agentenprüfung finale Dateien ohne sichtbare Platzhalter enthalten.

Finale Bewerbungsdateien dürfen keine sichtbaren Arbeitsmarker enthalten:
- `[ergänzen]`
- `{{PLATZHALTER}}`
- `TODO`
- `DOKUMENT NOCH NICHT FINAL`

## Umwandlungsregeln

- `ä` zu `ae`
- `ö` zu `oe`
- `ü` zu `ue`
- `Ä` zu `Ae`
- `Ö` zu `Oe`
- `Ü` zu `Ue`
- `ß` zu `ss`
- `&` zu `und`
- `/` zu `-`
- Punkte in Firmennamen entfernen, außer sie sind notwendig

## Beispiele

```text
Beispiel GmbH
-> Private/Bewerbungen/Beispiel-GmbH/2026-06-30--Sachbearbeitung/
```

```text
Muster GmbH
-> Private/Bewerbungen/Muster-GmbH/2026-06-30--Kundenservice/
```

```text
Müller & Partner GmbH
-> Private/Bewerbungen/Mueller-und-Partner-GmbH/2026-06-30--Projektassistenz/
```