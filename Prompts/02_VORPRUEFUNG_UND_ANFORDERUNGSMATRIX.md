# Vorprüfung und Anforderungsmatrix

## Ziel

Vor dem Schreiben einer Bewerbung müssen Stammdaten, Bewerbungslogistik und Stellenanforderungen strukturiert geprüft werden. Freie Analyseabsätze allein reichen nicht aus, weil unklare Muss-Kriterien oder nicht gepflegte persönliche Entscheidungen sonst erst während der Finalisierung auffallen.

## Stammdatenprüfung

Unter PowerShell zuerst ausführen:

```powershell
.\Tools\Pruefe-Stammdaten.ps1
```

Pflichtangaben zu Identität und Kontakt dürfen keine Beispielplatzhalter enthalten. Die zentralen Entscheidungen zu gewünschter Stellenart, gewünschtem Arbeitsmodell, Verwendung eines Gehaltswunschs und Gehaltslogik müssen vor der finalen Freigabe eindeutig gepflegt sein.

Der Ordnerhelfer kopiert die Bewerbungslogistik aus Datei `01` als Snapshot in `Bewerbungsauftrag.json`. Ab diesem Zeitpunkt ist dieser bewerbungsspezifische Snapshot für die konkrete Bewerbung maßgeblich; Datei `01` bleibt nur die Rückfallquelle für ältere Aufträge. So kann eine Bewerbung beispielsweise bewusst `Vollzeit` und `hybrid` verwenden, ohne globale Stammdaten für andere Bewerbungen umzuschreiben.

Ungeklärte zentrale Bewerbungslogistik im Bewerbungsauftrag wird bei der Finalisierung zum Blocker. Optionale Angaben dürfen offen bleiben, müssen aber als Warnung sichtbar sein und dürfen nicht erfunden werden.

## Bewerbungsauftrag

`Tools/Neue-Bewerbung.ps1` beziehungsweise `Tools/neue-bewerbung.sh` erzeugt im privaten Arbeitsordner eine Datei `Bewerbungsauftrag.json`.

Sie enthält mindestens:

- Dokumentmodus: `vollbewerbung` oder `anschreiben_mit_universalem_lebenslauf`
- im Anschreiben-Modus: Pfad, Dateiname und SHA-256-Snapshot der freigegebenen Universal-Lebenslauf-HTML
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

- `seitenstrategie`: `eine_seite` oder `zwei_seiten`
- `bewerbungsentscheidung`: `bewerben` oder `nicht_bewerben`
- `darstellungsoptionen.schulbildungsmodus`: `vollstaendig` oder `recruiter_kompakt`
- `darstellungsoptionen.profillinksModus`: `alle`, `rollenrelevant` oder `keine`
- bei `rollenrelevant`: `profillinksAuswahl` mit den tatsächlich verwendeten Feldnamen aus Datei `01`

Die Werte `noch_festzulegen` sind nur im initialen Arbeitsauftrag erlaubt und blockieren die Finalisierung. `nicht_bewerben` dokumentiert einen bewussten Abbruch und darf nicht veröffentlicht werden.

Ab Schema 3 ist der Dokumentmodus Pflicht. Im Anschreiben-Modus darf der eingefrorene universelle Lebenslauf nicht verändert werden. Die Zielrollenprüfung gilt dann für Anschreiben und E-Mail-Betreff, nicht für den universellen Lebenslauf.

Firma, Rolle und Pfade in dieser Datei dürfen nach der Dokumenterstellung nicht stillschweigend geändert werden.

## Anforderungsmatrix

Vor Lebenslauf und Anschreiben muss aus `Anforderungsmatrix--ENTWURF.json` eine geprüfte `Anforderungsmatrix.json` entstehen.

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
