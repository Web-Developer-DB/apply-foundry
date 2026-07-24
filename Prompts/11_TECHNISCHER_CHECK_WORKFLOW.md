# Technischer Check-Workflow

## Ziel

Dieser Workflow verhindert wiederkehrende technische Probleme bei der Erstellung und Prüfung finaler Bewerbungsunterlagen.

Er ergänzt den inhaltlichen Qualitätscheck. Er ersetzt nicht die fachliche Prüfung aus `Prompts/09_QUALITAETSCHECK.md`, sondern sorgt dafür, dass Dateien, Pfade, Platzhalter und A4-Grundstruktur technisch sauber sind.

## Grundregeln für Agenten

- Kritische Eingabedateien unter Windows bevorzugt sequenziell lesen, wenn parallele PowerShell-Prozesse fehlschlagen oder instabil wirken.
- Bei Textsuche mit `rg` keine Pfad-Wildcards wie `ORDNER/*.html` verwenden. Stattdessen:

```powershell
rg -g "*.html" "SUCHMUSTER" "ORDNER"
```

- Browser- oder Headless-Checks nur als bestanden werten, wenn die erwartete Ausgabe im aktuellen Lauf frisch erzeugt wurde, die korrekte Dateisignatur und die erwarteten Abmessungen besitzt.
- Wenn ein Browser-Layoutcheck keine Datei erzeugt, ist das kein bestandener Layoutcheck. Dann muss der Fehler klar dokumentiert werden.
- Finale Bewerbungsdateien dürfen erst gemeldet werden, nachdem mindestens der statische Check erfolgreich war.
- PDFs dürfen erst erzeugt werden, nachdem der statische Check erfolgreich war.
- Versandfertige Dateien werden zunächst im privaten `Kandidat`-Ordner geprüft. Der finale Zielordner bleibt bis zur atomaren Veröffentlichung leer.
- Eine Änderung an einer HTML-Datei nach dem Layoutcheck macht den bisherigen Screenshot- und PDF-Nachweis ungültig. Maßgeblich sind die SHA-256-Werte in den Prüfberichten.
- Kandidatendateien einzeln und vollständig schreiben und danach unmittelbar validieren. Insbesondere JSON-Dateien nach jeder Änderung parsen; keine unübersichtliche Sammeländerung darf bei einem Teilfehler mehrere fertige Dokumente halb aktualisiert zurücklassen.
- In einer als verwaltete Sandbox bekannten Umgebung den ersten browsergestützten Lauf direkt mit lokaler Browserfreigabe ausführen, statt einen erwartbaren Browser-Fehlerlauf zu provozieren.

## Verbindlicher Finalisierungsworkflow

Der Standardweg verwendet `Tools/Finalisiere-Bewerbung.ps1` und den privaten Arbeitsordner.

Vorbereitung mit allen maschinellen Prüfungen:

```powershell
.\Tools\Finalisiere-Bewerbung.ps1 -Arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" -Browser auto
```

Dieser Lauf:

- verlangt eine vollständige `Anforderungsmatrix.json`
- sperrt ungeklärte zentrale Bewerbungslogistik
- führt Stammdaten-, Inhalts- und statischen HTML-Check aus
- erzeugt frische Layoutscreenshots samt Dichtehinweisen
- exportiert und validiert beide PDFs
- prüft die PDF-Textschicht und Lesbarkeit für ATS
- schreibt Hashnachweise für Quellen, sämtliche Kandidatendateien, PDFs und Seitenscreenshots
- veröffentlicht noch keine Datei

Nach der tatsächlichen Sichtprüfung:

```powershell
.\Tools\Finalisiere-Bewerbung.ps1 -Arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" -Veroeffentlichen -VisuellGeprueft
```

Liegen automatische Layoutwarnungen vor, muss zusätzlich eine konkrete Sichtbewertung angegeben werden, zum Beispiel `-VisuelleFreigabeNotiz "Alle markierten Seiten geprüft; kein Beschnitt und keine Überlappung."`.

Die Veröffentlichung wird verweigert, wenn Quellen, Kandidatendateien oder Screenshots nach der Vorbereitung verändert wurden. Sie kopiert nicht dateiweise in den Zielordner, sondern veröffentlicht das validierte Set über einen privaten Staging-Ordner gemeinsam. Das Ergebnis trennt `Versand/` mit genau zwei PDF-Anlagen und E-Mail-Text von `Intern/` mit HTML-Quellen und Nachweisen. `Manifest.json` bindet jede veröffentlichte Datei an ihren SHA-256-Wert.

Die nachfolgenden Einzelwerkzeuge bleiben für Diagnose, Entwicklung und gezielte Wiederholungen verfügbar. Für neue Bewerbungen ersetzt ihre manuelle Verkettung nicht den verbindlichen Finalisierungsworkflow.

## Pflichtprüfung nach jeder Bewerbung

Nach dem Erstellen der finalen Bewerbungsdateien soll, sofern eine PowerShell-Umgebung verfügbar ist, dieser statische Prüfer ausgeführt werden:

