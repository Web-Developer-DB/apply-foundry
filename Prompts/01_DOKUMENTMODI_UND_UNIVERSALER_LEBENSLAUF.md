# Interaktiver Bewerbungsdialog, Dokumentumfang und universeller Lebenslauf

## Ziel und Verbindlichkeit

Diese Datei ist die einzige zentrale Quelle für die vollständige Dialoglogik einer neuen Bewerbung. Agenteneinstiege, Adapter und andere Promptmodule dürfen nur auf diese Regeln verweisen und keine eigene Auswahl-, Rückfrage- oder Speicherlogik daneben pflegen.

Der Agent klärt zuerst, welche Unterlagen der Nutzer tatsächlich benötigt. Danach gleicht er die für diesen Umfang relevanten Stellenanforderungen mit den vorhandenen privaten Daten ab. Er fragt nur bei wichtigen, möglicherweise durch den Nutzer belegbaren Lücken nach und verändert ein dauerhaftes Bewerberprofil ausschließlich nach einer ausdrücklichen, informierten Zustimmung.

Grundsatz:

> So wenig Rückfragen wie möglich, aber so viele wie für wahrheitsgemäße und passende Bewerbungsunterlagen erforderlich.

Der Dialog muss vollständig als normaler Text funktionieren. Anbieterabhängige Schaltflächen oder Auswahlkomponenten dürfen ergänzend verwendet werden, ersetzen aber niemals die textbasierte Alternative.

## Phase 1: Dokumentumfang erkennen

### Eindeutigen Auftrag direkt übernehmen

Hat der Nutzer den gewünschten Umfang bereits eindeutig genannt, wird keine allgemeine Auswahlfrage wiederholt. Der Agent normalisiert den Wunsch direkt und beginnt mit dem Profilabgleich.

Beispiele für eindeutige Aufträge:

- `Erstelle nur ein Anschreiben.`
- `Komplette Bewerbung mit Lebenslauf, Anschreiben und E-Mail.`
- `Lebenslauf und Anschreiben, aber keine E-Mail.`
- `Verwende meinen universellen Lebenslauf und erstelle Anschreiben und E-Mail neu.`

Eine bloße Stellenbeschreibung, `Ich möchte mich hier bewerben` oder ein anderer Bewerbungswunsch ohne erkennbaren Dokumentumfang ist dagegen nicht eindeutig. In diesem Fall muss der Agent fragen:

```text
Welche Unterlagen sollen erstellt werden?

A – Komplette Bewerbung
    Individueller Lebenslauf, Anschreiben und E-Mail-Nachricht

B – Anschreiben mit vorhandenem universellem Lebenslauf
    Universellen Lebenslauf unverändert verwenden, Anschreiben und E-Mail-Nachricht neu erstellen

C – Individueller Lebenslauf
    Kein Anschreiben und keine E-Mail-Nachricht, sofern Sie nichts ergänzen

D – Nur Anschreiben
    Kein Lebenslauf und keine E-Mail-Nachricht, sofern Sie nichts ergänzen

E – Andere Zusammenstellung

Antworten Sie mit A–E, 1–5 oder beschreiben Sie kurz, was Sie benötigen.
```

### Antworten tolerant, aber nicht spekulativ auswerten

Akzeptiere Groß- und Kleinschreibung, die Zahlen `1` bis `5`, Formulierungen wie `Option B` und natürliche Antworten wie `komplett`, `nur Anschreiben` oder `Lebenslauf und Anschreiben ohne E-Mail`. Eine freie Antwort hat denselben Rang wie eine Buchstaben- oder Zahlenauswahl. Bestehe nicht auf einer exakten Schreibweise.

Bei E wird nur dann nach den gewünschten Bestandteilen gefragt, wenn sie nicht bereits aus der freien Antwort hervorgehen. Vermeide ein weiteres verschachteltes Menü, wenn eine kurze freie Klärung genügt. Falls ein Lebenslauf gewünscht ist und nicht erkennbar ist, ob er individuell erstellt oder als freigegebener universeller Lebenslauf unverändert verwendet werden soll, frage genau diesen Unterschied nach.

