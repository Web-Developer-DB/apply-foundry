# Lebenslauf-Regeln

## Ziel

Der Lebenslauf ist eine bewerbungsspezifische, recruiterfreundliche Darstellung. Er zeigt nicht alles, sondern genau das, was zur Stellenbeschreibung passt, aus den privaten Profildaten belegbar ist und für die konkrete Zielrolle einen Nutzen hat.

Diese Zieldefinition gilt immer, wenn `dokumentumfang.lebenslauf = individuell` ist, unabhängig davon, ob Auswahl A, C oder E verwendet wird. Bei `dokumentumfang.lebenslauf = universal_unveraendert` wird kein neuer Lebenslauf geschrieben: Die freigegebene Universalquelle wird unverändert übernommen und nur technisch erneut geprüft und als PDF gerendert. Bei `nicht_enthalten` gelten die Lebenslauf-Erstellungsregeln nicht.

Der öffentliche Agent ist neutral. Branche, Rollenprofil, Erfahrungsart, Zusatzkenntnisse und Schwerpunkt entstehen aus:

1. der Stellenbeschreibung
2. `Private/Daten/01_PERSOENLICHE_DATEN.md`
3. `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md`

Keine Branche, keine konkrete Fachrolle und kein Projekttyp darf aus den öffentlichen Prompts als Standard angenommen werden.

## Datenquellen für den Lebenslauf

Für den Lebenslauf gelten klare Zuständigkeiten:

- Kontakt, Name, Dateiname-Name und verfügbare Links kommen aus `Private/Daten/01_PERSOENLICHE_DATEN.md`. Welche Links erscheinen und welche Bewerbungslogistik für den Einzelfall gilt, steuert der bewerbungsspezifische `Bewerbungsauftrag.json`; Datei `01` ist die Quelle seines initialen Snapshots.
- Zielrollen, Kurzprofil, Berufserfahrung, Ausbildung, Studium, Umschulung, Weiterbildung, Schulbildung, Kompetenzen, Sprachen, Projekte und private Praxis kommen aus `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md`.
- Wenn Datei `02` fachliche Inhalte nach Belegarten strukturiert, sind diese Belegarten verbindlich. Inhalte aus `BERUFLICH BELEGT`, `ÜBERTRAGBAR`, `WEITERBILDUNG`, `PROJEKTPRAXIS`, `PRIVATE PRAXIS / HOME-LAB`, `GRUNDLAGEN / VERSTÄNDNIS`, `EINARBEITUNGSZIEL` und `NICHT BEHAUPTEN` dürfen nicht sprachlich gleichgesetzt werden.
- Schulbildung gehört fachlich zu Datei `02`, nicht zu Datei `01`.
- Wenn fachliche Angaben in Datei `01` stehen, aber in Datei `02` fehlen oder widersprüchlich sind, muss der Agent dies in `Offene_Fragen.md` dokumentieren und darf daraus keine stillschweigend geglättete finale Fassung bauen.

## Aufbau

Der Lebenslauf orientiert sich am deutschsprachigen Arbeitsmarkt. Er ist kein reines Skill-Profil und keine Projektsammlung, sondern ein moderner, klar strukturierter CV mit formalen Stationen.

Der Standard ist ein ruhiger, tabellarisch wirkender deutscher Lebenslauf. Moderne Gestaltung ist erlaubt, aber sie muss die Recruiter-Lesbarkeit stärken. Vermeide Layouts, die wie Portfolioseiten, Skill-Dashboards, Marketingkarten oder Webprofile wirken.

Empfohlene Grundstruktur:

1. Kompakter Kopfbereich mit Name, Zielrolle, Kontakt und passender Stellenart
2. Kurzprofil mit maximal 3 bis 4 präzisen Zeilen oder 2 bis 3 starken Kurzpunkten
3. Rollenrelevante Kompetenzen als klar gruppierte Zeilen
4. Beruflicher Werdegang / Berufserfahrung, bevorzugt tabellarisch und chronologisch rückwärts
5. Praktische Zusatzpraxis, Projekte oder Home-Lab nur mit klarer Rollenrelevanz
6. Weiterbildung, Zertifikate und Qualifikationen
7. Ausbildung, Studium oder berufliche Bildung
8. Schulbildung nach dem im Bewerbungsauftrag gewählten Modus
9. Sprachen
10. Weitere Kenntnisse nur dann, wenn sie für diese Stelle erkennbaren Recruiter-Nutzen haben

