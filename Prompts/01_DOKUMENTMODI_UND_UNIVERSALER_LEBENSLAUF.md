# Dokumentmodi und universeller Lebenslauf

## Ziel

Der Workflow unterstützt zwei klar getrennte Betriebsarten. Der gewählte Modus wird im `Bewerbungsauftrag.json` unter `dokumentmodus` gespeichert und darf während einer Bewerbung nicht stillschweigend wechseln.

## Modus `vollbewerbung`

Dieser Modus erstellt eine vollständig stellenbezogene Bewerbung:

- neuer, auf die konkrete Zielrolle zugeschnittener Lebenslauf
- neues individuelles Anschreiben
- neue E-Mail-Nachricht
- Analyse, Anforderungsmatrix und Qualitätsnachweise

Pflichtregeln:

- Die im Bewerbungsauftrag gespeicherte Zielrolle muss in Lebenslauf, Anschreiben und E-Mail-Betreff in derselben Form vorkommen.
- Der Lebenslauf darf kein universelles Alles-Profil sein. Er wird anhand der Stellenbeschreibung priorisiert.
- Profil-Links, Kompetenzen, Projektpraxis und Detailtiefe werden rollenbezogen gewählt.

## Modus `anschreiben_mit_universalem_lebenslauf`

Dieser Modus erstellt nur die stellenbezogenen Bestandteile neu und verwendet einen bereits freigegebenen universellen Lebenslauf unverändert weiter:

- universeller Lebenslauf wird als HTML-Snapshot in den Kandidatenordner übernommen und als PDF neu gerendert
- neues individuelles Anschreiben
- neue E-Mail-Nachricht
- neue Analyse, Anforderungsmatrix und Qualitätsnachweise

Pflichtregeln:

- `Tools/Neue-Bewerbung.ps1` erhält `-Dokumentmodus anschreiben_mit_universalem_lebenslauf` und `-UniversalLebenslaufPath`.
- Die Universalquelle muss `Lebenslauf - NACHNAME.VORNAME.html` heißen und bereits frei von Platzhaltern sein.
- Der SHA-256-Wert der Universalquelle wird bei Anlage im Bewerbungsauftrag eingefroren.
- Der Kandidaten-Lebenslauf darf weder textlich noch gestalterisch an Firma oder Zielrolle angepasst werden.
- Die Zielrolle wird nur in Anschreiben und E-Mail-Betreff verlangt. Sie muss nicht im universellen Lebenslauf stehen.
- Der verbindliche Lebenslauf-zu-Anschreiben-Abgleich verwendet den unveränderten universellen Lebenslauf als Referenz.
- Wenn eine wesentliche Stellenanforderung im universellen Lebenslauf fehlt, wird sie bei belegter Datengrundlage im Anschreiben erklärt. Der Lebenslauf wird deswegen in diesem Modus nicht verändert.
- Ist die fehlende Information für die Glaubwürdigkeit oder formale Eignung zu wichtig für ein Anschreiben allein, wird ein Wechsel zu `vollbewerbung` empfohlen und nicht stillschweigend vorgenommen.

## Auswahlregel

- Nutzer verlangt eine vollständige Bewerbung oder nennt keinen Modus: `vollbewerbung`.
- Nutzer verlangt ausdrücklich nur ein Anschreiben zu einem bestehenden universellen Lebenslauf: `anschreiben_mit_universalem_lebenslauf`.
- Nutzer verlangt nur ein Anschreiben, aber es gibt keine freigegebene Universalquelle: nicht improvisieren. Zuerst die Erstellung und Freigabe eines universellen Lebenslaufs anbieten beziehungsweise durchführen.

## Ablage der Universalquelle

Empfohlener privater Pfad:

`Private/LebenslaufUniversal/Aktiv/Lebenslauf - NACHNAME.VORNAME.html`

Zusätzliche Versionen können datiert unter `Private/LebenslaufUniversal/Archiv/` liegen. Bewerbungen referenzieren immer einen konkreten HTML-Snapshot per Hash, niemals nur einen veränderlichen Ordnernamen.

## Versandlogik

Auch im Anschreiben-Modus enthält `Versand/` zwei Anlagen:

- den unverändert übernommenen und frisch geprüften universellen Lebenslauf als PDF
- das neue Anschreiben als PDF

„Nur Anschreiben erstellen“ bedeutet: Nur das Anschreiben wird inhaltlich neu geschrieben. Der freigegebene Lebenslauf wird für ein vollständiges Versandpaket unverändert beigefügt.
