# Interaktiver Bewerbungsdialog – Testszenarien

Stand: 05.08.2026

Dieses Dokument beschreibt die neun verbindlichen Nutzerfälle für Umfangsauswahl, gezielte Profilrückfragen und kontrollierte Profilaktualisierung. Die fachliche Quelle ist [`Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md`](../Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md). Der sitzungsübergreifende Zustand liegt im `Bewerbungsauftrag.json` nach Schema 4; dieses Dokument führt keinen zweiten Dialog- oder Datenvertrag ein.

Automatisierte Vertrags- und Fixturetests werden mit folgendem Befehl ausgeführt:

```powershell
.\Tests\Run-RegressionTests.ps1
```

Sie prüfen deterministische Regeln, Dateizustände und Schutzgrenzen. Sie sind keine echte Modellsitzung. Alle Fixtures müssen ausschließlich fiktive Daten in einem temporären Testordner verwenden. Echte Daten oder Bewerbungen unter `Private/` dürfen weder gelesen noch verändert werden.

## Statusbegriffe

- **Automatisiert:** Der deterministische Vertrags- oder Dateizustand wird durch [`Run-RegressionTests.ps1`](Run-RegressionTests.ps1) geprüft.
- **Dokumentiert:** Das Dialogverhalten ist als reproduzierbares Szenario festgelegt, wurde aber nicht als echte Modellsitzung ausgeführt.
- **Realer Modelltest nicht ausgeführt:** Es wurde in diesem Auftrag kein Modell für diesen Fall gestartet; daraus darf kein bestandener Modelltest abgeleitet werden.

## Übersicht

| Nr. | Fall | Status |
| ---: | --- | --- |
| 1 | Unklarer Auftrag | automatisierter Auswahlvertrag; echter Dialog dokumentiert |
| 2 | Eindeutiger Auftrag | automatisierter Direktstartvertrag; echter Dialog dokumentiert |
| 3 | Bekannte Anforderungen | automatisierter Rückfragefilter-Vertrag; echter Dialog dokumentiert |
| 4 | Relevante Wissenslücke | automatisierter Rückfrage- und Speichervertrag; echter Dialog dokumentiert |
| 5 | Nur aktuelle Bewerbung | automatisierter Fixturetest |
| 6 | Dauerhafte Speicherung | automatisierter Fixturetest |
| 7 | Widerspruch | automatisierter Schutzvertrag; echter Dialog dokumentiert |
| 8 | Agentenneustart | automatisierter Fortsetzungsvertrag; echter Anbieterwechsel dokumentiert |
| 9 | Kleines lokales Modell | Fail-closed-Vertrag automatisiert; realer Modelltest nicht ausgeführt |

## Test 1 – Unklarer Auftrag

**Eingabe**

```text
Ich möchte mich auf diese Stelle bewerben.
```

**Erwarteter Dialogzustand**

- Der Agent fragt einmal nach dem gewünschten Bewerbungsumfang und bietet die Auswahl A bis E sowie eine freie Texteingabe an.
- Er legt nicht selbstständig eine Vollbewerbung fest.
- Vor einer eindeutigen Auswahl beginnt keine Dokumenterstellung.

**Erwarteter Dateizustand**

- Private Profildateien bleiben unverändert.
- Ohne eindeutig bestätigten Umfang wird kein neuer Schema-4-Auftrag und kein Kandidatendokument angelegt.
- Wird eine bestehende Bewerbung fortgesetzt, darf ihr bereits gültiger Umfang durch eine mehrdeutige Antwort nicht überschrieben werden; der offene Klärungsbedarf bleibt blockierend.

**Status:** Der Auswahl- und Nicht-Standardisierungsvertrag ist automatisiert; die natürlichsprachliche Modellsitzung ist dokumentiert.

## Test 2 – Eindeutiger Auftrag

**Eingabe**

```text
Erstelle nur ein Anschreiben.
```

**Erwarteter Dialogzustand**