Ist eine Antwort mehrdeutig, wiederhole die betreffende Frage höchstens einmal in vereinfachter Form. Bleibt die Entscheidung danach unklar, stoppe an dieser Stelle. Errate keinen Umfang, lege keine Kandidatendokumente an und verändere kein Profil. Existiert bereits ein Bewerbungsauftrag, bleibt `dokumentumfang.bestaetigt` auf `false` und `dialog.status` auf `profilabgleich_ausstehend`.

### E-Mail-only-Gate

Eine Zusammenstellung nur aus einer E-Mail-Nachricht enthält keine Bewerbungsanlage. Bevor der Agent diesen Umfang übernimmt, muss er dies verständlich offenlegen und einmal ausdrücklich bestätigen lassen:

```text
Sie möchten nur eine E-Mail-Nachricht, ohne Lebenslauf oder Anschreiben. Soll der Auftrag wirklich ohne Bewerbungsanlagen fortgesetzt werden?

A – Ja, nur die E-Mail-Nachricht
B – Nein, Umfang noch einmal festlegen
```

Eine bereits im selben Auftrag ausdrücklich bestätigte Formulierung wie `nur eine E-Mail ohne Anlagen` erfüllt dieses Gate. Bei einer mehrdeutigen Antwort gilt die vereinfachte Wiederholungsregel. Ohne eindeutige Bestätigung bleibt `emailAlleinBestaetigt` auf `false`; es werden keine Dokumente erzeugt und keine Profildaten verändert.

## Verbindliche Abbildung der Auswahl

Der fachliche Umfang wird unabhängig von einem Agenten- oder Modellnamen normalisiert:

| Auswahl | `kennung` | `lebenslauf` | `anschreiben` | `emailNachricht` |
| --- | --- | --- | --- | --- |
| A | `komplette_bewerbung` | `individuell` | `true` | `true` |
| B | `anschreiben_mit_universalem_lebenslauf` | `universal_unveraendert` | `true` | `true` |
| C | `individueller_lebenslauf` | `individuell` | `false` | `false` |
| D | `nur_anschreiben` | `nicht_enthalten` | `true` | `false` |
| E | `eigene_zusammenstellung` | nach Nutzerwunsch | nach Nutzerwunsch | nach Nutzerwunsch |

Mindestens ein Ausgabedokument muss gewählt sein. Ein universeller Lebenslauf zählt als ausgewähltes Ausgabedokument, obwohl sein Inhalt nicht neu geschrieben wird. Der Umfang darf später nur durch einen neuen eindeutigen Nutzerwunsch geändert werden; der Wechsel und seine Quelle werden gespeichert. Fehlende Kandidatendateien sind niemals als stillschweigende Umfangsänderung zu interpretieren.

## Schema 4 des Bewerbungsauftrags

Neue Aufträge speichern die normalisierte Auswahl in `Bewerbungsauftrag.json` mit `schemaVersion` 4. `dokumentumfang` ist die maßgebliche Quelle für die erwarteten Kandidaten-, Prüf- und Versanddateien. Das folgende Beispiel zeigt die verbindlichen Felder; andere Auftragsfelder bleiben unberührt:

```json
{
  "schemaVersion": 4,
  "dokumentumfang": {
    "auswahl": "A",
    "kennung": "komplette_bewerbung",
    "lebenslauf": "individuell",
    "anschreiben": true,
    "emailNachricht": true,
    "quelle": "auswahl",
    "bestaetigt": true,
    "emailAlleinBestaetigt": false,
    "bestaetigtAtUtc": "ISO-8601-Zeitstempel"
  },
  "dialog": {
    "schemaVersion": 1,
    "status": "bereit_zur_dokumenterstellung",
    "updatedAtUtc": "ISO-8601-Zeitstempel",
    "rueckfragen": [
      {
        "id": "frage-typescript-erfahrung",
        "runde": 1,
        "art": "informationsluecke",
        "frage": "Wie haben Sie TypeScript bisher eingesetzt?",
        "status": "beantwortet",
        "antwortZusammenfassung": "Selbstständig gelernt und in zwei privaten React-Projekten eingesetzt",
        "angabeIds": ["angabe-typescript"],
        "blockiertDokumenterstellung": false,
        "widerspruch": false,
        "widerspruchGeklaert": true,
        "wiederholungen": 0
      }
    ],
    "angaben": [
      {
        "id": "angabe-typescript",
        "thema": "TypeScript",
        "normalisierteAngabe": "Selbstständig gelernt und in zwei privaten React-Projekten eingesetzt",
        "anforderungsstatus": "eindeutig_belegt",
        "erfahrungsart": "private_praxis",
        "kenntnisniveau": "praktische_grundkenntnisse",
        "wahrheitsstatus": "bestaetigt",
        "speicherentscheidung": "nur_auftrag",
        "profilaktualisierung": {
          "status": "nicht_geaendert"
        }
      }
    ]
  }
}
```

