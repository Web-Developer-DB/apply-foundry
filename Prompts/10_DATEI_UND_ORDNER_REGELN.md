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
Private/Daten/Passfoto.png   # optional, nur für individuelle Lebensläufe
Private/Bewerbungen/
Private/Bewertungen/
Private/Archiv/
```

Eigenständiger Universal-Lebenslauf:

```text
Private/Bewerbungen/_Universal-Lebenslauf/
├─ _Arbeitsdateien/
│  └─ YYYY-MM-DD--Softwareentwicklung/
│     ├─ Universalauftrag.json
│     ├─ Kandidat/
│     ├─ Layoutcheck/
│     └─ PDF-Export/
└─ Aktiv/
   ├─ Versand/Lebenslauf - NACHNAME.VORNAME.pdf
   ├─ Intern/Lebenslauf - NACHNAME.VORNAME.html
   └─ Manifest.json
```

Die aktive HTML-Datei wird bei `dokumentumfang.lebenslauf = universal_unveraendert` per SHA-256 als unveränderter Snapshot eingebunden. `Aktiv/` entsteht erst nach technischem Check und persönlicher Sichtprüfung. Nach erfolgreicher Aktivierung wird der genau zugehörige datierte Arbeitsordner vollständig gelöscht; im aktiven Paket bleiben ausschließlich HTML, Versand-PDF und deren Manifest. Eine frühere `Private/LebenslaufUniversal/`-Quelle darf nur noch als ausdrücklich angegebene unveränderte Legacy-Quelle gelesen werden und ist kein Ziel für neue Dateien.

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

`Passfoto.png` bleibt immer unter `Private/Daten/` und wird nie als eigenständige Kandidaten- oder Versanddatei kopiert. Bei einem individuellen Lebenslauf darf ausschließlich seine bytegleiche Base64-Einbettung im privaten HTML und im daraus erzeugten PDF erscheinen. Der Finalisierungs- und Manifestnachweis führt `passfoto` nur bei tatsächlich vorhandener und verwendeter Quelle.

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

Neue Aufträge verwenden Schema 5 mit `pfadModus = relativ_zu_bewerbungen_root`. `zielOrdner`, `arbeitsOrdner` und `kandidatOrdner` enthalten ausschließlich `/`-normalisierte relative Pfade. Absolute Pfade, Steuerzeichen, leere Segmente, `.` und `..` sind unzulässig. Leser rekonstruieren diese Pfade aus dem ausdrücklich übergebenen `BewerbungenRoot` oder dem validierten Arbeitsordner, prüfen symlinksicher das Containment und gleichen Firma, Rolle, Datum und Slugs mit der erwarteten Struktur ab. Nicht vorhandene Ziele werden über ihren real aufgelösten vorhandenen Elternordner validiert. Aufträge der Schemata 1 bis 4 bleiben ohne automatische Umschreibung auf ihrem bisherigen System lesbar.

Der standardisierte Nutzungsbericht liegt ausschließlich im zugehörigen Arbeitsordner:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Tokenverbrauch.json
```

Er ist ein nicht blockierendes Diagnose- und Kostenartefakt, kein Qualitätsnachweis und keine Kandidatendatei. Er gehört weder nach `Versand/` noch nach `Intern/` und wird standardmäßig nicht in `Manifest.json` aufgenommen. Er darf keine API-Schlüssel, Zugangsdaten, vollständigen Prompts oder privaten Bewerbungsinhalte enthalten.

