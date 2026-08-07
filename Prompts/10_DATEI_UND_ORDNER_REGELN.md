# Datei- und Ordnerregeln

## Ziel

Für jede Bewerbung wird ein eigener privater Arbeitsordner erstellt.

Alle generierten Bewerbungsdateien liegen unter `Private/`, damit das Projekt ohne private Daten auf GitHub veröffentlicht werden kann.

## Öffentliche und private Bereiche

Öffentlich:

```text
AGENTS.md
CLAUDE.md
GEMINI.md
opencode.json
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

Empfohlene aktive Universalquelle:

```text
Private/LebenslaufUniversal/Aktiv/Lebenslauf - NACHNAME.VORNAME.html
```

Sie wird bei `dokumentumfang.lebenslauf = universal_unveraendert` per SHA-256 als unveränderter Snapshot eingebunden. Frühere Versionen gehören unter `Private/LebenslaufUniversal/Archiv/`.

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

## Umfangsabhängige Dateien pro Bewerbung

Jeder veröffentlichte Bewerbungsordner trennt Versand und interne Nachweise:

```text
YYYY-MM-DD--ROLLENNAME/
├─ Versand/
│  ├─ optional Lebenslauf - NACHNAME.VORNAME.pdf
│  ├─ optional Anschreiben - NACHNAME.VORNAME.pdf
│  └─ optional Email-Nachricht--FIRMA.md
├─ Intern/
│  ├─ Stellenbeschreibung.md
│  ├─ Analyse.md
│  ├─ optional Lebenslauf - NACHNAME.VORNAME.html
│  ├─ optional Anschreiben - NACHNAME.VORNAME.html
│  ├─ Qualitaetscheck.md
│  ├─ Druck-Hinweis.md
│  └─ optional Offene_Fragen.md
└─ Manifest.json
```

`Versand/` enthält ausschließlich die laut `dokumentumfang` ausgewählten PDF-Anlagen und gegebenenfalls den E-Mail-Text. `Intern/` enthält vorhandene HTML-Quellen und gemeinsame Nachweise, aber keine PDF-Dubletten. `Manifest.json` weist den Dokumentumfang und alle Dateien außer sich selbst mit relativem Pfad, Größe und SHA-256 nach.

Bei universellem Lebenslauf ist die PDF keine neu geschriebene Stellenfassung, sondern die frisch gerenderte, inhaltlich unveränderte Universalquelle.

Eine Stellenanzeige, die eine Bewerbung „in Form einer PDF-Datei“ verlangt, legt das Datenformat fest. Sie ändert die nutzerseitige Umfangsauswahl nicht und verlangt nur bei eindeutiger Formulierung eine zusammengeführte Datei.

Wenn ein HTML-Kandidat wegen Drucklayout, A4-Fit oder Recruiter-Design überarbeitet wird, bleibt der geplante finale Dateiname gleich. Die Änderung macht vorhandene Layout- und PDF-Nachweise ungültig und erfordert eine neue Finalisierungsvorbereitung. Bereits veröffentlichte Bewerbungen dürfen nur über einen erneut vollständig geprüften Kandidatensatz ersetzt werden.

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

Versandfertig benannte, aber noch nicht freigegebene Kandidatendateien liegen unter:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat/
```

Der Kandidatenordner verwendet für ausgewählte Dokumente bereits die späteren finalen Dateinamen. Er ist trotzdem kein Versandordner. `Bewerbungsauftrag.json` enthält zusätzlich den normalisierten Dialogzustand; Rohchat und unnötige sensible Details werden dort nicht gespeichert. Der finale Zielordner bleibt bis zur atomaren Veröffentlichung leer.