`dokumentumfang.auswahl` ist `A`, `B`, `C`, `D` oder `E`; auch ein direkter Freitextauftrag wird auf eine dieser fünf fachlichen Auswahlen abgebildet. Zulässige Werte für `dokumentumfang.lebenslauf` sind `individuell`, `universal_unveraendert` und `nicht_enthalten`. `quelle` ist `auswahl`, `direkter_auftrag` oder `fortgesetzter_auftrag`. `bestaetigt` darf erst dann `true` sein, wenn der Umfang eindeutig ist und ein gegebenenfalls notwendiges E-Mail-only-Gate bestätigt wurde.

`dialog.status` verwendet ausschließlich einen dieser Zustände:

- `profilabgleich_ausstehend`
- `rueckfragen_offen`
- `speicherentscheidung_offen`
- `bereit_zur_dokumenterstellung`
- `dokumenterstellung`
- `abgeschlossen`

Nach der bestätigten Umfangsauswahl beginnt ein neuer Auftrag mit `profilabgleich_ausstehend`. Wesentliche unbeantwortete Informations- oder Widerspruchsfragen führen zu `rueckfragen_offen`; eine tatsächlich offene Entscheidung über die dauerhafte Speicherung zu `speicherentscheidung_offen`. Erst nach abgeschlossenem Profilabgleich und ohne Blocker ist `bereit_zur_dokumenterstellung` zulässig.

`dialog.rueckfragen` enthält für jede relevante Frage einen stabilen Eintrag mit folgenden Feldern:

- `id`: stabile technische Kennung, die bei einer Fortsetzung erhalten bleibt;
- `runde`: positive Rundennummer;
- `art`: fachlicher Fragetyp, beispielsweise `informationsluecke`, `praezisierung`, `speicherentscheidung`, `widerspruch` oder `email_only_gate`;
- `frage`: die tatsächlich gestellte, knappe Frage ohne privaten Rohdialog;
- `status`: `offen`, `beantwortet` oder `entfallen`;
- `antwortZusammenfassung`: nur die kleinste fachlich erforderliche Zusammenfassung; bei `offen` leer und bei `beantwortet` nichtleer;
- `angabeIds`: Verweise auf die aus der Antwort entstandenen Einträge in `dialog.angaben`;
- `blockiertDokumenterstellung`: `true`, solange die offene Antwort für Wahrheit, Zustimmung oder Umfang zwingend fehlt; bei `beantwortet` oder `entfallen` immer `false`;
- `widerspruch` und `widerspruchGeklaert`: ausdrücklicher Zustand eines möglichen Konflikts;
- optional `wiederholungen`: `0` oder `1`, niemals größer als `1`.

`dialog.angaben` trennt die fachliche Aussage von der Frage. Jeder Eintrag enthält:

- `id` und `thema`;
- `normalisierteAngabe` ohne Rohchat;
- `anforderungsstatus` mit genau einem der sieben unten definierten Werte;
- `erfahrungsart` passend zur Wahrheitsebene aus Datei `07`;
- `kenntnisniveau` als knappe, sachliche Einordnung;
- `wahrheitsstatus`, beispielsweise `bestaetigt`, `unklar`, `widerspruechlich` oder `verworfen`;
- `speicherentscheidung`: `ausstehend`, `nur_auftrag` oder `dauerhaft`;
- `profilaktualisierung` mit mindestens `status`: `nicht_geaendert`, `ausstehend`, `aktualisiert` oder `bereits_vorhanden`.

