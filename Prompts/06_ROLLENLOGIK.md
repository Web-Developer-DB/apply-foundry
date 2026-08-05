# Rollenlogik

## Ziel

Die Stellenbeschreibung entscheidet, welche Teile des privaten Profils hervorgehoben, gekürzt oder ausgelassen werden.

Der Agent ist neutral. Er darf keine Branche, keine konkrete Fachrolle, keine Verwaltungstätigkeit, keinen Pflegekontext, keinen Verkaufskontext und kein anderes Berufsbild als Standard voraussetzen. Das konkrete Bewerbungsprofil entsteht immer aus der Kombination von Stellenbeschreibung und privaten Profildaten.

## Vorgehen

1. Zielrolle erkennen.
2. Branche, Arbeitsfeld und typische Aufgaben erkennen.
3. Muss-Anforderungen erkennen.
4. Kann-Anforderungen erkennen.
5. Gewünschte Arbeitsweise, Soft Skills, Tools, Methoden, Systeme oder Fachkenntnisse extrahieren.
6. Stellenart, Arbeitsmodell, Standort/Region, Eintrittstermin, Reise- oder Schichtanforderungen und Gehaltsanforderung erkennen.
7. Seniorität oder Einstiegsniveau ableiten.
8. Firmengröße oder Organisationsart ableiten, falls Hinweise vorhanden sind.
9. Private Profildaten auf echte Belege prüfen.
10. Bewerbungslogistik aus dem Snapshot in `Bewerbungsauftrag.json` prüfen und mit der Anzeige abgleichen.
11. Belegarten aus `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` auswerten, falls vorhanden.
12. Profilstrategie festlegen.
13. Beweislogik festlegen: Welche Stationen, Weiterbildungen, Projekte oder Praxisbelege tragen die Zielrolle wirklich?
14. Risiken, Lücken oder fehlende formale Anforderungen erkennen.
15. Irrelevante Inhalte bewusst reduzieren.

## Bewerbungsprofil

Vor der Erstellung der ausgewählten Bewerbungsdokumente wird eine kurze Profilstrategie erstellt:

- Zielrolle
- Branche oder Arbeitsfeld
- Erfahrungsart
- Seniorität oder Einstiegsniveau
- Firmengröße oder Organisationsart, falls erkennbar
- Stellenart der Anzeige und bewerbungsspezifische Stellenart aus `Bewerbungsauftrag.json`
- Arbeitsmodell, Region, Eintrittstermin, Reise- oder Schichtanforderungen, falls relevant
- Gehaltsstrategie: manuelle Angabe, automatische Schätzung, nur bei ausdrücklicher Anforderung oder keine Angabe
- wichtigste Anforderungen der Stelle
- stärkste belegbare Argumente aus den privaten Daten
- Belegarten-Logik: beruflich belegte Erfahrung, übertragbare Erfahrung, Weiterbildung, Projektpraxis, private Praxis, Grundlagen, Einarbeitungsziele und nicht zu behauptende Inhalte
- Zusatzkenntnisse mit Nutzen
- Beweislogik für Personalverantwortliche: welche Belege im Lebenslauf die Passung in 10 bis 20 Sekunden sichtbar machen
- offene Risiken, Lücken oder fehlende formale Anforderungen
- bewusst weggelassene Inhalte
- gewichtete Eignungsklasse und ausdrückliche Bewerbungsentscheidung
- Schulbildungsmodus und begründete Auswahl öffentlicher Profil-Links
- bestätigter Dokumentumfang und, falls ausgewählt, Eignung des universellen Lebenslaufs als unveränderte Basis

Diese Strategie wird in `Analyse.md` dokumentiert.

Bei einem universellen Lebenslauf beeinflusst die Rollenstrategie dessen Inhalt nicht. Sie bestimmt, welche belegten Argumente ein ausgewähltes Anschreiben ergänzend hervorhebt und ob der universelle Lebenslauf für die konkrete Bewerbung ausreichend ist.

## Gewichtung nach Rolle

Für jede Information aus den privaten Daten gilt:

1. Direkt relevant: sichtbar und früh platzieren.
2. Teilweise relevant: kurz aufnehmen, wenn sie die Passung stärkt.
3. Nur allgemein positiv: nur aufnehmen, wenn Platz vorhanden ist und kein stärkerer Inhalt verdrängt wird.
4. Irrelevant oder ablenkend: weglassen.

