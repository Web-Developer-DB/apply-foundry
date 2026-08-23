# Vorprüfung und Anforderungsmatrix

## Ziel

Vor dem Schreiben einer Bewerbung müssen Stammdaten, Bewerbungslogistik und Stellenanforderungen strukturiert geprüft werden. Freie Analyseabsätze allein reichen nicht aus, weil unklare Muss-Kriterien oder nicht gepflegte persönliche Entscheidungen sonst erst während der Finalisierung auffallen.

## Stammdatenprüfung

Zuerst über den Plattform-Dispatcher ausführen:

```powershell
pwsh -NoProfile -File Tools/bewerbung.ps1 stammdaten
```

```bash
python3 Tools/bewerbung.py stammdaten
```

Pflichtangaben zu Identität und Kontakt dürfen keine Beispielplatzhalter enthalten. Die zentralen Entscheidungen zu gewünschter Stellenart, gewünschtem Arbeitsmodell, Verwendung eines Gehaltswunschs und Gehaltslogik müssen vor der finalen Freigabe eindeutig gepflegt sein.

Der Ordnerhelfer kopiert die Bewerbungslogistik aus Datei `01` als Snapshot in `Bewerbungsauftrag.json`. Ab diesem Zeitpunkt ist dieser bewerbungsspezifische Snapshot für die konkrete Bewerbung maßgeblich; Datei `01` bleibt nur die Rückfallquelle für ältere Aufträge. So kann eine Bewerbung beispielsweise bewusst `Vollzeit` und `hybrid` verwenden, ohne globale Stammdaten für andere Bewerbungen umzuschreiben.

Ungeklärte zentrale Bewerbungslogistik im Bewerbungsauftrag wird bei der Finalisierung zum Blocker. Optionale Angaben dürfen offen bleiben, müssen aber als Warnung sichtbar sein und dürfen nicht erfunden werden.

## Bewerbungsauftrag

Das Subcommand `neu` des Plattform-Dispatchers (`pwsh -NoProfile -File Tools/bewerbung.ps1` unter Windows, `python3 Tools/bewerbung.py` unter Linux) erzeugt im privaten Arbeitsordner eine Datei `Bewerbungsauftrag.json`. `Tools/neue-bewerbung.sh` bleibt unter Linux ein kompatibler Alias. Unmittelbar danach wird die tatsächlich übergebene Stellenbeschreibung in `Kandidat/Stellenbeschreibung.md` gesichert, bevor Profilabgleich oder Rückfragen beginnen. Ein Platzhalter des Ordnerhelfers ist kein fortsetzbarer Stelleninhalt.

Ab Schema 4 enthält sie mindestens:

- den vom Nutzer bestätigten `dokumentumfang` mit Lebenslaufart, Anschreiben- und E-Mail-Auswahl, Quelle und Zeitstempel
- die technische Kompatibilitätsangabe `dokumentmodus`
- bei `lebenslauf = universal_unveraendert`: Pfad, Dateiname und SHA-256-Snapshot der freigegebenen Universal-Lebenslauf-HTML
- den normalisierten Dialogstatus mit stabilen IDs, offenen/beantworteten Rückfragen, auftragsbezogenen Angaben, Speicherentscheidungen und gegebenenfalls Profiländerungsnachweisen
- Firma und technischer Firmenslug
- Zielrolle und technischer Rollenslug
- Bewerbungsdatum
- Dateiname-Name des Bewerbers, sofern verfügbar
- finalen Zielordner
- privaten Arbeitsordner
- Kandidatenordner
- geplante Seitenstrategie
- Snapshot der Bewerbungslogistik
- ausdrückliche Bewerbungsentscheidung
- Darstellungsoptionen für Schulbildung und Profil-Links
- Hashnachweise der Stammdaten- und Profildatei zum Anlagezeitpunkt

Vor der Inhaltsprüfung müssen folgende Werte endgültig gesetzt sein:

- bei ausgewähltem Lebenslauf `seitenstrategie`: `eine_seite` oder `zwei_seiten`; sonst `nicht_erforderlich`
- `bewerbungsentscheidung`: `bewerben` oder `nicht_bewerben`
- bei ausgewähltem Lebenslauf `darstellungsoptionen.schulbildungsmodus`: `vollstaendig` oder `recruiter_kompakt`; sonst `nicht_erforderlich`
- bei ausgewähltem Lebenslauf `darstellungsoptionen.profillinksModus`: `alle`, `rollenrelevant` oder `keine`; sonst `nicht_erforderlich`
- bei `rollenrelevant`: `profillinksAuswahl` mit den tatsächlich verwendeten Feldnamen aus Datei `01`