- Der Agent wiederholt die Umfangsauswahl nicht.
- Er beginnt direkt mit dem für das Anschreiben notwendigen Profilabgleich.
- Lebenslauf oder E-Mail werden nicht stillschweigend zum gewünschten Umfang ergänzt.

**Erwarteter Dateizustand**

- `Bewerbungsauftrag.json` hat `schemaVersion` 4 und kennzeichnet ausschließlich das Anschreiben als ausgewählten neuen Bestandteil.
- Die Auswahlquelle ist der ausdrückliche Nutzerauftrag.
- Im Kandidatenordner werden nur die laut Umfang erforderlichen Dokumente erwartet.

**Status:** Der Direktstart- und Schema-4-Umfangsvertrag ist automatisiert; die echte Modellsitzung ist dokumentiert.

## Test 3 – Bekannte Anforderungen

**Ausgangslage**

Eine fiktive Stellenbeschreibung verlangt ausschließlich Kompetenzen, die das fiktive Testprofil bereits eindeutig und widerspruchsfrei belegt.

**Eingabe**

```text
Erstelle eine vollständige Bewerbung für diese fiktive Stelle. Gefordert werden React, Git und technische Dokumentation.
```

**Erwarteter Dialogzustand**

- Der Agent stellt keine Rückfrage nur um interaktiv zu wirken.
- Bereits gespeicherte oder im aktuellen Dialog bestätigte Angaben werden nicht erneut abgefragt.
- Der Zustand kann ohne offene Profilfrage zur Dokumenterstellung übergehen.

**Erwarteter Dateizustand**

- Das Testprofil bleibt unverändert.
- Der Schema-4-Auftrag enthält keine erfundene neue Nutzerangabe und keine unnötige offene Dialogfrage.
- Die Anforderungsmatrix verweist auf die bereits vorhandenen Belege.

**Status:** Der Rückfragefilter- und Keine-Dublette-Vertrag ist automatisiert; die sprachliche Qualität des Dialogs ist dokumentiert.

## Test 4 – Relevante Wissenslücke

**Ausgangslage und Eingabe**

Die fiktive Stelle verlangt TypeScript; im fiktiven Profil ist dazu keine Angabe vorhanden.

```text
Ich habe TypeScript in zwei privaten React-Projekten eingesetzt.
```

**Erwarteter Dialogzustand**

- Der Agent fragt gezielt nach TypeScript und bietet verständliche Erfahrungsarten sowie eine freie Antwort an.
- Freier Zusatztext wird ausgewertet und als private Projekterfahrung eingeordnet; er wird nicht nur auf einen Auswahlbuchstaben reduziert.
- Sind Niveau oder Kontext danach ausreichend klar, folgt keine weitere Frage.
- Vor einer dauerhaften Profiländerung folgt eine getrennte Speicherfrage.

**Erwarteter Dateizustand**

- Der Schema-4-Auftrag speichert nur die normalisierte, fachlich relevante Angabe und ihre Einordnung, kein vollständiges Chattranskript.
- Bis zur ausdrücklichen Speicherentscheidung gilt die Angabe für den aktuellen Auftrag; die Profildatei bleibt unverändert.
- Die betreffende Anforderung kann nach der Antwort auf den belegbaren Status aktualisiert werden, ohne daraus Berufserfahrung zu machen.

**Status:** Rückfrage, freie Antwort, wahrheitsgemäße Einordnung und Standardumfang „aktueller Auftrag“ sind als Verträge automatisiert; ein echter Dialog ist dokumentiert.

## Test 5 – Nur aktuelle Bewerbung

**Eingabe**

Nach der bestätigten TypeScript-Angabe antwortet der Nutzer:

```text
Nein, nur für diese Bewerbung verwenden.
```

**Erwarteter Dialogzustand**

