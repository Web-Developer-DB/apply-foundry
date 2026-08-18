# Vorlagen

Dieser Ordner enthält öffentliche HTML-Designreferenzen.

`Anforderungsmatrix.example.json` ist die öffentliche Strukturreferenz für den verpflichtenden Muss-/Kann-Abgleich vor der Dokumenterstellung.

Die Vorlagen enthalten nur Platzhalter und dürfen keine echten Bewerberdaten enthalten. Der Agent darf Struktur und CSS-Regeln übernehmen, muss aber vor finaler Ausgabe alle Platzhalter ersetzen.

Die Lebenslaufreferenz ist bewusst als ruhiger deutscher Recruiter-CV angelegt:

- kompakter Kopf
- tabellarisch lesbarer Werdegang
- Kompetenzen als gruppierte Zeilen statt Tag-Wolke
- feste A4-Seitenhöhe für den stabilen Chrome-/Edge-Export
- ein markierter optionaler Passfoto-Block, der über `bewerbung.ps1 passfoto` vollständig befüllt oder entfernt wird

Die gezeigte Fotoform ist nur eine neutrale Referenz. Bei vorhandenem `Private/Daten/Passfoto.png` werden Größe, Form, Rahmen, Position und Zuschnitt an das konkrete Bewerbungsdesign angepasst und anschließend im Seitenscreenshot geprüft. Ohne Datei bleibt weder ein Fotoelement noch reservierter Leerraum zurück.

Wenn der Inhalt nicht auf eine A4-Seite passt, darf die Vorlage nicht einfach wachsen. Dann muss entweder gekürzt oder ein bewusster zweiseitiger Lebenslauf mit zwei `.page`-Containern erstellt werden.