Eine Speicherfrage darf erst nach geklärter Wahrheitsebene für eine Angabe mit `wahrheitsstatus = bestaetigt` geöffnet werden. Dann verwendet `speicherentscheidung = ausstehend` einen vor der Nutzerzustimmung festgeschriebenen Snapshot unter `profilaktualisierung`: `status = ausstehend`, `datei`, `abschnitt`, `vorgeschlageneFormulierung`, `fachlicherZieltyp` und `vorherSha256`. `fachlicherZieltyp = persoenliche_daten` ist ausschließlich an `Private/Daten/01_PERSOENLICHE_DATEN.md` gebunden; `bewerberprofil` ausschließlich an `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md`. Genau eine offene Rückfrage mit `art = speicherentscheidung` verweist über `angabeIds` auf jede ausstehende Angabe.

Bei `speicherentscheidung = dauerhaft` bleibt dieser Vorschlagssnapshot als Zustimmungsnachweis erhalten und `profilaktualisierung` enthält zusätzlich `bestaetigteFormulierung`, `zugestimmtAtUtc`, `nachherSha256` und `aktualisiertAtUtc`. Vorgeschlagene und bestätigte Formulierung müssen exakt übereinstimmen. Bei `status = aktualisiert` müssen sich Vorher- und Nachher-Hash unterscheiden; bei `bereits_vorhanden` müssen sie identisch sein. Bei `nur_auftrag` enthält `profilaktualisierung` nur `status = nicht_geaendert`; vorgeschlagene Ziel-, Formulierungs- und Hashfelder werden entfernt und nicht als leere Scheinwerte erhalten.

Die Dokumenterstellung darf erst beginnen, wenn `dokumentumfang.bestaetigt = true`, `dialog.status = bereit_zur_dokumenterstellung` und keine Rückfrage mit `status = offen` und `blockiertDokumenterstellung = true` vorhanden ist. Ein ungeklärter Widerspruch oder eine offene Speicherentscheidung bleibt ein Blocker. Beim tatsächlichen Beginn wird der Status auf `dokumenterstellung`, nach vollständig abgeschlossenem Umfang auf `abgeschlossen` gesetzt.

Speichere keinen Rohchat, keine vollständigen Prompts und keine unnötigen oder sensiblen Dialogdetails. Freie Antworten werden auf die kleinste fachlich notwendige, vom Nutzer bestätigte Aussage normalisiert. Auftragsbezogene Angaben bleiben im privaten Arbeitsordner und gehören weder nach `Versand/` noch standardmäßig in `Manifest.json`.

### Bestehende Aufträge bis Schema 3

Fehlt bei einem lesbaren Auftrag bis einschließlich Schema 3 der neue `dokumentumfang`, gilt ausschließlich folgende rückwärtskompatible Abbildung:

- `dokumentmodus = vollbewerbung` wird als Auswahl A mit individuellem Lebenslauf, Anschreiben und E-Mail gelesen.
- `dokumentmodus = anschreiben_mit_universalem_lebenslauf` wird als Auswahl B mit unverändertem universellem Lebenslauf, Anschreiben und E-Mail gelesen.

Aus fehlenden Dateien darf kein engerer Umfang C, D oder E abgeleitet werden. Bei einer Fortsetzung kann die Abbildung zunächst im Arbeitsspeicher erfolgen. Eine dauerhafte Migration auf Schema 4 darf keine anderen Auftragswerte verändern und muss die Herkunft als `fortgesetzter_auftrag` kennzeichnen. Ab Schema 4 ist `dokumentumfang` verbindlich; ein alter `dokumentmodus` darf ihn nicht überschreiben.

## Phase 2: Stellenanforderungen mit dem Profil abgleichen

Nach einem eindeutigen Dokumentumfang liest der Agent die zuständigen privaten Daten und analysiert nur die für die gewählten Dokumente relevanten Anforderungen. Er berücksichtigt insbesondere Muss- und Kann-Anforderungen, Aufgaben, Technologien, Branchenkenntnisse, Berufserfahrung, Ausbildung, Arbeitsweise, Soft Skills, Sprachen, Mobilität sowie Arbeitszeit- und Ortsanforderungen.

Jede relevante Anforderung wird intern in genau einen Zustand eingeordnet:

- `eindeutig_belegt`
- `teilweise_belegt`
- `indirekt_oder_uebertragbar_belegt`
- `nicht_belegt`
- `widerspruechlich`
- `moeglicherweise_vorhanden_aber_nicht_dokumentiert`
- `nicht_relevant`