Pflichtlogik für formale Stationen:

- Berufserfahrung, Ausbildung/Studium/berufliche Bildung und Schulbildung dürfen nicht durch Projekte, Skill-Listen oder private Praxis verdrängt werden.
- Wenn entsprechende Daten in `Private/Daten/` vorhanden sind, müssen sie im Lebenslauf berücksichtigt werden.
- Formale Stationen mit Zeitraum sind im deutschen Lebenslauf grundsätzlich nicht frei kürzbar. Wenn sie in Datei `02` vorhanden sind, müssen Zeitraum, Stationstyp, Name/Institution/Arbeitgeber und Rollen- oder Bildungsbezeichnung sichtbar bleiben.
- Diese Nicht-Kürzungsregel gilt uneingeschränkt für berufliche Stationen, Ausbildung, Umschulung, Studium, Weiterbildung und Zertifikate mit Zeitraum. Für Schulbildung gilt die unten definierte, ausdrücklich zu dokumentierende Kompaktoption.
- Bei Platzmangel dürfen zuerst Beschreibungen, Bulletpoints, Projektlisten, Tool-Details, Zusatzpraxis, Kurzprofil und Kompetenzlisten gekürzt werden. Formale Zeiträume und Stationsnamen dürfen nicht entfernt werden, nur um eine Seite zu halten.
- Wenn die vollständige formale Chronologie nicht sauber und lesbar auf eine DIN-A4-Seite passt, muss bewusst ein zweiseitiger Lebenslauf mit zwei expliziten A4-Seitencontainern erstellt werden.
- Wenn wichtige formale Daten fehlen, werden sie nicht erfunden, sondern in `Offene_Fragen.md` dokumentiert.
- Nicht-klassische Erfahrung, private Praxis, Quereinstieg oder Projektarbeit wird ehrlich als solche eingeordnet.
- Projekte und Zusatzpraxis stehen hinter den formalen Stationen oder werden kompakt in passende Abschnitte integriert.
- Zeiträume müssen für Recruiter nachvollziehbar sein. Auffällige Lücken oder aktuelle Phasen werden nicht erfunden, sondern mit vorhandenen Daten sauber eingeordnet oder in `Offene_Fragen.md` dokumentiert.
- Bei Quereinstieg darf der Lebenslauf nicht den Eindruck erwecken, dass private IT-Praxis, Weiterbildung oder Grundlagen berufliche Administratorerfahrung seien. Abschnittstitel und Formulierungen müssen klar unterscheiden zwischen `übertragbarer technischer Erfahrung`, `IT-Grundlagen`, `privater Praxis / Home-Lab` und `Einarbeitungsfeldern`.
- Wenn eine Kompetenz aus mehreren Belegarten stammt, muss die vorsichtigere Belegart die Formulierung steuern. Beispiel: `Linux` aus Home-Lab wird als `private Linux-Praxis` oder `Linux-Grundlagen aus Home-Lab` formuliert, nicht als berufliche Linux-Administration.

Die Reihenfolge und Abschnittsnamen dürfen je nach Profil angepasst werden, aber die formalen CV-Stationen müssen erkennbar bleiben. Mögliche Abschnittsnamen:

- `Berufserfahrung`
- `Berufliche Stationen`
- `Praxiserfahrung`
- `Ausbildung`
- `Studium`
- `Berufliche Bildung`
- `Schulbildung`
- `Weiterbildung und Zertifikate`
- `Zusatzqualifikationen`
- `Projekte und Praxis`

Abschnittsnamen müssen zur Zielrolle passen und dürfen keine falsche Spezialisierung suggerieren.

## Deutscher Recruiter-Standard

Vor dem finalen Schreiben ist der Lebenslauf gedanklich wie von einem Recruiter zu prüfen:

- Welche Zielrolle ist nach 5 Sekunden erkennbar?
- Welche Belege im Werdegang tragen diese Zielrolle wirklich?
- Gibt es eine nachvollziehbare Brücke bei Quereinstieg, Rollenwechsel oder nicht-klassischer Erfahrung?
- Sind Zeiträume und aktuelle Entwicklung verständlich?
- Wirkt der Lebenslauf formal seriös, ruhig, tabellarisch und nicht wie ein Portfolio?

