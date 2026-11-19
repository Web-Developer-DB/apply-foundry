# E-Mail-Nachricht-Regeln

## Ziel

Die E-Mail-Nachricht ist kurz, höflich und funktional. Bei ausgewähltem Anschreiben ergänzt sie dieses als Versandtext. Bei ausdrücklich bestätigter E-Mail ohne Anlagen erfüllt sie den vereinbarten Versandzweck eigenständig. Sie enthält immer eine direkt nutzbare Betreffzeile für den E-Mail-Versand.

## Datei

`Email-Nachricht--FIRMEN-SLUG.md`

`FIRMEN-SLUG` ist exakt der Wert `firmaSlug` aus dem zugehörigen `Bewerbungsauftrag.json`, zum Beispiel `Muster GmbH` → `Muster-GmbH`. Die Datei liegt vor der Freigabe im `Kandidat/`-Ordner und nach der Veröffentlichung unter `Versand/`. Sie ist immer UTF-8-Markdown; eine `.html`-Variante oder ein frei gewählter Dateiname ist nicht zulässig.

## Inhalt

- Die Datei beginnt immer mit einer Betreffzeile im Format `Betreff: ...`.
- Der Betreff nennt Zielrolle und Bewerbername. Wenn vorhanden, nimmt er zusätzlich Kennziffer, Referenznummer oder Job-ID aus der Stellenanzeige auf.
- Nach der Betreffzeile folgt eine Leerzeile, danach beginnt die eigentliche E-Mail-Nachricht.
- Neutrale oder konkrete Anrede.
- Kurzer Hinweis auf Bewerbung und Zielrolle.
- Hinweis ausschließlich auf die laut `dokumentumfang` tatsächlich ausgewählten PDF-Anlagen. Bei Lebenslauf und Anschreiben werden beide als getrennte Anlagen genannt; bei nur einer Anlage wird nur diese genannt.
- Bei einer ausdrücklich bestätigten E-Mail ohne Anlagen darf die Nachricht keine Anlage behaupten. Sie muss inhaltlich zum bestätigten Versandzweck passen.
- Bei universellem Lebenslauf und Anschreiben werden Lebenslauf und Anschreiben als zwei getrennte Anlagen genannt. Interne Begriffe wie Snapshot, unveränderte Universalquelle oder neu erstellter Kandidat gehören nicht in den Versandtext.
- Freundlicher Abschluss mit Name aus den privaten Daten.
- Wenn die Stellenanzeige eine konkrete Bewerbungsfrage enthält, wird sie kurz und sachlich beantwortet, soweit die Antwort belegt ist. Bewerberangaben stammen aus privaten Quellen oder bestätigten auftragsbezogenen Angaben; die Stellenbeschreibung allein belegt keine persönliche Erfahrung oder Verfügbarkeit.

## Stil

- 4 bis 7 Zeilen sind ein Richtwert, kein Prüflimit; die tatsächliche Bildschirmbreite bestimmt Zeilenumbrüche. Notwendige Antworten auf Bewerbungsfragen bleiben vollständig.
- Keine langen Motivationsabsätze.
- Keine Platzhalter in finaler Datei.
- Kein erfundener Ansprechpartner.
- Keine erfundene Kennziffer, Referenznummer oder Job-ID im Betreff.
- Keine Wiederholung des Anschreibens.

Eine Bitte um Bewerbung „als PDF“ beschreibt ohne weitere Präzisierung das Dateiformat. Sie ist kein automatischer Auftrag, mehrere ausgewählte Dokumente zu einer einzigen PDF zusammenzuführen. Die E-Mail nennt die tatsächlich vorhandenen Anlagen; eine Gesamt-PDF wird nur bei ausdrücklicher Forderung erstellt.

## Beispielstruktur

```text
Betreff: Bewerbung als [Rolle] - [Kennziffer] - [Name]

Sehr geehrte Damen und Herren,

anbei sende ich Ihnen meine Bewerbungsunterlagen für die Position als [Rolle].

Über eine Rückmeldung freue ich mich.

Mit freundlichen Grüßen
[Name]
```

Das Beispiel ist nur Struktur. Finale Dateien müssen echte Daten verwenden.