Diese Dialogbewertung ersetzt nicht die Anforderungsmatrix. Für deren bestehende Felder gilt: eindeutig belegt entspricht `erfuellt`; teilweise oder übertragbar belegt entspricht `teilweise` mit wahrer Belegart; nicht belegt entspricht `nicht_belegt`; widersprüchlich oder möglicherweise vorhanden entspricht bis zur Klärung `unklar`; nicht relevant entspricht `nicht_relevant`.

Eine Rückfrage ist nur zulässig, wenn alle folgenden Punkte erfüllt sind:

1. Die Anforderung ist für die konkrete Stelle und den gewählten Dokumentumfang relevant.
2. Die vorhandenen Daten belegen sie nicht ausreichend oder widersprechen sich.
3. Der Nutzer könnte die fehlende Information plausibel selbst bestätigen oder korrigieren.
4. Die Antwort beeinflusst Wahrheit, Eignungsbewertung oder Qualität der gewählten Unterlagen wesentlich.

Frage nicht nach eindeutig nicht vorhandenen formalen Abschlüssen, unwichtigen Randanforderungen, bereits ausreichend belegten oder übertragbar abgedeckten Punkten, für den Umfang irrelevanten Informationen oder bereits beantworteten Einträgen in `dialog.rueckfragen`. Erzeuge keine Frage nur, um interaktiv zu wirken.

## Phase 3: Gezielte Rückfragen

Verwandte Lücken werden in einer verständlichen Frage gebündelt. Pro Dialogrunde sind höchstens drei voneinander unabhängige Fragen zulässig. Nach jeder Runde werden die Antworten verarbeitet; eine weitere Runde erfolgt nur, wenn eine verbleibende Unklarheit wesentlich ist.

Konfrontiere den Nutzer nicht mit internen Status- oder Matrixbezeichnungen. Erläutere knapp, was die Stelle verlangt und was im Profil noch nicht eindeutig ist. Biete kurze Antwortmöglichkeiten an und erlaube immer eine freie Beschreibung. Beispiel:

```text
In der Stellenanzeige werden TypeScript-Kenntnisse verlangt. Dazu finde ich in Ihrem Profil noch keine eindeutige Angabe.

Welche Aussage trifft zu?

A – Beruflich eingesetzt
B – In privaten Projekten eingesetzt
C – In einer Weiterbildung oder einem Kurs gelernt
D – Theoretische Grundkenntnisse
E – Keine Kenntnisse
F – Freie Beschreibung
```

Antworten wie `B, in zwei privaten React-Projekten`, `privat gelernt`, `keine Erfahrung` oder eine gemeinsame Antwort auf mehrere nummerierte Fragen müssen inhaltlich ausgewertet werden. Ein Buchstabe darf immer nur im Kontext der gerade offenen Frage interpretiert werden.

Reicht eine Antwort für eine wahrheitsgemäße Einordnung noch nicht aus, darf genau die kleinste notwendige Präzisierungsfrage folgen, beispielsweise zu Anwendungskontext, Praxisart, Zeitraum oder Niveau. Sind genügend Details vorhanden, wird nicht weiter gefragt.

## Phase 4: Erfahrungsart wahrheitsgemäß einordnen

Eine Nutzerantwort wird nicht ungeprüft wörtlich in Bewerbungsunterlagen oder Profildateien übernommen. Ordne nur die tatsächlich belegte Erfahrungsart ein und nutze die Wahrheitsebenen aus `Prompts/07_WAHRHEIT_UND_GRENZEN.md`:

| Dialogeinordnung | Beleg- und Formulierungsebene |
| --- | --- |
| berufliche Anwendung | `BERUFLICH BELEGT`, aber nur bei tatsächlicher Berufsausübung |
| übertragbare Berufserfahrung | `ÜBERTRAGBAR` |
| formale Weiterbildung oder Kurs | `WEITERBILDUNG` |
| konkret beschreibbare Projektarbeit | `PROJEKTPRAXIS` |
| eigene Projekte oder Home-Lab | `PRIVATE PRAXIS / HOME-LAB` |
| Selbststudium oder theoretische Basis | `GRUNDLAGEN / VERSTÄNDNIS` |
| gewünschte künftige Vertiefung | `EINARBEITUNGSZIEL` |
| ausdrücklich keine Erfahrung | für diesen Auftrag `nicht_belegt`; nicht als vorhandene Kompetenz speichern |