Bevorzugte Darstellungsformen:

- Zeiträume links oder gut sichtbar vorangestellt, Inhalt rechts oder direkt daneben.
- Kompetenzen als gruppierte Textzeilen, nicht als unruhige Tag-Wolke.
- Private Praxis als `Praktische Erfahrung`, `Home-Lab`, `Projektpraxis` oder ähnliche ehrliche Bezeichnung.
- Entwicklungsfelder klar von vorhandener Erfahrung trennen.
- Kontaktinformationen kompakt darstellen, nicht als dominierende Karte.

Nur nutzen, wenn es wirklich passt:

- Skill-Tags oder Chips, und dann sparsam.
- große farbige Kästen, Kontaktboxen, Kartenlayouts oder dekorative Elemente.
- Projektlisten vor dem formalen Werdegang.

Nicht nutzen:

- eine vollständige Skill-Inventarliste
- portfolioartige Selbstdarstellung als Ersatz für berufliche Stationen
- visuelle Elemente, die den deutschen CV-Standard überdecken

## Bewerbungsprofil ableiten

Vor dem Schreiben des Lebenslaufs muss der Agent ein kurzes Bewerbungsprofil bestimmen:

- Zielrolle
- Branche oder Arbeitsfeld
- Erfahrungsart
- Seniorität oder Einstiegsniveau
- Stellenart aus dem Bewerbungsauftrag und Stellenart aus der Anzeige
- Arbeitsmodell, Region und Eintrittstermin, falls relevant
- vermutete Firmengröße, falls aus der Stellenbeschreibung ableitbar
- Kernargumente für die Zielrolle
- Zusatzkenntnisse mit Recruiter-Nutzen
- bewusst weggelassene Inhalte
- Beweislogik: welche Stationen oder Praxisbelege die Zielrolle tragen
- Risiken oder Lücken, die neutral behandelt oder in `Offene_Fragen.md` dokumentiert werden

Zusätzlich muss vor dem Lebenslauf eine strukturierte `Anforderungsmatrix.json` nach `Prompts/02_VORPRUEFUNG_UND_ANFORDERUNGSMATRIX.md` vorliegen. Jede früh platzierte Rollenbehauptung muss auf einen konkreten Beleg oder eine ausdrücklich vorsichtige Erfahrungsart in dieser Matrix zurückführbar sein.

Dieses Profil steuert Auswahl, Reihenfolge und Kürzung des Lebenslaufs.

Bei `lebenslauf = universal_unveraendert` steuert dieses Profil ausschließlich Analyse und die zusätzlich ausgewählten stellenbezogenen Dokumente. Es darf keine Änderung am universellen Lebenslauf auslösen. Reicht der universelle Lebenslauf für eine glaubwürdige Bewerbung nicht aus, wird ein Wechsel zu `lebenslauf = individuell` empfohlen; der Umfang wird nicht ohne Nutzerauftrag geändert.

## Inhalt

