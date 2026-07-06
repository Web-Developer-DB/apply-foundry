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
- `Lebenslauf - NACHNAME.VORNAME.html`
- `Anschreiben - NACHNAME.VORNAME.html`
- `Email-Nachricht--FIRMA.md`
- `Qualitaetscheck.md`
- `Druck-Hinweis.md`

Optional:
- `Offene_Fragen.md`
- `Notizen.md`
- PDF-Dateien mit demselben Namen wie die finalen HTML-Dateien, falls später PDFs erzeugt werden

Wenn ein HTML-Dokument nachträglich wegen Drucklayout, A4-Fit oder Recruiter-Design überarbeitet wird, bleibt der finale Dateiname gleich. Alte Entwurfsvarianten gehören nur in den passenden `_Arbeitsdateien`-Ordner und nicht neben die finale Versanddatei.

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

- Ordner-Slugs für Firma und Rolle bleiben technisch sauber: keine Umlaute, Leerzeichen durch Bindestriche, mehrere Bindestriche vermeiden.
- Finale Versanddateien für Lebenslauf und Anschreiben nutzen Bewerbername statt Firma.
- Pflichtschema für finale HTML-Dateien: `Lebenslauf - NACHNAME.VORNAME.html` und `Anschreiben - NACHNAME.VORNAME.html`.
- Pflichtschema für finale PDF-Dateien, falls erzeugt: `Lebenslauf - NACHNAME.VORNAME.pdf` und `Anschreiben - NACHNAME.VORNAME.pdf`.
- In finalen Versanddateien sind Leerzeichen um den Bindestrich und der Punkt zwischen Nachname und Vorname ausdrücklich erlaubt.
- `NACHNAME.VORNAME` kommt aus `Private/Daten/01_PERSOENLICHE_DATEN.md`.
- Umlaute und Sonderzeichen im Bewerbernamen werden dateisicher umgewandelt, z. B. `ä` zu `ae`, `ß` zu `ss`; Schrägstriche und andere Pfadzeichen sind verboten.
- Wenn Vorname oder Nachname fehlen oder uneindeutig sind, keine finale Datei mit Platzhalter erzeugen; stattdessen in `Offene_Fragen.md` dokumentieren oder nachfragen.
- Interne Entwurfsdateien dürfen weiterhin technische Namen mit Firma oder `ENTWURF` verwenden, weil sie nicht versendet werden.

## Finale-Dateien

Das Hilfsskript darf Arbeitsdateien mit Warnhinweisen nur unter `_Arbeitsdateien` erzeugen.
Der finale Bewerbungsordner darf erst nach Agentenprüfung finale Dateien ohne sichtbare Platzhalter enthalten.

Finale HTML-Dateien müssen außerdem druckstabil sein:

- Einseiten-Dokumente dürfen in Firefox bei 100 Prozent Skalierung keine zweite Seite erzeugen.
- Zweiseitige Dokumente müssen bewusst zwei A4-Seitencontainer enthalten.
- Drucklayout-Korrekturen werden direkt an der finalen HTML-Datei vorgenommen und anschließend im `Qualitaetscheck.md` dokumentiert.

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