```powershell
.\Tools\Pruefe-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Der Prüfer kontrolliert:

- nichtleere Pflichtdateien im finalen Bewerbungsordner; Verzeichnisse mit Dateinamen zählen nicht
- korrekte Versanddateien für Lebenslauf und Anschreiben
- keine sichtbaren Platzhalter oder Entwurfsmarker
- keine Entwurfsdateien im finalen Bewerbungsordner
- exakte A4-Grundstruktur mit `width: 210mm` und `height: 297mm`
- exakt eine Anschreibenseite sowie ein oder zwei explizite Lebenslaufseiten mit konsistenten Seiten-Footern
- eingebettetes CSS ohne automatisch geladene externe oder lokale Ressourcen, Skripte, Fonts, Medien oder CDNs
- `overflow: hidden` nur auf der äußeren A4-Seite
- kurze, platzhalterfreie E-Mail-Nachricht mit konkretem `Betreff:` in der ersten Zeile
- bei strukturierten Veröffentlichungen: korrekte `Versand/`-/`Intern/`-Trennung und vollständiges Hash-Manifest

Nur wenn der Prüfer mit `OK` endet, darf der technische Abschlusscheck als bestanden gelten.

## Optionaler Layoutcheck

Wenn ein lokaler Browser verfügbar ist, kann zusätzlich ein visueller Layoutcheck erzeugt werden:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Der Layoutcheck:

- sucht finale HTML-Dateien im Bewerbungsordner
- erzeugt Screenshots im passenden privaten Arbeitsordner unter `_Arbeitsdateien`
- schreibt keine Kontrollbilder in den finalen Bewerbungsordner
- prüft nach jedem Browserlauf, ob die Ausgabedatei wirklich erzeugt wurde
- entfernt alte erwartete Ausgaben vor dem Lauf und akzeptiert keine veralteten Dateien
- validiert PNG-Signatur, Aktualität und exakte Bildabmessungen
- beendet hängende Browser nach dem konfigurierten Timeout
- meldet Fehler sichtbar, statt stille Browserfehler zu übergehen

Als Einzelwerkzeug ist der Browser-Layoutcheck für Diagnose optional. Im verbindlichen Finalisierungsworkflow ist er Voraussetzung für die Veröffentlichung. Wenn er wegen lokaler Browser- oder Sandbox-Einschränkungen nicht läuft, darf der statische Check zwar separat ausgewertet, die Bewerbung aber nicht als vollständig finalisiert veröffentlicht werden.

## Standardweg unter Windows 11 / VS Code / PowerShell

Im Standardweg wählt das Skript automatisch einen unterstützten installierten Browser aus:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -Browser auto
```

`auto` verwendet Chrome oder Edge, sofern einer davon verfügbar ist. Besonders in Sandbox-Umgebungen können Headless-Browser ohne echte Layoutursache fehlschlagen oder hängen. Wenn der Lauf im Sandbox-Kontext keine Screenshot-Dateien erzeugt, mit einem Browser-Startfehler endet oder hängen bleibt:

- den Lauf nicht als bestandenen Layoutcheck werten
- nicht automatisch auf Firefox ausweichen, wenn Chrome oder Edge lokal vorhanden ist
- denselben Befehl außerhalb der Sandbox oder mit lokaler Browserfreigabe erneut ausführen
- bei Bedarf den tatsächlich installierten Browser mit `-Browser chrome` oder `-Browser edge` gezielt diagnostizieren
- den Sandbox-Fehler in `Qualitaetscheck.md` nur als technischen Laufzeitfehler dokumentieren