- Verwende nur Daten aus `Private/Daten/` und aus der konkreten Stellenbeschreibung.
- Verwende Datei `01` nur für persönliche Stammdaten und Datei `02` für fachliche Lebenslaufdaten.
- Nenne die Stellenart im Lebenslauf immer kompakt: `Vollzeit`, `Teilzeit` oder `Vollzeit/Teilzeit`, gemäß Bewerbungsauftrag und Stellenanzeige.
- Wenn der Bewerbungsauftrag einen Stundenumfang nennt, darf er bei Teilzeit oder gemischten Modellen ergänzt werden, z. B. `Teilzeit, 30 Std./Woche`.
- Wenn die Stellenanzeige eine andere Stellenart verlangt als der Bewerbungsauftrag, die Bewerbung nicht stillschweigend passend machen. Den Widerspruch in `Offene_Fragen.md` dokumentieren und im finalen Lebenslauf nur eine wahre, nicht widersprüchliche Formulierung verwenden.
- Arbeitsmodell, Region, Pendeldistanz oder Eintrittstermin nur aufnehmen, wenn sie für die Bewerbung nützlich sind oder die Anzeige dazu klare Anforderungen enthält.
- Formuliere kurz, konkret und ohne übertriebene Selbstdarstellung.
- Priorisiere Muss-Anforderungen der Stelle.
- Nenne private, ehrenamtliche, schulische, akademische oder inoffizielle Praxis korrekt als solche, nicht als berufliche Verantwortung.
- Trenne vorhandene Erfahrung, Grundlagen und Entwicklungsfelder sprachlich eindeutig.
- Bei Quereinstiegsprofilen müssen Zielrolle und Einstiegssituation früh sichtbar sein, z. B. durch Formulierungen wie `Bewerbung als ... (Quereinstieg)`, `IT-Grundlagen aus Weiterbildung und Home-Lab` oder `gezielte Einarbeitung in ...`.
- Verwende `NICHT BEHAUPTEN`-Abschnitte aus Datei `02` als harte Sperrliste. Diese Inhalte dürfen höchstens als Einarbeitungsziel erwähnt werden, wenn Datei `02` oder die Stellenanzeige dies erlaubt.
- Erfinde keine Arbeitgeber, Zeiträume, Zertifikate, Tools, Systeme, Branchen oder Verantwortlichkeiten.
- Lasse irrelevante Inhalte weg, auch wenn sie grundsätzlich vorhanden sind.

## Zusatzkenntnisse

Zusatzkenntnisse, Nebenprojekte und fachfremde Erfahrungen werden nur aufgenommen, wenn sie für diese Stelle einen erkennbaren Recruiter-Nutzen haben.

Erlaubt sind Zusatzkenntnisse, wenn sie mindestens eine dieser Funktionen erfüllen:

- sie passen direkt zur Stelle
- sie belegen eine gewünschte Arbeitsweise
- sie erhöhen Glaubwürdigkeit für die Zielrolle
- sie zeigen Lernfähigkeit, Breite oder Transferfähigkeit ohne abzulenken
- sie sind für die vermutete Firmengröße wahrscheinlich wertvoll

Wenn eine Zusatzkenntnis nur zeigt, „was die Person noch kann“, aber keinen Nutzen für diese Bewerbung hat, wird sie gekürzt oder weggelassen.

## Schulbildungsmodus

Der Bewerbungsauftrag legt genau einen Modus fest:

- `vollstaendig`: Alle in Datei `02` vorhandenen Schulstationen bleiben mit Zeitraum, Institution und Abschluss-/Bildungsbezeichnung sichtbar.
- `recruiter_kompakt`: Für erfahrene Bewerber oder bei engem Inhaltsbudget darf die Schulchronologie auf eine gut erkennbare Zeile mit dem höchsten oder relevantesten Schulabschluss verdichtet werden. Einzelne Schulzeiträume dürfen dann entfallen.

Auch im kompakten Modus darf Schulbildung nicht vollständig verschwinden. Der Abschluss muss wahr, eindeutig und als Schulbildung erkennbar bleiben. Berufserfahrung, berufliche Bildung, Studium, Umschulung und formale Weiterbildungen werden durch diesen Modus nicht kürzbar. Die Wahl wird in `Analyse.md` und `Qualitaetscheck.md` begründet; sie ist kein Mittel, um einen schlecht priorisierten Einseiter zu erzwingen.

## Profil-Links

Die Stammdaten definieren nur, welche öffentlichen Profile verfügbar sind. Der Bewerbungsauftrag entscheidet rollenbezogen, welche davon im Lebenslauf erscheinen:

- `alle`: alle gepflegten Profil-Links verwenden, wenn sie professionell und aktuell sind.
- `rollenrelevant`: ausschließlich die in `profillinksAuswahl` genannten Links verwenden. Jeder ausgewählte Link muss einen erkennbaren Recruiter-Nutzen für die Zielrolle haben.
- `keine`: keine öffentlichen Profil-Links in den Lebenslauf aufnehmen.

Nicht ausgewählte Links dürfen nicht beiläufig im Kontaktblock verbleiben. Ein Portfolio- oder Repository-Link wird nur ausgewählt, wenn die dort sichtbaren Inhalte die konkrete Rolle stützen und keine widersprüchliche Positionierung erzeugen. Die URL selbst wird niemals erfunden oder verändert.