Erfasse bei Bedarf Kontext, ungefähre Dauer, Projektbezug sowie praktische oder theoretische Tiefe. Wähle die stärkste wahrheitsgemäße Formulierung, ohne private, schulische, autodidaktische oder ehrenamtliche Erfahrung als Berufserfahrung auszugeben.

## Phase 5: Auftragsbezogene und dauerhafte Angaben trennen

Eine neue Angabe gilt zunächst immer nur für die aktuelle Bewerbung. Nach ihrer wahrheitsgemäßen Einordnung wird sie in `dialog.angaben` mit `speicherentscheidung = nur_auftrag` und `profilaktualisierung.status = nicht_geaendert` gespeichert und darf für die aktuellen Dokumente verwendet werden. Daraus folgt noch keine Erlaubnis, `Private/Daten/` zu verändern.

Neue, wahrscheinlich langfristig relevante Angaben werden nach der Rückfragerunde gebündelt. Zeige die beabsichtigte Formulierung transparent und frage ausdrücklich:

```text
Folgende neue Angaben sind bisher nicht dauerhaft in Ihrem Profil gespeichert:

1. TypeScript – praktische Kenntnisse aus privaten React-Projekten
2. Docker – Grundlagen aus dem eigenen Home-Server

Was soll übernommen werden?

A – Alle Angaben dauerhaft speichern
B – Keine Angabe speichern, nur für diese Bewerbung verwenden
C – Einzeln auswählen
D – Formulierungen vorher ändern
```

Bei nur einer Angabe genügen `Ja, übernehmen`, `Nein, nur für diese Bewerbung` und `Formulierung vorher ändern`. Akzeptiere auch eindeutige natürliche Antworten sowie Kombinationen wie `1 speichern, 2 nur diesmal`.

Eine dauerhafte Änderung ist nur erlaubt, wenn alle drei Bedingungen erfüllt sind:

1. Der Nutzer hat die Information selbst angegeben oder ausdrücklich bestätigt.
2. Der Agent hat die beabsichtigte Formulierung und die betroffene Profildatei transparent genannt.
3. Der Nutzer hat der dauerhaften Speicherung eindeutig zugestimmt.

Sobald eine Speicherentscheidung tatsächlich erfragt wird, speichert der Agent zuerst den oben definierten Vorschlagssnapshot, setzt die bestätigte Angabe auf `speicherentscheidung = ausstehend`, verknüpft genau eine offene Speicherfrage und setzt `dialog.status = speicherentscheidung_offen`. Eine mehrdeutige Speicherantwort wird höchstens einmal vereinfacht nachgefragt. Bleibt sie unklar, bleiben diese Zustände bestehen und die zugehörige offene Rückfrage blockiert die Dokumenterstellung. Mehrdeutigkeit ist niemals Zustimmung. Wird keine dauerhafte Speicherung angeboten oder wird sie eindeutig abgelehnt, lautet die Entscheidung weiterhin beziehungsweise wieder `nur_auftrag`, der Profilstatus `nicht_geaendert` und der Vorschlagssnapshot wird entfernt.

Nach einer eindeutigen Entscheidung schließt das Übernahmewerkzeug die verknüpfte Speicherfrage erst, wenn alle darin gebündelten Angaben entschieden sind. Die Frage wird `beantwortet`, nicht blockierend und erhält eine knappe Zusammenfassung. `dialog.status` wird danach aus dem Restzustand neu abgeleitet: weitere Speicherentscheidungen, sonst offene Blocker oder Widersprüche, sonst `bereit_zur_dokumenterstellung`.

### Zustimmung

Bei eindeutiger Zustimmung:

1. Bestimme die fachlich zuständige private Datei.
2. Prüfe, ob die Angabe bereits sinngemäß vorhanden ist.
3. Vermeide Dubletten und erhalte vorhandene, nicht betroffene Angaben unverändert.
4. Ergänze oder ersetze nur an der fachlich passenden Stelle.
5. Übergebe an `Tools/Uebernehme-Dialogangabe.ps1` exakt die bereits im Vorschlagssnapshot gespeicherte Datei, den Abschnitt, die Formulierung und den Ausgangshash; Abweichungen oder ein zwischenzeitlich veränderter Profilhash werden abgelehnt.
6. Protokolliere Entscheidung, vorgeschlagene und bestätigte Formulierung, fachlichen Zieltyp, Datei, Abschnitt, Zustimmungs- und Aktualisierungszeit sowie den SHA-256-Wert vor und nach der Änderung unter `profilaktualisierung`.
7. Setze `speicherentscheidung = dauerhaft` und `profilaktualisierung.status = aktualisiert` erst nach erfolgreichem Schreiben und Prüfen. War die bestätigte Angabe bereits sinngemäß vorhanden und war kein Schreiben nötig, verwende stattdessen `bereits_vorhanden`.
8. Bestätige die konkrete Änderung kurz.

