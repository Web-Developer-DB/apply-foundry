# HTML/CSS-Designregeln

## Ziel

Ein laut Dokumentumfang ausgewählter Lebenslauf oder ein ausgewähltes Anschreiben wird jeweils als eigenständige HTML-Datei erzeugt. Jedes vorhandene HTML-Dokument muss in Firefox sichtbar gut aussehen und in der Druckansicht dieselben Proportionen behalten.

## Grundregeln

- CSS immer direkt im HTML einbetten.
- Keine automatisch geladenen externen oder lokalen Ressourcen, Fonts, Stylesheets, Bilder, Medien, Skripte oder CDNs. Vollständig eingebettete `data:`-Ressourcen sind zulässig, wenn sie keine privaten Zusatzdaten offenlegen.
- Keine Dateipfade im Dokument anzeigen.
- Keine sichtbaren Platzhalter in finalen Dateien.
- A4 als feste Seitenfläche verwenden.
- Bildschirmansicht und Druckansicht dürfen nicht heimlich unterschiedliche Schriftgrößen, Spaltenbreiten oder Abstände verwenden.
- Einseiten-Dokumente müssen technisch eine feste A4-Seite sein: `width: 210mm; height: 297mm;`.
- `min-height: 297mm` allein ist für finale Einseiter nicht erlaubt, weil Firefox sonst automatisch auf zwei Seiten umbrechen kann.
- Der Lebenslauf soll ruhig, tabellarisch und recruiterfreundlich wirken. Keine dominierende Kontaktkarte, keine unruhige Skill-Tag-Wolke und keine portfolioartige Gestaltung, sofern die Stelle keinen kreativen Portfolio-CV verlangt.

## A4-Struktur

Empfohlene Seitenstruktur:

```html
<body>
  <main class="page">
    <!-- Inhalt -->
  </main>
</body>
```

Empfohlene Geometrie für ein Einseiten-Dokument:

```css
@page {
  size: A4;
  margin: 0;
}

html,
body {
  margin: 0;
  padding: 0;
  background: #e9edf3;
  font-family: Arial, Helvetica, sans-serif;
}

.page {
  width: 210mm;
  height: 297mm;
  margin: 0 auto;
  overflow: hidden;
  background: #fff;
  box-sizing: border-box;
}

@media print {
  html,
  body {
    width: 210mm;
    height: 297mm;
    min-height: 297mm;
    background: #fff;
  }

  .page {
    width: 210mm;
    height: 297mm;
    margin: 0;
    box-shadow: none;
  }
}
```

Wichtig:

- `overflow: hidden` ist nur auf der äußeren A4-Seitenfläche erlaubt.
- `overflow: hidden` darf niemals verwendet werden, um zu lange Inhalte unsichtbar zu machen.
- Wenn Inhalt nicht vollständig in diese feste A4-Seite passt, muss zuerst fachlich gekürzt oder bewusst auf zwei Seiten gewechselt werden.
- Keine fixen Höhen für normale Textabschnitte, Listen oder Spalten, wenn dadurch Inhalt abgeschnitten werden könnte.

Empfohlene Geometrie für einen bewusst zweiseitigen Lebenslauf:

```html
<body>
  <main class="page page-1">
    <!-- Seite 1 -->
    <footer class="page-footer">Seite 1 von 2</footer>
  </main>
  <main class="page page-2">
    <!-- Seite 2 -->
    <footer class="page-footer">Seite 2 von 2</footer>
  </main>
</body>
```

```css
.page {
  width: 210mm;
  height: 297mm;
  margin: 0 auto;
  padding-bottom: 17mm;
  overflow: hidden;
  position: relative;
  background: #fff;
  box-sizing: border-box;
}

.page-footer {
  position: absolute;
  right: 13mm;
  bottom: 7mm;
  left: 13mm;
  margin: 0;
  padding-top: 1.6mm;
  border-top: 1px solid #d5dee8;
  color: #667085;
  font-size: 9.8px;
  line-height: 1.2;
  text-align: right;
}

@media print {
  .page {
    width: 210mm;
    height: 297mm;
    margin: 0;
    box-shadow: none;
    break-after: page;
  }

  .page:last-child {
    break-after: auto;
  }
}
```

Für mehrseitige Lebensläufe ist dieser Footer Pflicht. Die Maße für `left`, `right` und `bottom` müssen zur jeweiligen Seitenpolsterung passen. Der Inhalt braucht genügend unteren Abstand, damit er die Trennlinie und Seitenangabe nicht berührt. Seitenzahlen dürfen nicht als normales `<p>` am Ende des Inhaltsflusses stehen.

## Firefox-Druck

Browser-Kopf- und Fußzeilen wie Dateiname, URL, Datum und Seitenzahl kommen aus dem Druckdialog, nicht aus dem HTML.

Eine Ausnahme gilt für bewusst gestaltete, mehrseitige Lebensläufe: Dort ist ein eigener, dezenter Dokument-Footer mit Trennlinie und Seitenangabe im HTML vorgeschrieben. Browser-Kopf- und Fußzeilen bleiben trotzdem im Druckdialog deaktiviert.