## Optionales Passfoto

Diese Regel gilt ausschließlich für `dokumentumfang.lebenslauf = individuell`:

- Prüfe unmittelbar vor der Lebenslauferstellung ausschließlich den exakten Pfad `Private/Daten/Passfoto.png`. Stelle keine Rückfrage nach einem Foto und suche nicht nach ähnlich benannten Bilddateien.
- Fehlt die Datei, enthält der Lebenslauf weder Fotoelement noch Platzhalter oder reservierte Leerfläche. Das Fehlen ist kein Fehler und keine Warnung.
- Ist die Datei vorhanden, muss sie eine gültige PNG-Signatur und einen gültigen IHDR-Header besitzen. Eine beschädigte oder nur umbenannte Datei blockiert die Dokumenterstellung; sie wird nicht stillschweigend ausgelassen.
- Setze an der designgerechten Stelle genau einen optionalen Block mit `<!-- passfoto:start -->`, `{{PASSFOTO_BLOCK}}` und `<!-- passfoto:end -->`. Führe danach `pwsh -NoProfile -File Tools/bewerbung.ps1 passfoto --arbeitsordner "ARBEITSORDNER"` aus. Das Werkzeug entfernt den Platzhalter immer und bettet bei vorhandener Quelle genau ein `<img class="bewerbungsfoto" ... alt="">` als `data:image/png;base64` ein.
- Form, Größe, Rahmen, Position und Zuschnitt folgen dem konkreten Bewerbungsdesign. Das Foto darf weder verzerrt noch dominant, unscharf, abgeschnitten oder über anderen Inhalten platziert sein. Bei `object-fit: cover` muss insbesondere der Gesichtsausschnitt im Seitenscreenshot geprüft werden.
- Das Original wird weder verändert noch kopiert. Nur die eingebetteten Bytes liegen im privaten Lebenslauf-HTML und im daraus erzeugten PDF; `Versand/` erhält keine separate Bilddatei.
- Bei späterem Hinzufügen, Ändern oder Löschen von `Passfoto.png` das Einbettungswerkzeug erneut ausführen und anschließend fachliche Prüfung, technische Vorbereitung und persönliche Sichtprüfung erneuern.

Bei `universal_unveraendert` gilt die Fotoprüfung ausdrücklich nicht. Auch eine vorhandene `Passfoto.png` darf den eingefrorenen Universal-Lebenslauf nicht verändern.

## Recruiter-Strategie

Recruiter lesen oft schnell und selektiv. Die wichtigsten Passungen müssen innerhalb der ersten 10 bis 20 Sekunden sichtbar sein.

Bei großen Firmen oder stark standardisierten Rollen:

- klare Rollenpassung zuerst
- Muss-Anforderungen und Keywords früh sichtbar machen
- weniger Nebenprojekte und weniger erklärende Breite
- keine fachfremden Zusatzkenntnisse, wenn sie nicht direkt helfen

Bei kleinen Firmen, Startups, Vereinen oder breit angelegten Rollen:

- breiteres Profil darf sichtbarer sein
- Zusatzkenntnisse können als Flexibilitäts- und Lernsignal nützlich sein
- trotzdem immer mit konkretem Nutzen für die Stelle formulieren

Bei unklarer Firmengröße:

- klare Zielrollenpassung zuerst
- Zusatzkenntnisse nur knapp als Plus erwähnen

## A4-Inhaltsbudget

Ziel ist ein Lebenslauf, der im Idealfall auf eine DIN-A4-Seite passt. Eine Seite ist aber kein Dogma. Wenn der Lebenslauf mit den wichtigen formalen Stationen nicht sauber auf eine Seite passt, wird bewusst ein professioneller zweiseitiger Lebenslauf erstellt.

Grundregel:

1. Inhalt priorisieren.
2. Danach Layout moderat optimieren.
3. Wenn es weiterhin nicht sauber passt, bewusst auf zwei A4-Seiten wechseln.
4. Niemals relevante Inhalte abschneiden, verstecken oder unlesbar klein quetschen.

Richtwerte für eine A4-Seite:

- Kurzprofil: maximal 3 bis 4 Zeilen
- Kompetenz- oder Profilbasis: maximal 3 Gruppen; bei Quereinstieg keine Überschrift wählen, die berufliche Spezialistenpraxis suggeriert
- Skill-/Kompetenz-Tags: nur ausnahmsweise und sparsam; bevorzugt gruppierte Kompetenzzeilen
- Arbeitsweise: maximal 3 bis 4 Bulletpoints oder in andere Abschnitte integrieren
- Berufserfahrung: kompakt, aber mit allen vorhandenen formalen Stationen, Zeiträumen, Arbeitgebern und Rollenbezeichnungen
- Ausbildung, Studium und berufliche Bildung: kurz, aber vollständig als formale Chronologie mit Zeitraum und Stationsbezeichnung; Schulbildung entsprechend dem festgelegten Modus
- Weiterbildung/Zertifikate: rollenrelevante Beschreibungen priorisieren; vorhandene formale Weiterbildungsstationen mit Zeitraum und Bezeichnung nicht aus Platzgründen entfernen
- Praxis/Projekte/Zusatzkenntnisse: nur 1 bis 2 wirklich relevante Blöcke

Kürzungsreihenfolge bei Platzproblemen:

1. fachfremde Zusatzkenntnisse entfernen
2. nicht rollennahe Projekte entfernen oder auf eine Zeile reduzieren
3. lange Skill-Listen auf wichtigste Anforderungen reduzieren
4. Arbeitsweise kürzen oder in Profil/Berufserfahrung integrieren
5. Wiederholungen zwischen Kurzprofil, Skills und Erfahrung entfernen
6. Bulletpoints straffen
7. Kurzprofil verdichten
8. Beschreibungen formaler Stationen weiter verdichten, ohne Zeitraum, Arbeitgeber/Institution, Stationstyp oder Rollen-/Bildungsbezeichnung zu entfernen
9. Layout minimal verdichten, solange Lesbarkeit und Druckqualität professionell bleiben
10. Wenn die vollständige formale Chronologie weiterhin nicht passt, bewusst auf zwei A4-Seiten wechseln

Nicht gekürzt oder verdrängt werden dürfen:

- alle belegbaren beruflichen Stationen mit Zeitraum, Arbeitgeber und Rollenbezeichnung
- Ausbildung, Studium, Umschulung oder berufliche Bildung mit Zeitraum, Institution und Bildungsbezeichnung, wenn vorhanden
- Schulbildung gemäß `vollstaendig` oder als sichtbare Abschlusszusammenfassung gemäß `recruiter_kompakt`
- Weiterbildungen/Zertifikate mit Zeitraum, Institution und Bezeichnung, wenn sie in den privaten Daten als formale Qualifikation enthalten sind

Nur die Detailtiefe innerhalb dieser Stationen ist kürzbar. Die Station selbst bleibt sichtbar.

Wenn zwei Seiten fachlich sinnvoll sind:

- Es werden zwei explizite A4-Seitencontainer erstellt.
- Die Verteilung folgt fachlichen, recruiterfreundlichen Abschnitten und niemals einem technischen Umbruch: Jeder Abschnitt liegt vollständig auf genau einer Seite und trägt eine stabile `data-cv-section`-Kennung; jede Seite besitzt einen mit `data-cv-page-header` markierten Kopf.
- Seite 1 bündelt die stärksten Recruiter-Signale für die konkrete Profilrichtung. Seite 2 bildet einen eigenständigen, logisch lesbaren Block und beginnt nicht mitten in Berufserfahrung, Projekten, Ausbildung oder einer anderen Rubrik.
- Für den eigenständigen universellen Softwareentwicklungs-Lebenslauf gilt verbindlich: Seite 1 enthält vollständig Kurzprofil, Technologien und sämtliche ausgewählten Entwicklungsprojekte; Seite 2 enthält vollständig Berufserfahrung, Weiterbildung, Ausbildung und Schulbildung. Dadurch bleiben Entwicklungsbelege vorne scanbar und die gesamte formale Chronologie geschlossen zusammen.
- Seite 2 darf nicht wie ein zufälliger Rest wirken.
- Seite 1 darf nicht halb leer wirken; Seite 2 darf kein ausgelagerter Rest mit unten abgeschnittenen formalen Stationen sein.
- Wenn Seite 1 deutlich zu wenig Inhalt trägt oder Seite 2 nur durch einzelne verschobene Rubriken entsteht, muss neu verteilt, fachlich gekürzt oder wieder ein kompakter Einseiten-Lebenslauf erstellt werden.
- Schulbildung und berufliche Bildung dürfen bei einer zweiseitigen Fassung nicht erst so spät stehen, dass sie am Seitenende gefährdet oder abgeschnitten wirken.
- Es gibt keinen zufälligen Browserumbruch und keinen abgeschnittenen Inhalt.
- Jede Seite eines mehrseitigen Lebenslaufs erhält einen festen, dezenten Footer: unten eine feine horizontale Trennlinie über die Inhaltsbreite und darunter rechts die Seitenangabe, z. B. `Seite 1 von 2`.
- Seitenangaben dürfen nicht als normaler Absatz nach dem Inhalt stehen. Sie müssen am unteren Rand der jeweiligen A4-Seite verankert sein und dürfen nicht zwischen zwei Seiten oder mitten im Inhaltsfluss wirken.
- Der Seiteninhalt muss ausreichend unteren Innenabstand haben, damit Text, Listen und formale Stationen den Footer nicht berühren oder überdecken.