Erfolgreiche Screenshots liegen hier:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Layoutcheck/
```

Typische Dateinamen:

```text
Lebenslauf---NACHNAME.VORNAME--seite-1-von-2--chrome.png
Lebenslauf---NACHNAME.VORNAME--seite-2-von-2--chrome.png
Anschreiben---NACHNAME.VORNAME--seite-1-von-1--chrome.png
```

Bei automatischer Auswahl kann im Dateinamen statt `chrome` auch `edge` stehen.

Wenn ein Bildbetrachter oder ein Agentenwerkzeug für lokale Bilder verfügbar ist, muss jeder erwartete Seitenscreenshot geöffnet und visuell geprüft werden. Bei einer Layoutkorrektur sind danach alle Nachweise erneut zu erzeugen.

Visuelle Bewertung des Screenshots:

- Ein einseitiger Lebenslauf zeigt genau eine vollständige A4-Seite und keine zweite Restseite.
- Ein zweiseitiger Lebenslauf wirkt bewusst verteilt; Seite 1 ist nicht halb leer und Seite 2 nicht nur ein ausgelagerter Rest.
- Überschriften, Zeiträume und Kontaktdaten überlappen nicht.
- Am unteren Seitenrand ist kein Inhalt abgeschnitten.
- Bei mehrseitigen Lebensläufen hat jede Seite einen festen Footer mit feiner Trennlinie und Seitenangabe darunter rechts.
- Die Seitenangabe steht nicht als normaler Absatz im Inhalt und wirkt nicht wie ein Rest zwischen zwei Seiten.
- Formale Stationen wie Berufserfahrung, Weiterbildung, berufliche Bildung und Schulbildung sind sichtbar.
- Schriftgröße, Zeilenabstand und Weißraum wirken professionell lesbar.
- Der Screenshot enthält keine Browser-Kopfzeilen, Dateipfade, URLs oder Druckdialog-Reste.

Der Layoutcheck isoliert jeden expliziten `.page`-Container in einer temporären A4-Ansicht. Dadurch wird keine Seite von einer festen Screenshot-Höhe abgeschnitten oder übersehen. Die Dichteheuristik ignoriert Footer und unteren Sicherheitsabstand; ihre Warnung muss fachlich bewertet werden und rechtfertigt kein blindes Auffüllen oder Komprimieren.

## Automatischer PDF-Export

Wenn die finalen HTML-Dateien technisch im grünen Bereich sind, können Lebenslauf und Anschreiben automatisch als PDF exportiert werden:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Der PDF-Export:

- führt zuerst `Tools/Pruefe-Bewerbung.ps1` aus
- bricht ab, wenn der statische Check fehlschlägt
- nutzt Chrome oder Edge Headless für den PDF-Export
- speichert die PDFs beim Einzellauf im geprüften HTML-/Kandidatenordner; die Finalisierung übernimmt sie anschließend ausschließlich nach `Versand/`
- nutzt dieselben Dateinamen wie die HTML-Dateien, nur mit `.pdf`
- prüft, ob jede PDF-Datei existiert, nicht leer ist und einen PDF-Header enthält
- prüft, ob die PDF-MediaBox DIN A4 entspricht, sofern das Exporttool dies unterstützt
- prüft, ob jede PDF frisch erzeugt wurde, korrekt endet und genauso viele Seiten wie das HTML explizite A4-Seitencontainer enthält
- exportiert und validiert zunächst beide PDFs in einem eindeutigen privaten Arbeitslauf
- ersetzt bestehende finale PDFs erst danach gemeinsam und stellt sie bei einem Veröffentlichungsfehler wieder her
- nutzt einen privaten Arbeitsordner unter `_Arbeitsdateien/.../PDF-Export` für Browserprofile und Zwischenexporte

Beispielausgabe:

```text
Lebenslauf - Nachname.Vorname.html
Lebenslauf - Nachname.Vorname.pdf
Anschreiben - Nachname.Vorname.html
Anschreiben - Nachname.Vorname.pdf
```

Optional kann der PDF-Export vorher auch den Browser-Layoutcheck ausführen:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -MitLayoutcheck
```

Unter Windows 11 / VS Code / PowerShell mit Chrome kann der Export gezielt mit Chrome ausgeführt werden:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -Browser chrome
```

Wenn kein Chrome oder Edge verfügbar ist, wird kein PDF-Export als bestanden gemeldet. Dann bleibt der manuelle PDF-Export über Firefox oder einen anderen Browser möglich, muss aber offen dokumentiert werden.

## ATS-Prüfung der PDFs

Der verbindliche Finalisierungsworkflow führt nach dem PDF-Export `Tools/Pruefe-ATS.ps1` aus. Das Werkzeug extrahiert die Unicode-Textschicht ohne externes PDF-Paket und prüft:

- Pflichttexte wie Bewerbername, Firma und Zielrolle
- formale Zeiträume im Lebenslauf
- Textabdeckung zwischen HTML und PDF
- eine grundlegende, nachvollziehbare Lesereihenfolge

Ein optisch korrektes PDF ohne ausreichend extrahierbaren Text ist nicht versandfertig. Die ATS-Prüfung ersetzt weiterhin nicht die Sichtprüfung. Lebenslauf und Anschreiben bleiben zwei getrennte PDFs; eine Formatforderung „PDF“ wird nicht als Gesamt-PDF interpretiert.

## Reihenfolge im Abschluss

1. Stammdaten prüfen und `Anforderungsmatrix.json` vervollständigen.
2. Versandfertig benannte Dateien im privaten Kandidatenordner erzeugen.
3. Finalisierung ohne Veröffentlichung vorbereiten.
4. Jeden Seitenscreenshot visuell öffnen und prüfen.
5. Bei Layoutproblemen Kandidaten-HTML korrigieren und die Vorbereitung vollständig wiederholen.
6. Bei Dichte- oder Layoutwarnungen die Sichtbewertung als Freigabenotiz dokumentieren.
7. Erst nach erfolgreicher Sichtprüfung mit `-Veroeffentlichen -VisuellGeprueft` atomar veröffentlichen.
8. Bei Fehlern nicht final melden; der finale Zielordner muss unverändert bleiben.

## Keine stillen Erfolge

Ein technischer Check gilt nur als erfolgreich, wenn das Tool mit Exitcode `0` endet und eine klare OK-Meldung ausgibt.

Stille Browserprozesse, veraltete oder ungültige Screenshots, fehlende oder leere PDFs, PDFs ohne gültige Struktur, zusätzliche Druckseiten oder durch Shell-Syntax fehlgeschlagene Suchläufe dürfen nicht als bestandene Prüfung behandelt werden.
