# HTML/CSS-Designregeln

## Ziel

Ein laut Dokumentumfang ausgewählter Lebenslauf oder ein ausgewähltes Anschreiben wird jeweils als eigenständige HTML-Datei erzeugt. Jedes vorhandene HTML-Dokument muss in Chrome oder Edge sichtbar gut aussehen und im verbindlichen Chromium-Druckexport dieselben Proportionen behalten. Andere Browser dürfen zusätzlich manuell geprüft werden, ersetzen aber keinen maschinellen Nachweis.

## Grundregeln

- CSS immer direkt im HTML einbetten.
- Keine automatisch geladenen externen oder lokalen Ressourcen, Fonts, Stylesheets, Bilder, Medien, Skripte oder CDNs. Vollständig eingebettete `data:`-Ressourcen sind zulässig, wenn sie keine privaten Zusatzdaten offenlegen.
- Kontaktlinks sind die einzige Ausnahme ohne Nachladen: `<a href="https://…">https://…</a>` für Portfolio- oder Profilseiten und `<a href="mailto:name@example.de">name@example.de</a>` für E-Mail-Adressen. Der sichtbare Text muss dem Ziel vollständig entsprechen; verkürzte oder anders beschriftete Links sind nicht zulässig. Diese Links müssen im HTML lesbar und im exportierten PDF anklickbar bleiben.
- Nicht zulässig bleiben insbesondere `javascript:`, `file:`, protokollrelative Ziele (`//…`), andere URI-Schemata, `<link>`, `@import`, externe oder lokale `src`-Attribute sowie CSS-`url()`-Nachladungen. Ein Linkziel darf beim Rendern nicht geladen werden.
- Keine Dateipfade im Dokument anzeigen.
- Keine sichtbaren Platzhalter in finalen Dateien.
- A4 als feste Seitenfläche verwenden.
- Bildschirmansicht und Druckansicht dürfen nicht heimlich unterschiedliche Schriftgrößen, Spaltenbreiten oder Abstände verwenden.
- Einseiten-Dokumente müssen technisch eine feste A4-Seite sein: `width: 210mm; height: 297mm;`.
- `min-height: 297mm` allein ist für finale Einseiter nicht erlaubt, weil der Browser sonst automatisch auf zwei Seiten umbrechen kann.
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
- Der verbindliche Layoutcheck misst zusätzlich browserseitig `scrollHeight`, Elementgrenzen und sichtbare Überläufe. Ein Textanker im HTML genügt nicht, wenn sein Element außerhalb der A4-Seite liegt oder abgeschnitten wird.

Empfohlene Geometrie für einen bewusst zweiseitigen Lebenslauf:

```html
<body>
  <main class="page page-1">
    <header data-cv-page-header><!-- wiederholbarer Seitenkopf --></header>
    <section data-cv-section="kurzprofil"><!-- vollständiger Abschnitt --></section>
    <footer class="page-footer">Seite 1 von 2</footer>
  </main>
  <main class="page page-2">
    <header data-cv-page-header><!-- wiederholbarer Seitenkopf --></header>
    <section data-cv-section="berufserfahrung"><!-- vollständiger Abschnitt --></section>
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

/* Ausschließlich für die Bildschirmvorschau, niemals für das Drucklayout. */
@media screen {
  .page + .page {
    margin-top: 8mm;
  }
}

@media print {
  /* Derselbe Selektor verhindert, dass eine globale ältere Regel die
     weniger spezifische .page-Margin im Druck überschreibt. */
  .page + .page {
    margin-top: 0;
  }

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

Bei zwei Lebenslaufseiten sind `data-cv-page-header`, jede eindeutige `data-cv-section`-Kennung und `<footer class="page-footer">` nicht nur Designempfehlungen, sondern ein statischer Vertragsbestandteil. Eine andere Footer-Klasse, fehlende Markierungen oder doppelte Abschnittskennungen blockieren die technische Vorbereitung. Der Layoutcheck lässt den gesamten Footerbereich bei der Dichtemessung außer Betracht.

Für mehrseitige Lebensläufe ist dieser Footer Pflicht. Die Maße für `left`, `right` und `bottom` müssen zur jeweiligen Seitenpolsterung passen. Der Inhalt braucht genügend unteren Abstand, damit er die Trennlinie und Seitenangabe nicht berührt. Seitenzahlen dürfen nicht als normales `<p>` am Ende des Inhaltsflusses stehen.

Abstände, Schatten und Hintergründe zwischen zwei A4-Seiten sind reine Bildschirmvorschau und gehören in `@media screen`. Eine globale Regel wie `.page + .page { margin-top: 8mm; }` kann wegen ihrer höheren CSS-Spezifität im Druck weitergelten und eine Fußzeile auf eine zusätzliche PDF-Seite verschieben. Im Druckmodus muss derselbe Selektor ausdrücklich auf `0` zurückgesetzt werden. Nach jeder Änderung eines mehrseitigen HTML-Dokuments ist vor Dichte- oder Typografiearbeit die vollständige Druckvorprüfung auszuführen: Die Zahl der PDF-Seiten muss exakt der Zahl der expliziten `.page`-Container entsprechen.

Jeder zweiseitige Lebenslauf markiert außerdem den Seitenkopf jeder Seite mit `data-cv-page-header` und jeden fachlichen `<section>`-Block mit einer dokumentweit eindeutigen slugförmigen `data-cv-section`-Kennung. Dieselbe Kennung darf nicht auf beiden Seiten erscheinen. Eine Rubrik wird als Ganzes umverteilt; sie wird nicht durch CSS, Browserumbruch oder duplizierte Kennungen geteilt.

## Verbindlicher Chrome-/Edge-Druck

Browser-Kopf- und Fußzeilen wie Dateiname, URL, Datum und Seitenzahl kommen aus dem Druckdialog, nicht aus dem HTML.

Eine Ausnahme gilt für bewusst gestaltete, mehrseitige Lebensläufe: Dort ist ein eigener, dezenter Dokument-Footer mit Trennlinie und Seitenangabe im HTML vorgeschrieben. Browser-Kopf- und Fußzeilen bleiben trotzdem im Druckdialog deaktiviert.

Ein finaler Einseiten-Lebenslauf muss im automatisierten Chrome-/Edge-Export bei 100 Prozent Skalierung als genau eine Seite erscheinen. Wenn der unterstützte Chromium-Export zwei Seiten erzeugt, ist das HTML nicht final. Dann muss der Inhalt gekürzt, die Abschnittsaufteilung verbessert oder ein bewusst zweiseitiger Lebenslauf mit zwei `.page`-Containern erstellt werden.

Für finale PDF-Ausgabe:

Der verbindliche CLI-Export setzt A4, keine Browser-Kopf-/Fußzeilen und die vorgesehene Skalierung automatisch. Eine manuelle Vorschau darf ergänzend mit `Strg + P` erfolgen, gilt aber nur als tatsächlich geprüft, wenn sie wirklich geöffnet und bewertet wurde.

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
  <header data-cv-page-header><!-- Kopf Seite 1 --></header>
  <section data-cv-section="projekte"><!-- vollständiger Inhalt Seite 1 --></section>
  <footer class="page-footer">Seite 1 von 2</footer>
</main>
<main class="page">
  <header data-cv-page-header><!-- Kopf Seite 2 --></header>
  <section data-cv-section="berufserfahrung"><!-- vollständiger Inhalt Seite 2 --></section>
  <footer class="page-footer">Seite 2 von 2</footer>
</main>
```

Kein zufälliger Umbruch mitten im Layout. Kein finaler Inhalt darf durch `overflow: hidden` nur optisch versteckt werden.
Bei mehrseitigen Lebensläufen muss die Seitenangabe in einem festen Footer am unteren A4-Rand stehen: feine Trennlinie, darunter rechts die Seitenzahl. Der Footer ist Teil der Seitenarchitektur und darf nicht als nachlaufender Inhaltsabsatz umgesetzt werden.

Vor der finalen Ausgabe eines zweiseitigen Lebenslaufs muss die Verteilung auf die Seiten geprüft werden:

- Seite 1 muss wie eine vollständig genutzte CV-Seite wirken, nicht wie ein Kopfbereich mit etwas Inhalt und großer leerer Fläche.
- Seite 2 muss bewusst strukturiert sein und darf nicht nur aus ausgelagerten Restabschnitten bestehen.
- Kein fachlicher Abschnitt darf auf beiden Seiten beginnen beziehungsweise fortgesetzt werden; zusammengehörige Berufserfahrung oder Projekte bleiben atomar.
- Formale Stationen wie Ausbildung, berufliche Bildung und Schulbildung dürfen nicht am unteren Seitenrand abgeschnitten oder optisch gefährdet sein.
- Die Footer-Trennlinie und Seitenangabe müssen auf jeder Seite sichtbar, dezent und gleich positioniert sein.
- Der Footer darf keine Inhalte überdecken und darf nicht wie ein zufälliger Restabsatz zwischen den Seiten erscheinen.
- Wenn die Verteilung nicht stimmt, ist das Layout nicht final; Inhalte müssen neu verteilt, gekürzt oder wieder auf einen kompakten Einseiten-Lebenslauf gebracht werden.

Der automatische Layoutcheck erzeugt für jeden expliziten `.page`-Container ein isoliertes Prüf-HTML und daraus ein eigenes PNG im Format `...--seite-X-von-Y--chrome.png`. Dabei wird genau der ausgewählte Seitencontainer in den Dokumentkörper übernommen; zusätzliche `<main>`-Elemente oder seine ursprüngliche Position dürfen die Seitenauswahl nicht beeinflussen. Bei einem zweiseitigen Lebenslauf müssen beide Seiten einzeln geöffnet und bewertet werden; ein hoher Gesamtscreenshot oder nur die erste Bildschirmhöhe ist kein vollständiger Freigabenachweis.

Die automatische Dichteprüfung wertet ausschließlich den nutzbaren Inhaltsbereich oberhalb von Footer und unterem Sicherheitsabstand. Seitenkante, Scrollbar und fester Footer dürfen nicht als Inhalt gelten. Ein Dichtehinweis ist eine Aufforderung zur Sichtprüfung, kein Auftrag zum blinden Auffüllen, Verkleinern oder Entfernen hochwertiger Inhalte. Zuerst werden relevante belegbare Inhalte und die Seitenverteilung geprüft, danach die Ein-/Zweiseitenentscheidung und erst zuletzt moderate Abstands- oder Typografieanpassungen. Recruiter-Lesbarkeit und inhaltliche Priorität bleiben maßgeblich.

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

## Design eines optionalen Bewerbungsfotos

Ein Bewerbungsfoto ist nur zulässig, wenn bei einem individuellen Lebenslauf exakt `Private/Daten/Passfoto.png` vorhanden ist. Es wird als vollständig eingebettete `data:image/png;base64`-Ressource mit der stabilen Klasse `bewerbungsfoto` eingefügt. Lokale Pfade, externe URLs, CSS-Hintergrundbilder oder eine separate Bilddatei im Kandidaten- beziehungsweise Versandordner sind unzulässig.

Die öffentliche Designreferenz zeigt nur eine neutrale mögliche Anordnung. Die tatsächliche Darstellung muss zum konkreten Bewerbungsdesign passen:

- Der umgebende Block existiert nur mit Foto; ohne Quelle darf er weder Breite noch Höhe oder Weißraum reservieren.
- Seitenverhältnis und Gesichtszüge dürfen nicht verzerrt werden. Ein beschnittener Darstellungsrahmen ist nur zulässig, wenn Kopf und Gesicht im aktuellen Seitenscreenshot vollständig und professionell wirken.
- Größe, Form, Ecken, Rahmen und Position greifen Raster, Akzentfarbe und Typografie des konkreten Lebenslaufs auf, ohne Kontakt oder Recruiter-Signale zu verdrängen.
- Das Foto muss bei 100 Prozent Skalierung im Chrome-/Edge-Screenshot und im PDF scharf, vollständig, überlappungsfrei und drucktauglich erscheinen.
- Ein Foto darf die A4-Seitenstrategie nicht durch Verkleinern wichtiger Texte oder Abschneiden formaler Stationen retten. Inhalt und Seitenaufteilung werden bei Bedarf neu geplant.