Zulässige Profilziele sind ausschließlich:

- `Private/Daten/01_PERSOENLICHE_DATEN.md` für Identität, Kontakt und globale Bewerbungslogistik wie Verfügbarkeit, Stellenart, Arbeitsmodell, Region, Mobilität oder Gehaltslogik;
- `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` für fachliches Profil, Berufserfahrung, Ausbildung, Weiterbildungen, Kenntnisse, Projekte, private Praxis, Sprachen und fachliche Grenzen.

Ändere niemals `Private.example/`, einen universellen Lebenslauf oder andere private Bewerbungen als Nebenwirkung einer Profilzustimmung. Sensible Angaben werden nur gespeichert, wenn sie für den Nutzerauftrag notwendig sind und der Nutzer gerade dieser transparenten Formulierung ausdrücklich zugestimmt hat.

### Ablehnung oder Umformulierung

Bei Ablehnung bleibt die Profildatei hashgleich. Die normalisierte Angabe wird nur im aktuellen Bewerbungsauftrag verwendet und darf in einer späteren Bewerbung nicht als dauerhaft bestätigtes Profilwissen gelten.

Bei gewünschter Umformulierung schlägt der Agent eine neue sachliche Fassung vor. Vor einer eindeutigen Bestätigung dieser Fassung wird keine Profildatei geändert. Die Bestätigung einer Formulierung und die Entscheidung `nur für diesen Auftrag` sind voneinander unterscheidbar zu behandeln.

## Widersprüche behandeln

Widerspricht eine neue Antwort einer vorhandenen Profilangabe, wählt der Agent niemals stillschweigend eine Version und überschreibt nichts. Er nennt beide Aussagen knapp und fragt, welche aktuell wahr ist. Beispiel:

```text
Im Profil steht „TypeScript: Grundkenntnisse“. Sie haben jetzt regelmäßige Nutzung in mehreren privaten Projekten beschrieben.

Welche Angabe trifft aktuell besser zu?

A – Grundkenntnisse
B – Praktische Kenntnisse aus privaten Projekten
C – Eine andere Einordnung, die ich kurz beschreibe
```

Die Antwort klärt zunächst nur die Wahrheitsebene für den aktuellen Auftrag. Eine bestehende Profilangabe darf erst nach einer getrennten, ausdrücklichen Speicherzustimmung ersetzt werden. Bis zur Klärung bleibt `wahrheitsstatus = widerspruechlich`; die strittige Angabe darf nicht werbend verwendet werden.

Eine erstmalige Profilübernahme ist nur im gespeicherten Zustand `speicherentscheidung_offen` zulässig. Befindet sich der Dialog bereits in `dokumenterstellung` oder `abgeschlossen`, verweigert das Werkzeug die späte Quellenänderung. Soll die Angabe dennoch übernommen werden, muss der Agent den Workflow kontrolliert auf den Profilabgleich zurücksetzen und Matrix, Kandidatendateien, Prüfberichte, Screenshots sowie Sichtnachweise als ungültig behandeln; erst danach darf er eine neue transparente Speicherentscheidung öffnen und den geänderten Stand vollständig neu vorbereiten.

## Fortsetzen nach einem Agenten- oder Sitzungswechsel

Bei einer Fortsetzung wird der Dialog ausschließlich aus `Bewerbungsauftrag.json` rekonstruiert, nicht aus Chat-Erinnerung. Lies vor Matrix und Kandidatendateien mindestens:

- `dokumentumfang` einschließlich Bestätigung und E-Mail-only-Gate;
- `dialog.status`;
- alle Einträge aus `dialog.rueckfragen` mit `id`, Status, Blocker- und Widerspruchszustand;
- alle normalisierten auftragsbezogenen Einträge aus `dialog.angaben`;
- Speicherentscheidungen und bestätigte Formulierungen;
- offene Rückfragen und Widersprüche;
- Zielpfad und Erfolgsstatus bereits ausgeführter Profiländerungen.