- Der Agent bestätigt die auftragsbezogene Verwendung und fragt dieselbe Speicherentscheidung nicht erneut ab.
- Die Angabe darf in den ausgewählten Dokumenten dieser Bewerbung verwendet werden.
- Die verknüpfte Speicherfrage ist danach beantwortet und nicht mehr blockierend; ohne weitere offene Punkte lautet der Dialogstatus `bereit_zur_dokumenterstellung`.

**Erwarteter Dateizustand**

- Der SHA-256-Wert der fiktiven Profildatei ist vor und nach der Entscheidung identisch.
- Der Schema-4-Auftrag kennzeichnet die normalisierte Angabe eindeutig als nur für diesen Auftrag und die Profilaktualisierung als nicht durchgeführt.
- Eine spätere Bewerbung darf die Angabe nicht als dauerhaft bestätigtes Profilwissen übernehmen.

**Status:** Automatisierter Fixturetest mit unverändertem Profilhash und geprüftem Schema-4-Zustand.

## Test 6 – Dauerhafte Speicherung

**Eingabe**

Nach der bestätigten TypeScript-Angabe antwortet der Nutzer:

```text
Ja, dauerhaft übernehmen.
```

**Erwarteter Dialogzustand**

- Der Agent verwendet ausschließlich die zuvor transparent gemachte Formulierung.
- Falls für eine wahrheitsgemäße Einordnung noch ein notwendiges Detail fehlt, fragt er dieses vor dem Schreiben einmal gezielt ab.
- Nach erfolgreicher Änderung nennt er die tatsächlich geänderte Profildatei.

**Erwarteter Dateizustand**

- Ausschließlich die passende fiktive Profildatei wird an der fachlich zuständigen Stelle verändert.
- Datei, Abschnitt, fachlicher Zieltyp, exakter Formulierungsvorschlag und Ausgangshash sind bereits vor der Zustimmung im Pending-Snapshot gespeichert; abweichende Aufrufswerte werden abgelehnt.
- Die technische Übernahme dupliziert eine exakt bereits vorhandene bestätigte Formulierung nicht; die vorgelagerte semantische Dublettenprüfung bleibt Teil des dokumentierten Agentenvertrags.
- Der Schema-4-Auftrag protokolliert normalisierte Angabe, Einordnung, ausdrückliche Zustimmung, Zeitpunkt, Profildatei und erfolgreiche Aktualisierung.
- Andere Profilabschnitte und Dateien bleiben bytegleich; erneute identische Zustimmung erzeugt keine zweite Eintragung.
- Eine erstmalige Übernahme mit `dialog.status = dokumenterstellung` oder `abgeschlossen` scheitert, damit bestehende Folgeartefakte nicht stillschweigend veralten.

**Status:** Automatisierter Fixturetest für Zustimmung, Zieldatei, exakte Deduplizierung und begrenzte Änderung; die semantische Vorprüfung ist dokumentiert.

## Test 7 – Widerspruch

**Ausgangslage und Eingabe**

Im fiktiven Profil steht `TypeScript: Grundkenntnisse`. Der Nutzer erklärt anschließend, TypeScript regelmäßig in mehreren privaten Projekten einzusetzen.

**Erwarteter Dialogzustand**

- Der Agent macht den Widerspruch verständlich sichtbar und fragt nach der aktuell zutreffenden Einordnung.
- Die bestehende Aussage wird nicht stillschweigend ersetzt und die stärkere neue Aussage noch nicht in Dokumente übernommen.
- Eine freie Präzisierung bleibt zulässig.

**Erwarteter Dateizustand**

- Die Profildatei bleibt bis zur eindeutigen Bestätigung unverändert.
- Der Schema-4-Auftrag hält den Punkt als offen beziehungsweise widersprüchlich fest, ohne eine dauerhafte Zustimmung zu behaupten.
- Solange die Wahrheitsebene widersprüchlich oder unklar ist, wird noch keine Speicherentscheidung geöffnet.
- Erst die bestätigte Auflösung darf den auftragsbezogenen Zustand und gegebenenfalls das Profil aktualisieren.