Ein finaler Einseiten-Lebenslauf muss in der Firefox-Druckvorschau bei 100 Prozent Skalierung als genau eine Seite erscheinen. Wenn Firefox zwei Seiten erzeugt, ist das HTML nicht final. Dann muss der Inhalt gekürzt, die Abschnittsaufteilung verbessert oder ein bewusst zweiseitiger Lebenslauf mit zwei `.page`-Containern erstellt werden.

Für finale PDF-Ausgabe:

1. `Strg + P` drücken.
2. `Weitere Einstellungen` öffnen.
3. `Kopf- und Fußzeilen drucken` deaktivieren.
4. Skalierung auf `100%` stellen.
5. Ränder auf `Keine` stellen.

## Seitenumbruch

Ein Einseiten-Dokument soll als eine A4-Seite gebaut werden. Wenn der Inhalt nicht passt, wird zuerst fachlich gekürzt: irrelevante Zusatzkenntnisse, fachfremde Projekte, lange Skill-Listen und unnötige Detailabsätze entfernen oder reduzieren. Layoutverdichtung kommt erst danach und darf keine schlechtere Lesbarkeit erzeugen.

Für Einseiter gilt:

- Die finale `.page` hat `height: 297mm`, nicht nur `min-height`.
- Der Inhalt darf keine zweite Browser-Druckseite erzeugen.
- Große Kopfbereiche, Kontaktkarten, Tag-Chips, überlange Kompetenzlisten und dekorative Abstände sind zu reduzieren, bevor die Schrift unprofessionell klein wird.
- Tabellenähnliche Zwei-Spalten-Strukturen sind erlaubt, wenn sie stabil und ruhig wirken.

Wenn zwei Seiten nötig sind, werden zwei klare Seitencontainer genutzt:

```html
<main class="page">
  <!-- Inhalt Seite 1 -->
  <footer class="page-footer">Seite 1 von 2</footer>
</main>
<main class="page">
  <!-- Inhalt Seite 2 -->
  <footer class="page-footer">Seite 2 von 2</footer>
</main>
```

Kein zufälliger Umbruch mitten im Layout. Kein finaler Inhalt darf durch `overflow: hidden` nur optisch versteckt werden.
Bei mehrseitigen Lebensläufen muss die Seitenangabe in einem festen Footer am unteren A4-Rand stehen: feine Trennlinie, darunter rechts die Seitenzahl. Der Footer ist Teil der Seitenarchitektur und darf nicht als nachlaufender Inhaltsabsatz umgesetzt werden.

Vor der finalen Ausgabe eines zweiseitigen Lebenslaufs muss die Verteilung auf die Seiten geprüft werden:

- Seite 1 muss wie eine vollständig genutzte CV-Seite wirken, nicht wie ein Kopfbereich mit etwas Inhalt und großer leerer Fläche.
- Seite 2 muss bewusst strukturiert sein und darf nicht nur aus ausgelagerten Restabschnitten bestehen.
- Formale Stationen wie Ausbildung, berufliche Bildung und Schulbildung dürfen nicht am unteren Seitenrand abgeschnitten oder optisch gefährdet sein.
- Die Footer-Trennlinie und Seitenangabe müssen auf jeder Seite sichtbar, dezent und gleich positioniert sein.
- Der Footer darf keine Inhalte überdecken und darf nicht wie ein zufälliger Restabsatz zwischen den Seiten erscheinen.
- Wenn die Verteilung nicht stimmt, ist das Layout nicht final; Inhalte müssen neu verteilt, gekürzt oder wieder auf einen kompakten Einseiten-Lebenslauf gebracht werden.

Der automatische Layoutcheck erzeugt für jeden expliziten `.page`-Container ein eigenes PNG im Format `...--seite-X-von-Y--chrome.png`. Bei einem zweiseitigen Lebenslauf müssen daher beide Seiten einzeln geöffnet und bewertet werden; ein hoher Gesamtscreenshot oder nur die erste Bildschirmhöhe ist kein vollständiger Freigabenachweis.

Die automatische Dichteprüfung wertet ausschließlich den nutzbaren Inhaltsbereich oberhalb von Footer und unterem Sicherheitsabstand. Seitenkante, Scrollbar und fester Footer dürfen nicht als Inhalt gelten. Ein Dichtehinweis ist eine Aufforderung zur Sichtprüfung, kein Auftrag zum blinden Auffüllen, Verkleinern oder Entfernen hochwertiger Inhalte. Recruiter-Lesbarkeit und inhaltliche Priorität bleiben maßgeblich.

## Lebenslauf-Designstandard

Für deutsche Bewerbungen ist der bevorzugte Lebenslaufstil:

- kompakter Kopf mit Name, Zielrolle und Kontakt
- klare Abschnittsüberschriften
- tabellarisch lesbarer Werdegang mit Zeiträumen
- Kompetenzen als gruppierte Zeilen statt großer Tag-Wolke
- dezente Farbe für Akzentlinien und Überschriften
- ausreichend Weißraum, aber keine großen leeren Flächen
- keine verschachtelten Kartenlayouts

Eine modernere Gestaltung ist erlaubt, wenn sie die Lesbarkeit verbessert. Sie darf den Lebenslauf aber nicht wie eine Portfolioseite, Landingpage oder reine Skill-Übersicht wirken lassen.