Die Werte `noch_festzulegen` sind nur im initialen Arbeitsauftrag erlaubt und blockieren die Finalisierung. Bei einem ausdrücklichen Bewerbungsauftrag des Nutzers wird `bewerbungsentscheidung = bewerben` gesetzt, auch wenn die Eignungsklasse Risiken oder `stretch` ausweist. `nicht_bewerben` dokumentiert ausschließlich einen ausdrücklichen Abbruch oder eine entsprechende Entscheidung des Nutzers; der Agent darf den Nutzerauftrag nicht allein aufgrund einer Eignungskennzahl aufheben. `nicht_bewerben` darf nicht veröffentlicht werden.

Ab Schema 4 ist `dokumentumfang` Pflicht und steuert alle erwarteten Kandidaten-, Prüf- und Versandartefakte. Die alte Schema-3-Abbildung bleibt nach Prompt 01 rückwärtskompatibel. Ein eingefrorener universeller Lebenslauf darf nicht verändert werden; die Zielrollenprüfung gilt für die zusätzlich ausgewählten stellenbezogenen Dokumente, nicht für den universellen Snapshot.

Vor der Dokumenterstellung müssen alle blockierenden Rückfragen und Widersprüche geklärt sein. Neue Angaben bleiben standardmäßig `nur_auftrag`. Eine dauerhafte Profilaktualisierung benötigt die bestätigte Formulierung, die zulässige Zieldatei, ausdrückliche Zustimmung sowie einen konsistenten Vorher-/Nachher-Hash; Rohchats werden nicht gespeichert.

Firma, Rolle und Pfade in dieser Datei dürfen nach der Dokumenterstellung nicht stillschweigend geändert werden.

## Anforderungsmatrix

Vor der Erstellung der ausgewählten Bewerbungsdokumente muss aus `Anforderungsmatrix--ENTWURF.json` eine geprüfte `Anforderungsmatrix.json` entstehen. Der Agent kann während des Profilabgleichs Anforderungen und Belege im Entwurf sammeln; die endgültigen Werte für Gewichtung und `behandlung` werden erst nach der Profil- und Dokumentstrategie festgelegt.

Jede relevante Anforderung erhält:

- `id`: stabile technische Kennung
- `anforderung`: konkrete Anforderung aus der Anzeige
- `typ`: `muss` oder `kann`
- `kategorie`: `fachlich`, `erfahrung`, `formal`, `arbeitsweise` oder `logistik`
- `gewichtung`: `kritisch`, `hoch`, `mittel` oder `niedrig`
- `status`: `erfuellt`, `teilweise`, `nicht_belegt`, `unklar` oder `nicht_relevant`
- `belegart`: passende Belegart aus der fachlichen Profildatei
- `beleg`: kurze, konkrete Datengrundlage
- `behandlung`: Verwendung in Lebenslauf, Anschreiben, Analyse oder offenen Fragen

Neue Bewerbungen verwenden für `Anforderungsmatrix.json` Schema 5. Die Schemata 1 bis 4 bleiben für vorhandene Bewerbungen lesbar und werden nicht automatisch migriert. Eine ausdrückliche Migration erfolgt ausschließlich über das Subcommand `migrieren` des jeweiligen Plattform-Dispatchers; fachlich nicht ableitbare Felder werden als private Entwürfe mit offenen Ergänzungen ausgegeben. Schema 5 übernimmt die verbindliche `recruiterStrategie` aus Schema 4, ergänzt `anschreibenStrategie` und `externeQuellen` sowie eine unabhängige Beweiskette:

- `stellenanzeigeAbdeckung`: SHA-256 der vollständig gespeicherten `Stellenbeschreibung.md` und zeilengebundene `fundstellen`. Jede Fundstelle enthält stabile ID, Zeilenbereich, exakten Text, Klassifikation (`anforderung`, `aufgabe` oder `nicht_anforderung`) sowie zugeordnete Matrix-IDs oder eine konkrete Begründung.
- `stellenFundstellen`: mindestens eine Fundstellen-ID je Matrixanforderung. Explizite Muss-/Kann-Signale und Aufgaben der Anzeige dürfen weder stillschweigend fehlen noch nur durch eine freie Analyse behauptet werden.
- `Evidenzindex.json`: eigenständiger, privater Index mit SHA-256 der fachlichen Profildatei. Profileinträge haben stabile ID, Zeilenbereich, exakten Profiltext und Belegart. Bestätigte auftragsbezogene Dialogangaben dürfen ebenfalls verwendet werden, aber nur mit `auftragSha256`, `angabeId`, exakter normalisierter Angabe und bestätigtem Wahrheitsstatus. Die menschenlesbare Profildatei beziehungsweise der bestätigte Auftrag bleiben die fachlichen Quellen.
- `belegRefIds`: bei erfüllten oder teilweise erfüllten Anforderungen zwingende Evidenz-IDs. `NICHT BEHAUPTEN` und `EINARBEITUNGSZIEL` sind keine Direktbelege.
- `anschreibenStrategie`: Bei ausgewähltem Anschreiben `status = final` und grundsätzlich zwei bis vier Argumente; bei einem als `schmal` dokumentierten Profil ist ein Argument zulässig. Jedes Argument enthält `anforderungIds`, `belegRefIds`, `stellenFundstellen` oder eine Unternehmensquelle, `arbeitgeberbezug`, `nutzenargument` und sichtbare Textanker.
- `externeQuellen`: Liste strukturierter Unternehmens- oder Gehaltsquellen mit ID, Typ, Titel, Herausgeber, URL, Abrufzeit, optionalem Quellenstand, Aussage und Verwendungen. Eine leere Liste ist zulässig, solange keine externe Aussage verwendet wird.

Die `recruiterStrategie` enthält weiterhin:

- `kernbotschaft`: präzise, stellenbezogene Positionierung; keine austauschbare Eigenschaftssammlung.
- `profilSubstanz`: `ausreichend`, wenn mindestens zwei personenspezifische, rollenrelevante Belege für einen individuellen Lebenslauf vorliegen, sonst `schmal`.
- `profilSubstanzBegruendung`: konkrete Begründung anhand des tatsächlich verfügbaren Profils.
- `prioritaetsAnforderungen`: nach Recruiter-Relevanz geordnete Matrix-IDs. Alle kritischen oder hoch gewichteten fachlichen beziehungsweise erfahrungsbezogenen Anforderungen müssen enthalten sein.
- `profilHighlights`: belegte Stationen, Projekte, Qualifikationen oder Kenntnisse mit `id`, `anforderungIds`, `belegart`, verpflichtenden `belegRefIds`, `relevanz` (`hoch`, `mittel`, `niedrig`), `zielDokument` (`lebenslauf`, `anschreiben` oder `email_nachricht`), `platzierung` (`seite_1` nur im Lebenslauf, sonst `beliebig`) und konkreten `sichtbareAnker`n aus dem Dokumenttext.
- `transferbruecken`: für teilweise oder nicht direkt belegte Anforderungen mit `anforderungId`, `zieltechnologie`, `basisHighlightIds`, zulässiger `formulierungsebene` (`ÜBERTRAGBAR`, `GRUNDLAGEN / VERSTÄNDNIS` oder `EINARBEITUNGSZIEL`), `zielDokument`, `platzierung` und `sichtbareAnker`n.
- `auslassungen`: bewusst nicht verwendete Profilinhalte mit `thema`, konkreter `begruendung`, optionaler `anforderungId` und bei Profilinhalten `belegRefIds`. Jede Evidenz-ID des vollständigen Index muss entweder in einer Verwendung oder in genau einer begründeten Auslassung erscheinen.

Ein Highlight ist kein abstraktes Schlagwort. Sein sichtbarer Text muss Zweck oder Aufgabe, eingesetzte Kenntnisse beziehungsweise Technologien und den konkreten eigenen Beitrag so weit benennen, wie die Profildaten dies belegen. Bei Stationen darf derselbe Nachweis auch durch mehrere eng zusammengehörige Formulierungen entstehen.

Eine Transferbrücke ist keine Ersatzbehauptung. Sie nennt die Zieltechnologie nur auf der zulässigen Wahrheitsebene und verweist auf mindestens ein vorhandenes Highlight mit einer verwandten, belastbaren Grundlage. Ein bloßes `EINARBEITUNGSZIEL` ist keine ausreichende Grundlage. Ohne verwandten Beleg wird die Lücke begründet ausgelassen oder intern dokumentiert.

Für einen individuellen Lebenslauf werden die wichtigsten bis zu drei belegbaren Recruiter-Signale auf Seite 1 verankert. Kritische oder hoch gewichtete erfüllte beziehungsweise teilweise erfüllte Anforderungen benötigen einen sichtbaren Direktbeleg im vorgesehenen Dokument. Bei ausreichender Profilsubstanz müssen mindestens zwei personenspezifische Highlights im Lebenslauf sichtbar sein. Ein tatsächlich schmales Profil wird nicht künstlich aufgefüllt, sondern mit konkreten Auslassungen beziehungsweise Substanzgrenzen dokumentiert.