Wenn eine Seite gewählt wird:

- Die HTML-Seite muss technisch eine feste A4-Seite sein, nicht nur ein `min-height`-Container.
- Das Layout muss so kompakt sein, dass der verbindlich unterstützte Chrome-/Edge-Export bei 100 Prozent Skalierung nicht automatisch eine zweite Seite erzeugt.
- `overflow: hidden` darf nur auf der äußeren A4-Seite genutzt werden und nur, wenn vorher fachlich und visuell sichergestellt ist, dass kein relevanter Inhalt verdeckt wird.

## Stil

- Klar, scanbar, sachlich.
- Keine generischen KI-Floskeln.
- Keine langen Textwände.
- Bulletpoints nur dort, wo sie Lesbarkeit erhöhen.
- Keywords natürlich integrieren, nicht stapeln.
- Fachsprache nur verwenden, wenn sie zur Zielrolle und zu den privaten Daten passt.
- Ruhiges Layout schlägt dekoratives Layout.
- Deutsche CV-Konventionen schlagen Portfolio-Optik.

## Finale Datei

Dateiname:

`Lebenslauf - NACHNAME.VORNAME.html`

Finale Lebenslaufdateien dürfen keine Platzhalter, Warnhinweise, Entwurfsmarker oder abgeschnittene Inhalte enthalten. Der Dateiname nutzt den Bewerbernamen aus den privaten Daten, damit E-Mail-Anhänge für Recruiter schnell zuordenbar sind.

Bei `lebenslauf = universal_unveraendert` muss der SHA-256-Wert der final geprüften HTML-Quelle mit dem im Bewerbungsauftrag eingefrorenen Universal-Snapshot übereinstimmen.

## Tokenbericht nach dem Lebenslauf

Sobald der Lebenslauf-Kandidat fertiggestellt ist beziehungsweise der unveränderte Universal-Snapshot als Kandidat feststeht, aktualisiert der Agent `Tokenverbrauch.json` über `Tools/Aktualisiere-Tokenbericht.ps1 -Messbereich lebenslauf` nur dann sofort, wenn für diesen Messbereich bereits exakte maschinenlesbare Laufzeitwerte vorliegen. Andernfalls schreibt erst die spätere Finalisierung einmalig den Status `unavailable`; ein zusätzlicher Zwischenlauf ohne Messwerte ist nicht erforderlich.

Exakte Tokenwerte dürfen nur mit `-NutzungsdatenVerfuegbar` übergeben werden, wenn die Agentenlaufzeit diese maschinenlesbar ausweist. Sie werden weder aus Textlängen hochgerechnet noch aus Teilwerten ergänzt. Kann nur die gesamte Agentensitzung gemessen werden, wird `-Messumfang gesamte_agentensitzung` verwendet und die fehlende isolierte Lebenslaufmessung ausdrücklich genannt. Ohne exakte Nutzungsdaten lautet die Ausgabe `Tokenverbrauch: Von dieser Agentenumgebung nicht bereitgestellt.`; die Erstellung von Anschreiben und E-Mail wird dadurch nicht unterbrochen.
