# HTML/CSS-Designregeln

## Ziel

Lebenslauf und Anschreiben werden als eigenständige HTML-Dateien erzeugt. Sie müssen in Firefox sichtbar gut aussehen und in der Druckansicht dieselben Proportionen behalten.

## Grundregeln

- CSS immer direkt im HTML einbetten.
- Keine externen Fonts, Skripte oder CDNs.
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
  </main>
  <main class="page page-2">
    <!-- Seite 2 -->
  </main>
</body>
```

```css
.page {
  width: 210mm;
  height: 297mm;
  margin: 0 auto;
  overflow: hidden;
  background: #fff;
  box-sizing: border-box;
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

## Firefox-Druck

Browser-Kopf- und Fußzeilen wie Dateiname, URL, Datum und Seitenzahl kommen aus dem Druckdialog, nicht aus dem HTML.

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
<main class="page">Seite 1</main>
<main class="page">Seite 2</main>
```

Kein zufälliger Umbruch mitten im Layout. Kein finaler Inhalt darf durch `overflow: hidden` nur optisch versteckt werden.

Vor der finalen Ausgabe eines zweiseitigen Lebenslaufs muss die Verteilung auf die Seiten geprüft werden:

- Seite 1 muss wie eine vollständig genutzte CV-Seite wirken, nicht wie ein Kopfbereich mit etwas Inhalt und großer leerer Fläche.
- Seite 2 muss bewusst strukturiert sein und darf nicht nur aus ausgelagerten Restabschnitten bestehen.
- Formale Stationen wie Ausbildung, berufliche Bildung und Schulbildung dürfen nicht am unteren Seitenrand abgeschnitten oder optisch gefährdet sein.
- Wenn die Verteilung nicht stimmt, ist das Layout nicht final; Inhalte müssen neu verteilt, gekürzt oder wieder auf einen kompakten Einseiten-Lebenslauf gebracht werden.

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