### Normalisierung und Deduplizierung

- Erfasse nur eigenständige, entscheidungsrelevante Anforderungen. Wiederholungen, Synonyme und dieselbe Anforderung in Aufgaben- und Profilabschnitt werden zu genau einem Eintrag zusammengeführt.
- Eine sprachliche Wiederholung in der Anzeige darf Gewicht oder Eignungspunktzahl nicht mehrfach erhöhen.
- Explizite Pflichtformulierungen und objektiv notwendige Voraussetzungen werden `muss`; ausdrücklich optionale oder bevorzugte Punkte werden `kann`. Reine Unternehmenswerbung, Benefits und allgemeine Floskeln sind keine Anforderungen.
- Kernaufgaben werden nur dann als Muss-Anforderung gewertet, wenn ihre Ausübung eine konkrete Fähigkeit oder Voraussetzung erfordert. Andernfalls dienen sie der Strategie, ohne eine zusätzliche Scoring-Zeile zu erzeugen.
- Mehrere eng zusammengehörige Werkzeuge dürfen in einer Anforderung gebündelt werden, wenn Beleg, Status und Behandlung identisch sind. Unterschiedliche Belegarten oder wesentlich unterschiedliche Risiken bleiben getrennt.
- Es gibt keine starre Zeilenzahl. Die Matrix bleibt jedoch so klein wie möglich und so vollständig wie für Eignungsentscheidung und Dokumente nötig.
- `Analyse.md` verweist bevorzugt auf Matrix-IDs, statt Anforderungen, Belege und Bewertungen vollständig zu wiederholen.

Bei einer bestätigten reinen E-Mail-Nachricht enthält die Matrix nur die für Zielrolle, Versandzweck, konkrete Bewerbungsfragen und relevante Logistik notwendigen Punkte. CV-Chronologie, vollständige Kompetenzinventur, Seitenstrategie und Profil-Links sind dafür `nicht_erforderlich` und werden nicht künstlich analysiert.

Beispiel:

```json
{
  "id": "muss-berufserfahrung",
  "anforderung": "mindestens fünf Jahre Berufserfahrung",
  "typ": "muss",
  "kategorie": "erfahrung",
  "gewichtung": "kritisch",
  "status": "teilweise",
  "belegart": "ÜBERTRAGBAR",
  "beleg": "mehr als 20 Jahre technische Berufserfahrung, jedoch keine fünf Jahre berufliche Webentwicklung",
  "behandlung": "technische Berufserfahrung im Lebenslauf belegen; Auslegungsrisiko in Analyse und offenen Fragen dokumentieren"
}
```

## Entscheidungslogik

- Der Inhaltsprüfer berechnet eine gewichtete Eignungsbewertung. `erfuellt` zählt vollständig, `teilweise` zur Hälfte und `nicht_belegt`/`unklar` nicht; `nicht_relevant` wird aus der Berechnung entfernt.
- `stark` bedeutet mindestens 80 Prozent ohne kritische Lücke. `vertretbar_mit_risiken` bedeutet mindestens 55 Prozent und höchstens eine kritische Lücke. Alles darunter wird als `stretch` ausgewiesen.
- Die Kennzahl ersetzt kein fachliches Urteil. Sie erzwingt eine ausdrückliche Entscheidung im Bewerbungsauftrag und macht Risiken sichtbar; sie darf keine belegbaren Stärken wegfiltern und keine fehlenden Belege schönrechnen.
- Nicht belegte fachliche Anforderungen verhindern eine ausdrücklich gewünschte Bewerbung nicht automatisch.
- Nicht oder nur teilweise belegte Muss-Anforderungen müssen eine dokumentierte Behandlung besitzen.
- Identitätsfehler, widersprüchliche Bewerbungslogistik und ungeklärte zentrale persönliche Entscheidungen blockieren die finale Veröffentlichung.
- Risiken und Grenzen gehören vorrangig in Analyse, Qualitätscheck oder offene Fragen. Im Anschreiben werden sie nur genannt, wenn dies zur Vermeidung einer Irreführung zwingend nötig ist.
- Das Anschreiben bleibt positiv und belegorientiert. Defensive Metaformulierungen wie `nicht belegt`, `noch keine Erfahrung` oder `ohne daraus Berufserfahrung abzuleiten` sind zu vermeiden.

## Kandidatenordner

Versandfertig benannte, aber noch nicht veröffentlichte Dateien liegen ausschließlich unter:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat/
```

Der finale Zielordner bleibt bis nach fachlichem Check, statischem Check, Layoutcheck, visueller Sichtprüfung und PDF-Validierung leer.
