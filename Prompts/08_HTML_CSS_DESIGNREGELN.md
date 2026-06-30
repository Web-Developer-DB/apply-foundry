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

## A4-Struktur

Empfohlene Seitenstruktur:

```html
<body>
  <main class="page">
    <!-- Inhalt -->
  </main>
</body>
```

Empfohlene Geometrie:

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
  min-height: 297mm;
  margin: 0 auto;
  background: #fff;
  box-sizing: border-box;
}

@media print {
  html,
  body {
    width: 210mm;
    min-height: 297mm;
    background: #fff;
  }

  .page {
    width: 210mm;
    min-height: 297mm;
    margin: 0;
    box-shadow: none;
  }
}
```

## Firefox-Druck

Browser-Kopf- und Fußzeilen wie Dateiname, URL, Datum und Seitenzahl kommen aus dem Druckdialog, nicht aus dem HTML.

Für finale PDF-Ausgabe:

1. `Strg + P` drücken.
2. `Weitere Einstellungen` öffnen.
3. `Kopf- und Fußzeilen drucken` deaktivieren.
4. Skalierung auf `100%` stellen.
5. Ränder auf `Keine` stellen.

## Seitenumbruch

Ein Einseiten-Dokument soll als eine A4-Seite gebaut werden. Wenn der Inhalt nicht passt, wird zuerst fachlich gekürzt: irrelevante Zusatzkenntnisse, fachfremde Projekte, lange Skill-Listen und unnötige Detailabsätze entfernen oder reduzieren. Layoutverdichtung kommt erst danach und darf keine schlechtere Lesbarkeit erzeugen.

Wenn zwei Seiten nötig sind, werden zwei klare Seitencontainer genutzt:

```html
<main class="page">Seite 1</main>
<main class="page">Seite 2</main>
```

Kein zufälliger Umbruch mitten im Layout. Kein finaler Inhalt darf durch `overflow: hidden` nur optisch versteckt werden.