Zusatzkenntnisse dürfen nicht automatisch übernommen werden. Sie brauchen einen Nutzen für die konkrete Zielrolle.

Die gewichtete Anforderungsmatrix macht aus dieser Priorisierung eine prüfbare Entscheidungshilfe. Ein hoher Score erlaubt keine Übertreibung; ein niedriger Score löscht keine echten Transferstärken. Die Einstufung `stark`, `vertretbar_mit_risiken` oder `stretch` wird in `Analyse.md` festgehalten und führt zu einer ausdrücklichen Entscheidung im Bewerbungsauftrag.

## Belegarten-Gewichtung

Wenn Datei `02` Belegarten enthält, gilt:

- `BERUFLICH BELEGT`: darf als Berufserfahrung oder berufliche Stärke formuliert werden.
- `ÜBERTRAGBAR`: darf als Brücke zur Zielrolle formuliert werden, aber nicht als direkte Rollenpraxis.
- `WEITERBILDUNG`: als Weiterbildung, Qualifikation oder Lernbasis formulieren.
- `PROJEKTPRAXIS`: als Projektpraxis formulieren, nicht als Anstellung.
- `PRIVATE PRAXIS / HOME-LAB`: immer als privat, Home-Lab oder eigene Systeme kennzeichnen.
- `GRUNDLAGEN / VERSTÄNDNIS`: nur als Grundlagen, Verständnis oder Basiswissen formulieren.
- `EINARBEITUNGSZIEL`: nur als Einarbeitung, Lernziel, Vertiefung oder Entwicklungsperspektive formulieren.
- `NICHT BEHAUPTEN`: nicht als Erfahrung, Verantwortung, sichere Kompetenz oder Rollenpraxis verwenden.

Bei Konflikten gilt die vorsichtigere Belegart. Beispiel: Eine Technologie, die sowohl in einer Wunschrolle als auch unter `EINARBEITUNGSZIEL` steht, darf nicht als vorhandene Erfahrung erscheinen.

## Bewerbungslogistik und Gehalt

Stellenart, Arbeitsmodell, Eintrittstermin, Region, Reisebereitschaft, Schichtbereitschaft, Befristung und Gehaltswunsch sind Bewerbungslogistik. Datei `01` ist die Stammquelle; der bei der Anlage erzeugte Snapshot in `Bewerbungsauftrag.json` ist für die konkrete Bewerbung maßgeblich.

- Stellenart muss für alle ausgewählten Bewerbungsdokumente ausgewertet werden: `Vollzeit`, `Teilzeit` oder `Vollzeit/Teilzeit`.
- Die Stellenanzeige wird auf angebotene oder geforderte Stellenart geprüft. Bei Widerspruch zum Bewerbungsauftrag wird der Punkt in `Offene_Fragen.md` dokumentiert.
- Arbeitsmodell, Region, Pendeldistanz, Reisebereitschaft, Schicht- oder Wochenendbereitschaft und Befristung werden nur sichtbar gemacht, wenn sie für die konkrete Bewerbung relevant sind.
- Eine manuelle Gehaltsangabe im Bewerbungsauftrag hat Vorrang.
- Eine automatische Gehaltsschätzung ist nur zulässig, wenn sie im Bewerbungsauftrag ausdrücklich aktiviert ist. Sie wird aus einer aktuellen, nachvollziehbaren Quelle sowie Zielrolle, Seniorität, einschlägiger Berufserfahrung, Region, Arbeitsmodell und Stellenart abgeleitet. Alter, Geschlecht und andere geschützte persönliche Merkmale bleiben unberücksichtigt. Quelle, Stand und Begründung werden kurz in `Analyse.md` festgehalten.
- Wenn die Stellenanzeige eine Gehaltsvorstellung verlangt, muss der Agent prüfen, ob ein Gehalt genannt werden darf, automatisch geschätzt werden soll oder eine offene Frage entsteht.
- Wenn die Datengrundlage nicht reicht oder keine aktuelle Quelle geprüft werden kann, wird keine Scheingenauigkeit erzeugt. Dann wird `Offene_Fragen.md` genutzt.

## Rollenbezogene Profil-Links

GitHub-, Portfolio-, LinkedIn- oder Xing-Links werden nicht automatisch vollständig übernommen. Für jede Bewerbung wird `alle`, `rollenrelevant` oder `keine` gewählt. Im Modus `rollenrelevant` muss jeder ausgewählte Link die Zielrolle sichtbar stützen; nicht ausgewählte Links bleiben aus dem Lebenslauf entfernt. Die Auswahl ändert keine URL in den Stammdaten und wird in der Analyse knapp begründet.

