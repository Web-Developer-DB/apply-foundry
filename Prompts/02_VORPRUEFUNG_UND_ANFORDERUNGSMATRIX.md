# Vorprüfung und Anforderungsmatrix

## Ziel

Vor dem Schreiben einer Bewerbung müssen Stammdaten, Bewerbungslogistik und Stellenanforderungen strukturiert geprüft werden. Freie Analyseabsätze allein reichen nicht aus, weil unklare Muss-Kriterien oder nicht gepflegte persönliche Entscheidungen sonst erst während der Finalisierung auffallen.

## Stammdatenprüfung

Unter PowerShell zuerst ausführen:

```powershell
.\Tools\Pruefe-Stammdaten.ps1
```

Pflichtangaben zu Identität und Kontakt dürfen keine Beispielplatzhalter enthalten. Die zentralen Entscheidungen zu gewünschter Stellenart, gewünschtem Arbeitsmodell, Verwendung eines Gehaltswunschs und Gehaltslogik müssen vor der finalen Freigabe eindeutig gepflegt sein.

Ungeklärte zentrale Bewerbungslogistik wird bei der Finalisierung zum Blocker. Optionale Angaben dürfen offen bleiben, müssen aber als Warnung sichtbar sein und dürfen nicht erfunden werden.

## Bewerbungsauftrag

`Tools/Neue-Bewerbung.ps1` beziehungsweise `Tools/neue-bewerbung.sh` erzeugt im privaten Arbeitsordner eine Datei `Bewerbungsauftrag.json`.

Sie enthält mindestens:

- Firma und technischer Firmenslug
- Zielrolle und technischer Rollenslug
- Bewerbungsdatum
- Dateiname-Name des Bewerbers, sofern verfügbar
- finalen Zielordner
- privaten Arbeitsordner
- Kandidatenordner
- geplante Seitenstrategie

Vor der Inhaltsprüfung muss `seitenstrategie` auf `eine_seite` oder `zwei_seiten` gesetzt werden. Der Wert `noch_festzulegen` ist nur im initialen Arbeitsauftrag erlaubt und blockiert die Finalisierung.

Firma, Rolle und Pfade in dieser Datei dürfen nach der Dokumenterstellung nicht stillschweigend geändert werden.

## Anforderungsmatrix

Vor Lebenslauf und Anschreiben muss aus `Anforderungsmatrix--ENTWURF.json` eine geprüfte `Anforderungsmatrix.json` entstehen.

Jede relevante Anforderung erhält:

- `id`: stabile technische Kennung
- `anforderung`: konkrete Anforderung aus der Anzeige
- `typ`: `muss` oder `kann`
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
  "status": "teilweise",
  "belegart": "ÜBERTRAGBAR",
  "beleg": "mehr als 20 Jahre technische Berufserfahrung, jedoch keine fünf Jahre berufliche Webentwicklung",
  "behandlung": "technische Berufserfahrung im Lebenslauf belegen; Auslegungsrisiko in Analyse und offenen Fragen dokumentieren"
}
```

## Entscheidungslogik

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
