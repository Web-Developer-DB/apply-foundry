# Vorlagen

Dieser Ordner enthält öffentliche HTML-Designreferenzen.

`Anforderungsmatrix.example.json` ist die öffentliche Strukturreferenz für den verpflichtenden Muss-/Kann-Abgleich vor der Dokumenterstellung.

Die Vorlagen enthalten nur Platzhalter und dürfen keine echten Bewerberdaten enthalten. Der Agent darf Struktur und CSS-Regeln übernehmen, muss aber vor finaler Ausgabe alle Platzhalter ersetzen.

Die Lebenslaufreferenz ist bewusst als ruhiger deutscher Recruiter-CV angelegt:

- kompakter Kopf
- tabellarisch lesbarer Werdegang
- Kompetenzen als gruppierte Zeilen statt Tag-Wolke
- feste A4-Seitenhöhe für den stabilen Chrome-/Edge-/Chromium-Export
- Vorschauabstände, Schatten und Seitenhintergründe ausschließlich unter `@media screen`; `.page + .page` wird im Druckmodus ausdrücklich auf `margin-top: 0` gesetzt
- ein markierter optionaler Passfoto-Block, der über `python3 Tools/bewerbung.py passfoto` vollständig befüllt oder entfernt wird

Die gezeigte Fotoform ist nur eine neutrale Referenz. Bei vorhandenem `Private/Daten/Passfoto.png` werden Größe, Form, Rahmen, Position und Zuschnitt an das konkrete Bewerbungsdesign angepasst und anschließend im Seitenscreenshot geprüft. Ohne Datei bleibt weder ein Fotoelement noch reservierter Leerraum zurück.

Wenn der Inhalt nicht auf eine A4-Seite passt, darf die Vorlage nicht einfach wachsen. Dann muss entweder gekürzt oder ein bewusster zweiseitiger Lebenslauf mit zwei `.page`-Containern erstellt werden.

Der technische Layoutnachweis arbeitet zweistufig: zuerst wird jede explizite `.page` isoliert als PNG und per DOM-Geometrie geprüft, anschließend wird das vollständige Original-HTML mit denselben Chromium-Druckparametern vorgeprüft. Die PDF muss exakt so viele A4-Seiten erzeugen wie `.page`-Container vorhanden sind. Nach jeder HTML- oder CSS-Änderung ist diese vollständige Druckvorprüfung erneut auszuführen; Dichtehinweise bleiben redaktionelle Warnungen und werden nicht durch künstlichen Leertext beseitigt.