## Formale CV-Stationen

Die Rollenstrategie darf Inhalte gewichten, aber sie darf den deutschen Lebenslaufstandard nicht auflösen.

- Berufserfahrung und Ausbildung/Studium/berufliche Bildung bleiben als formale Stationen erkennbar. Schulbildung bleibt mindestens als Abschlussangabe sichtbar.
- Rollenrelevanz entscheidet über Detailtiefe und Reihenfolge, aber nicht darüber, ob berufliche Stationen, Ausbildung/Umschulung/Studium oder formale Weiterbildungen mit Zeitraum entfernt werden. Schulbildung bleibt im Modus `vollstaendig` mit Chronologie sichtbar und darf nur im ausdrücklich gesetzten Modus `recruiter_kompakt` auf eine wahre Abschlussangabe verdichtet werden.
- Formale CV-Stationen werden fachlich aus `Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` entnommen; `Private/Daten/01_PERSOENLICHE_DATEN.md` ist die Stammquelle für Identität, Kontakt, Dateiname-Name und den Logistik-Snapshot.
- Für die Rolle relevante Projekte, private Praxis und Zusatzkenntnisse dürfen formale Stationen ergänzen, aber nicht ersetzen.
- Bei Quereinstieg, Rollenwechsel oder wenig klassischer Berufserfahrung werden formale Stationen ehrlich dargestellt und durch passende Praxisbelege ergänzt.
- Wenn formale Daten fehlen, werden sie nicht erfunden und nicht durch scheinbar berufliche Projektformulierungen kaschiert.
- Entwicklungsfelder werden klar von vorhandener Erfahrung getrennt. Sie dürfen sichtbar sein, wenn die Stelle Lernbereitschaft oder Einarbeitung betont.
- Private Praxis, Weiterbildung, Projektpraxis und Grundlagen dürfen formale Stationen ergänzen, müssen aber sichtbar als solche gekennzeichnet bleiben.
- Der Lebenslauf muss trotz Rollenstrategie wie ein deutscher tabellarischer CV funktionieren.

## Gewichtung nach Firmengröße

Wenn die Stellenbeschreibung auf eine große Organisation, Konzernstruktur, öffentliche Einrichtung oder stark standardisierte Prozesse hindeutet:

- klare Rollenpassung priorisieren
- Muss-Anforderungen und Keywords früh sichtbar machen
- weniger Nebenprojekte und weniger Breite zeigen
- kurze, schnell erfassbare Formulierungen nutzen

Wenn die Stellenbeschreibung auf ein kleines Unternehmen, Startup, lokale Einrichtung, Verein oder sehr breite Aufgaben hindeutet:

- Allrounder-Qualitäten dürfen sichtbarer sein
- Zusatzkenntnisse können als Anpassungsfähigkeit und Lernsignal genutzt werden
- trotzdem nur aufnehmen, wenn sie einen konkreten Nutzen erklären

Wenn keine Firmengröße erkennbar ist:

- konservativ arbeiten: Rollenpassung zuerst, Zusatzkenntnisse knapp und nur mit Nutzen.

## Beispiele für neutrale Gewichtung

Bei einer kaufmännischen Rolle zählen z. B. Organisation, Genauigkeit, Kommunikation, Dokumentation, Kundenkontakt und relevante Zusatzkenntnisse stärker als fachfremde Projekte.

Bei einer technischen Rolle zählen z. B. Problemlösung, Systemverständnis, Dokumentation, Tools, Sicherheit, Qualität und nachvollziehbare Praxis stärker als rein fachfremde Details.

Bei einer sozialen, pflegerischen oder pädagogischen Rolle zählen z. B. Verlässlichkeit, Empathie, Belastbarkeit, Kommunikation, Dokumentation und relevante Erfahrung stärker als unverbundene Zusatzthemen.

Bei einer Quereinstiegsrolle zählen übertragbare Erfahrungen, Lernfähigkeit und glaubwürdige Motivation stärker als künstlich behauptete Berufserfahrung.

Diese Beispiele sind keine festen Branchenvorgaben. Die privaten Daten und die Stellenbeschreibung entscheiden.

## Dokumentation

Die gewählte Strategie wird in `Analyse.md` und am Ende von `Qualitaetscheck.md` kurz festgehalten.

Unsichere Punkte werden in `Offene_Fragen.md` dokumentiert.
