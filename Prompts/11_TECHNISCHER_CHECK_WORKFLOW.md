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

Der Browser-Layoutcheck ist hilfreich, aber optional. Wenn er wegen lokaler Browser- oder Sandbox-Einschränkungen nicht läuft, muss der statische Check trotzdem erfolgreich sein und der nicht ausgeführte Layoutcheck offen benannt werden.

## Standardweg unter Windows 11 / VS Code / PowerShell

Wenn der Agent unter Windows 11 in VS Code mit PowerShell arbeitet und Chrome installiert ist, soll für die visuelle Prüfung direkt Chrome gewählt werden:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -Browser chrome
```

Das vermeidet unnötige Browserwechsel. Besonders in Sandbox-Umgebungen können Headless-Browser ohne echte Layoutursache fehlschlagen oder hängen. Wenn der Chrome-Lauf im Sandbox-Kontext keine Screenshot-Dateien erzeugt, mit einem Browser-Startfehler endet oder hängen bleibt:

- den Lauf nicht als bestandenen Layoutcheck werten
- nicht automatisch auf Firefox ausweichen, wenn Chrome lokal vorhanden ist
- denselben Chrome-Befehl außerhalb der Sandbox oder mit lokaler Browserfreigabe erneut ausführen
- den Sandbox-Fehler in `Qualitaetscheck.md` nur als technischen Laufzeitfehler dokumentieren

Erfolgreiche Screenshots liegen hier:

```text
Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Layoutcheck/
```

Typische Dateinamen:

```text
Lebenslauf---NACHNAME.VORNAME--chrome.png
Anschreiben---NACHNAME.VORNAME--chrome.png
```

Wenn ein Bildbetrachter oder ein Agentenwerkzeug für lokale Bilder verfügbar ist, muss mindestens der Lebenslauf-Screenshot geöffnet und visuell geprüft werden. Bei einer Layoutkorrektur ist danach erneut ein Screenshot zu erzeugen.

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

Für bewusst zweiseitige Lebensläufe reicht ein Screenshot der ersten A4-Höhe nicht aus. Dann zusätzlich einen höheren Screenshot erzeugen oder die PDF-Ausgabe mit allen Seiten prüfen:

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -Browser chrome -Height 2300
```

## Automatischer PDF-Export

Wenn die finalen HTML-Dateien technisch im grünen Bereich sind, können Lebenslauf und Anschreiben automatisch als PDF exportiert werden:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Der PDF-Export:

- führt zuerst `Tools/Pruefe-Bewerbung.ps1` aus
- bricht ab, wenn der statische Check fehlschlägt
- nutzt Chrome oder Edge Headless für den PDF-Export
- speichert die PDFs im finalen Bewerbungsordner
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

## Reihenfolge im Abschluss

1. Finale Dateien erzeugen.
2. `Tools/Pruefe-Bewerbung.ps1` ausführen.
3. Optional `Tools/Layoutcheck-Bewerbung.ps1` ausführen, unter Windows 11 bevorzugt mit `-Browser chrome`.
4. Erzeugten Screenshot visuell prüfen und bei Layoutproblemen die HTML-Datei korrigieren.
5. Wenn PDF-Dateien gewünscht sind oder ein Browser verfügbar ist: `Tools/Exportiere-PDF.ps1` ausführen.
6. Ergebnis in `Qualitaetscheck.md` oder in der Abschlussnachricht knapp dokumentieren.
7. Bei Fehlern nicht final melden, sondern Dateien korrigieren und den Check erneut ausführen.

## Keine stillen Erfolge

Ein technischer Check gilt nur als erfolgreich, wenn das Tool mit Exitcode `0` endet und eine klare OK-Meldung ausgibt.

Stille Browserprozesse, veraltete oder ungültige Screenshots, fehlende oder leere PDFs, PDFs ohne gültige Struktur, zusätzliche Druckseiten oder durch Shell-Syntax fehlgeschlagene Suchläufe dürfen nicht als bestandene Prüfung behandelt werden.