Eine Rückfrage mit `status = beantwortet` darf nicht erneut gestellt werden. Setze beim ersten offenen Eintrag oder beim nächsten aus `dialog.status` folgenden Schritt fort. Ist eine protokollierte Profiländerung in der Zielprofildatei nicht mehr nachweisbar oder stimmt `profilaktualisierung.nachherSha256` nicht, behandle sie als inkonsistent und frage bei wesentlicher Auswirkung nach; behaupte keine dauerhafte Speicherung.

Eine reine Standabfrage verändert weder Auftrag noch Profil. Ein anderer Agent muss aus dem gespeicherten Zustand erkennen können, welcher Umfang gewählt wurde, welche Angaben nur für diesen Auftrag gelten, welche dauerhaft übernommen wurden, was noch offen ist und ob die Dokumenterstellung bereits begonnen hat.

## Universeller Lebenslauf

Bei `lebenslauf = universal_unveraendert` wird ein bereits freigegebener universeller Lebenslauf als konkreter HTML-Snapshot verwendet:

- Die Quelle liegt empfohlen unter `Private/LebenslaufUniversal/Aktiv/Lebenslauf - NACHNAME.VORNAME.html`.
- Sie muss frei von Platzhaltern sein und nach dem Pflichtschema benannt sein.
- Quellpfad, Dateiname und SHA-256-Wert werden im Bewerbungsauftrag eingefroren.
- Der Kandidaten-Lebenslauf wird hashgleich übernommen und weder textlich noch gestalterisch an Firma oder Zielrolle angepasst.
- Die Zielrolle muss in Anschreiben und E-Mail-Betreff stehen, nicht im unveränderten universellen Lebenslauf.
- Der Lebenslauf-zu-Anschreiben-Abgleich verwendet den Snapshot als Referenz.
- Eine belegte Anforderung, die im universellen Lebenslauf fehlt, darf im Anschreiben erklärt werden. Ist dies für Glaubwürdigkeit oder formale Eignung nicht ausreichend, wird ein individueller Lebenslauf empfohlen; der Umfang wird nicht stillschweigend gewechselt.

Fehlt bei Auswahl B eine gültige freigegebene Universalquelle, bleibt der Umfang bekannt, aber die Dokumenterstellung blockiert. Frage nach einer vorhandenen Quelle oder biete den getrennten Erstellungs- und Freigabeprozess für einen universellen Lebenslauf an. Improvisiere keinen Ersatz und ändere eine Universalquelle nur nach einem neuen ausdrücklichen Auftrag mit eigener Prüfung und Freigabe.

## Umfangsabhängige Ausgabe

Erzeuge, prüfe, rendere und veröffentliche ausschließlich die im bestätigten `dokumentumfang` gewählten Dokumente. Analyse, Anforderungsmatrix, Qualitäts- und Freigabenachweise bleiben entsprechend dem kanonischen Workflow erforderlich, werden aber auf den gewählten Umfang bezogen.

- Ein individueller Lebenslauf wird stellenbezogen erstellt.
- Ein universeller Lebenslauf wird unverändert übernommen und erneut technisch geprüft.
- Ein nicht gewählter Lebenslauf wird weder erzeugt noch als fehlende Pflichtdatei behandelt.
- Ein nicht gewähltes Anschreiben wird weder erzeugt noch als fehlende Pflichtdatei behandelt.
- Eine nicht gewählte E-Mail-Nachricht wird weder erzeugt noch als fehlende Pflichtdatei behandelt.
- `Nur Anschreiben` bedeutet Auswahl D. Es setzt keinen universellen Lebenslauf voraus und erzeugt keine E-Mail-Nachricht, sofern der Nutzer nichts anderes verlangt.
- `Anschreiben mit universalem Lebenslauf` bedeutet Auswahl B und enthält den unveränderten Lebenslauf als Anlage sowie eine neue E-Mail-Nachricht.

Der bestätigte Umfang steuert damit auch Kandidatenbestand, Layoutcheck, PDF-Export, ATS-Prüfung, Versandordner und Manifest. Kein Prüfschritt darf einen absichtlich nicht gewählten Bestandteil als Fehler melden.