Der kompakte Fortsetzungsnachweis liegt daneben im selben Arbeitsordner:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Workflow-Checkpoint.json
```

Er wird über `bewerbung.ps1 checkpoint` aktualisiert, enthält nur Schrittstatus sowie relative Pfade, Größen und SHA-256-Werte der vorhandenen Arbeitsartefakte und ist auf 24 Historieneinträge begrenzt. Rohchat, vollständige Quellen und Bewerberprofilkopien sind verboten. Der Checkpoint ist keine neue fachliche Stammquelle, kein Freigabenachweis und gehört weder nach `Versand/` noch standardmäßig in `Manifest.json`.

Regel:
- Entwürfe und Kandidatendateien in `_Arbeitsdateien`
- finale Dateien ausschließlich durch `Tools/Finalisiere-Bewerbung.ps1` veröffentlichen
- keine losen temporären Dateien direkt unter `Private/Bewerbungen/`
- keine generierten Bewerbungsdateien in öffentlichen Projektordnern

## Optionales Hilfsskript

Ein neuer Bewerbungsordner wird unter Windows mit dem gemeinsamen PowerShell-Dispatcher vorbereitet:

```powershell
pwsh -NoProfile -File Tools/bewerbung.ps1 neu --firma "Muster GmbH" --rolle "Sachbearbeitung" --umfang A
```

Unter Linux mit Bash:

```bash
./Tools/bewerbung.sh neu --firma "Muster GmbH" --rolle "Sachbearbeitung" --umfang A
```

Beide Einstiege führen dieselbe PowerShell-7.6-Implementierung aus. Sie erstellen den Firmenordner, einen zunächst leeren finalen Bewerbungsordner, einen Arbeitsordner unter `_Arbeitsdateien`, den Unterordner `Kandidat/`, einen portablen Schema-5-`Bewerbungsauftrag.json` und einen Entwurf der Anforderungsmatrix. `Tools/neue-bewerbung.sh` bleibt nur als kompatibler Alias für `bewerbung.sh neu` erhalten.

Die Skripte benötigen einen ausdrücklich geklärten Umfang A–E. Bei E werden die ausgewählten Bestandteile zusätzlich übergeben. Ein universeller Lebenslauf benötigt seine freigegebene HTML-Quelle; sie wird hashgleich übernommen. Für abgewählte Dokumente entstehen keine Entwürfe.

Existiert die bereinigte Kombination aus Firma, Datum und Rolle bereits, muss der Dispatcher standardmäßig abbrechen. Eine vorhandene Bewerbung darf nur mit `--fortsetzen` ergänzt werden, wenn Ziel- und Arbeitsordner vollständig vorhanden sind und `Arbeitsnotizen.md` exakt dieselbe Firma und Zielrolle bestätigt. Direkte Legacy-Aufrufe von `Neue-Bewerbung.ps1` mit `-Fortsetzen` bleiben unterstützt. Eine abweichende vorhandene `Stellenbeschreibung.md` darf nie überschrieben werden.

Platzhalter, Warnhinweise und Entwürfe der Hilfsskripte gehören ausschließlich in `_Arbeitsdateien`. Stellenbeschreibung und Druckhinweis dürfen bereits im Kandidatenordner liegen. Der finale Bewerbungsordner bleibt durch das Hilfsskript vollständig leer.

Browserprofile, isolierte Capture-HTMLs, Staging- und Backup-Verzeichnisse sind technische Laufzeitdaten. Sie werden nach Erfolg und nach kontrollierten Fehlerpfaden mit begrenzten Wiederholungsversuchen entfernt. Leere globale `.browser-tmp`-Wurzeln dürfen nach dem Lauf nicht bestehen bleiben.

## Plattformregeln

- Projektinterne Pfade werden in der Dokumentation mit `/` geschrieben.
- PowerShell darf intern native Trennzeichen verwenden; Schema-5-Pfade werden immer mit `/` relativ zu `BewerbungenRoot` gespeichert.
- Bash löst ausschließlich Skript- und Runtimepfad auf und reicht Argumente unverändert weiter.
- Keine absoluten Betriebssystempfade fest in Prompts, Vorlagen oder finale Bewerbungsdateien schreiben.
- Wenn ein Ausgabeordner abweichend gewählt wird, muss er vom Nutzer oder Agenten bewusst angegeben werden.
- Windows- und Linux-Einstieg müssen durch dieselbe Kernimplementierung dieselbe Struktur und Semantik erzeugen.
- Pfadvergleiche sind unter Windows case-insensitiv und unter Linux case-sensitiv; Slug-/Case-Kollisionen müssen fehlergeschlossen enden.
- Layout-, PDF-, ATS- und Finalisierungsberichte binden den Lauf mit einem Runtime-Fingerprint. Nach einem Betriebssystemwechsel bleiben Auftrag und Kandidaten erhalten, die technischen Nachweise gelten jedoch als veraltet und müssen neu erzeugt werden.

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

- Einseiten-Dokumente dürfen im verbindlichen Chrome-/Edge-/Chromium-Export bei 100 Prozent Skalierung keine zweite Seite erzeugen.
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