**Status:** Der Nicht-Überschreiben- und offene-Zustand-Vertrag ist automatisiert; die echte Rückfrageformulierung ist dokumentiert.

## Test 8 – Agentenneustart

**Ablauf**

1. Ein fiktiver Nutzer wählt den Dokumentumfang und beantwortet eine relevante Profilfrage.
2. Die Sitzung endet vor der Dokumenterstellung.
3. Eine neue Agentensitzung erhält den Auftrag, die Bewerbung fortzusetzen.

**Eingabe in der neuen Sitzung**

```text
Setze die zuletzt begonnene Bewerbung fort.
```

**Erwarteter Dialogzustand**

- Der neue Agent rekonstruiert Umfang, beantwortete Fragen, ausschließlich auftragsbezogene Angaben, dauerhafte Profiländerungen, einen gegebenenfalls noch offenen Pending-Snapshot und noch offene Entscheidungen aus den Dateien.
- Bereits beantwortete Fragen werden nicht erneut gestellt.
- Eine noch offene Speicher- oder Widerspruchsentscheidung wird verständlich fortgesetzt.

**Erwarteter Dateizustand**

- `Bewerbungsauftrag.json` bleibt ein lesbarer und konsistenter Schema-4-Auftrag.
- Der gespeicherte Dialogzustand genügt zur Fortsetzung ohne Chat-Memory; `Arbeitsnotizen.md` darf ihn erklären, ersetzt ihn aber nicht.
- Kandidaten- oder Profildateien werden durch eine reine Standrekonstruktion nicht verändert.

**Status:** Die dateibasierte Zustandsrekonstruktion ist automatisiert; ein tatsächlicher Wechsel zwischen zwei Agentenanbietern ist dokumentiert und kein bestandener Modellsitzungstest.

## Test 9 – Kleines lokales Modell

**Ausgangslage**

Ein kleines lokales Modell ordnet eine kurze Auswahlantwort nicht eindeutig zu oder liefert einen widersprüchlichen Werkzeugvorschlag.

**Eingabe**

```text
A – wobei ich vielleicht doch nur ein Anschreiben möchte.
```

**Erwarteter Dialogzustand**

- Nur eine eindeutig interpretierte Auswahl darf den Umfang festlegen.
- Bei Mehrdeutigkeit fragt der Agent höchstens einmal in einfachem Text nach.
- Bleibt die Antwort unklar, stoppt er vor Dokumenterstellung und Profiländerung, statt einen Umfang oder eine Zustimmung zu erraten.

**Erwarteter Dateizustand**

- Ohne eindeutige Auswahl wird kein neuer Schema-4-Auftrag erzeugt; bei einem vorhandenen Auftrag bleibt der letzte gültige Umfang unverändert und der Dialogstatus blockierend.
- Keine Profildatei wird verändert und keine dauerhafte Zustimmung eingetragen.
- Bereits gültige Zustandsdaten werden durch eine fehlerhafte Modellinterpretation nicht überschrieben.

**Status:** Der Fail-closed-Vertrag für uneindeutige Auswahl und fehlende Zustimmung ist automatisiert. In diesem Auftrag wurde kein neuer realer Ollama-Modelllauf ausgeführt; der reale Modelltest ist daher **nicht ausgeführt** und nicht bestanden.

## Abnahmeregel

Die neun Szenarien gelten dokumentarisch nur dann als aktuell, wenn ihre Feld- und Statusaussagen mit Prompt 01 und dem implementierten Schema 4 übereinstimmen. Nach einer Änderung am Dialog- oder Auftragsvertrag müssen diese Datei und die zugehörigen Prüfungen in `Run-RegressionTests.ps1` gemeinsam aktualisiert werden. Ein bestandener deterministischer Test darf niemals als bestandene Sitzung mit Codex, OpenCode, Claude Code oder einem Ollama-Modell ausgegeben werden.