Der standardisierte Nutzungsbericht liegt ausschließlich im zugehörigen Arbeitsordner:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Tokenverbrauch.json
```

Er ist ein nicht blockierendes Diagnose- und Kostenartefakt, kein Qualitätsnachweis und keine Kandidatendatei. Er gehört weder nach `Versand/` noch nach `Intern/` und wird standardmäßig nicht in `Manifest.json` aufgenommen. Er darf keine API-Schlüssel, Zugangsdaten, vollständigen Prompts oder privaten Bewerbungsinhalte enthalten.

Regel:
- Entwürfe und Kandidatendateien in `_Arbeitsdateien`
- finale Dateien ausschließlich durch `Tools/Finalisiere-Bewerbung.ps1` veröffentlichen
- keine losen temporären Dateien direkt unter `Private/Bewerbungen/`
- keine generierten Bewerbungsdateien in öffentlichen Projektordnern

## Optionales Hilfsskript

Ein neuer Bewerbungsordner kann unter Windows 11 mit PowerShell vorbereitet werden:

```powershell
.\Tools\Neue-Bewerbung.ps1 -Firma "Muster GmbH" -Rolle "Sachbearbeitung" -UmfangAuswahl A
```

Unter Linux mit Bash:

```bash
bash Tools/neue-bewerbung.sh --firma "Muster GmbH" --rolle "Sachbearbeitung" --umfang A
```

Beide Skripte erstellen den Firmenordner, einen zunächst leeren finalen Bewerbungsordner, einen Arbeitsordner unter `_Arbeitsdateien`, den Unterordner `Kandidat/`, `Bewerbungsauftrag.json` und einen Entwurf der Anforderungsmatrix.

Die Skripte benötigen einen ausdrücklich geklärten Umfang A–E. Bei E werden die ausgewählten Bestandteile zusätzlich übergeben. Ein universeller Lebenslauf benötigt seine freigegebene HTML-Quelle; sie wird hashgleich übernommen. Für abgewählte Dokumente entstehen keine Entwürfe.

Existiert die bereinigte Kombination aus Firma, Datum und Rolle bereits, müssen beide Skripte standardmäßig abbrechen. Eine vorhandene Bewerbung darf nur mit `-Fortsetzen` unter PowerShell beziehungsweise `--fortsetzen` unter Bash ergänzt werden, wenn Ziel- und Arbeitsordner vollständig vorhanden sind und `Arbeitsnotizen.md` exakt dieselbe Firma und Zielrolle bestätigt. Eine abweichende vorhandene `Stellenbeschreibung.md` darf nie überschrieben werden.

Platzhalter, Warnhinweise und Entwürfe der Hilfsskripte gehören ausschließlich in `_Arbeitsdateien`. Stellenbeschreibung und Druckhinweis dürfen bereits im Kandidatenordner liegen. Der finale Bewerbungsordner bleibt durch das Hilfsskript vollständig leer.

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
- Pflichtschema für jeweils ausgewählte finale HTML-Dateien: `Lebenslauf - NACHNAME.VORNAME.html` beziehungsweise `Anschreiben - NACHNAME.VORNAME.html`.
- Pflichtschema für jeweils erzeugte PDF-Dateien: `Lebenslauf - NACHNAME.VORNAME.pdf` beziehungsweise `Anschreiben - NACHNAME.VORNAME.pdf`.
- In finalen Versanddateien sind Leerzeichen um den Bindestrich und der Punkt zwischen Nachname und Vorname ausdrücklich erlaubt.
- `NACHNAME.VORNAME` kommt aus `Private/Daten/01_PERSOENLICHE_DATEN.md`.
- Umlaute und Sonderzeichen im Bewerbernamen werden dateisicher umgewandelt, z. B. `ä` zu `ae`, `ß` zu `ss`; Schrägstriche und andere Pfadzeichen sind verboten.
- Wenn Vorname oder Nachname fehlen oder uneindeutig sind, keine finale Datei mit Platzhalter erzeugen; stattdessen in `Offene_Fragen.md` dokumentieren oder nachfragen.
- Interne Entwurfsdateien dürfen weiterhin technische Namen mit Firma oder `ENTWURF` verwenden, weil sie nicht versendet werden.

## Finale-Dateien

Das Hilfsskript darf Arbeitsdateien mit Warnhinweisen nur unter `_Arbeitsdateien` erzeugen.
Der finale Bewerbungsordner darf erst nach Dialogstatus-, Stammdaten-, Inhalts- und Strukturprüfung veröffentlicht werden. Browser-, PDF- und ATS-Prüfung gelten für jedes ausgewählte HTML-Dokument; bei einem bestätigten reinen E-Mail-Auftrag werden sie maschinenlesbar als `nicht_erforderlich` ausgewiesen und die E-Mail muss persönlich textlich geprüft werden. Die Veröffentlichung erfolgt als vollständiges strukturiertes Set und nicht durch einzelne Kopiervorgänge des Agenten.

Finale HTML-Dateien müssen außerdem druckstabil sein:

- Einseiten-Dokumente dürfen im verbindlichen Chrome-/Edge-Export bei 100 Prozent Skalierung keine zweite Seite erzeugen.
- Zweiseitige Dokumente müssen bewusst zwei A4-Seitencontainer enthalten.
- Drucklayout-Korrekturen werden an der HTML-Datei im Kandidatenordner vorgenommen. Danach müssen Layout- und PDF-Nachweise wegen der Hashbindung neu erzeugt werden.

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
