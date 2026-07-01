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

- Browser- oder Headless-Checks nur als bestanden werten, wenn die erwartete Ausgabe wirklich existiert und eine sinnvolle Dateigröße hat.
- Wenn ein Browser-Layoutcheck keine Datei erzeugt, ist das kein bestandener Layoutcheck. Dann muss der Fehler klar dokumentiert werden.
- Finale Bewerbungsdateien dürfen erst gemeldet werden, nachdem mindestens der statische Check erfolgreich war.
- PDFs dürfen erst erzeugt werden, nachdem der statische Check erfolgreich war.

## Pflichtprüfung nach jeder Bewerbung

Nach dem Erstellen der finalen Bewerbungsdateien soll, sofern eine PowerShell-Umgebung verfügbar ist, dieser statische Prüfer ausgeführt werden:

```powershell
.\Tools\Pruefe-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME"
```

Der Prüfer kontrolliert:

- Pflichtdateien im finalen Bewerbungsordner
- korrekte Versanddateien für Lebenslauf und Anschreiben
- keine sichtbaren Platzhalter oder Entwurfsmarker
- keine Entwurfsdateien im finalen Bewerbungsordner
- feste A4-Grundstruktur in HTML-Dateien
- eingebettetes CSS ohne externe Skripte, Fonts oder CDNs
- `overflow: hidden` nur auf der äußeren A4-Seite
- kurze, platzhalterfreie E-Mail-Nachricht

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
- meldet Fehler sichtbar, statt stille Browserfehler zu übergehen

Der Browser-Layoutcheck ist hilfreich, aber optional. Wenn er wegen lokaler Browser- oder Sandbox-Einschränkungen nicht läuft, muss der statische Check trotzdem erfolgreich sein und der nicht ausgeführte Layoutcheck offen benannt werden.

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
- nutzt einen privaten Arbeitsordner unter `_Arbeitsdateien/.../PDF-Export` für Browserprofile

Beispielausgabe:

```text
Lebenslauf - BEISPIEL.PERSON.html
Lebenslauf - BEISPIEL.PERSON.pdf
Anschreiben - BEISPIEL.PERSON.html
Anschreiben - BEISPIEL.PERSON.pdf
```

Optional kann der PDF-Export vorher auch den Browser-Layoutcheck ausführen:

```powershell
.\Tools\Exportiere-PDF.ps1 -Ordner "Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME" -MitLayoutcheck
```

Wenn kein Chrome oder Edge verfügbar ist, wird kein PDF-Export als bestanden gemeldet. Dann bleibt der manuelle PDF-Export über Firefox oder einen anderen Browser möglich, muss aber offen dokumentiert werden.

## Reihenfolge im Abschluss

1. Finale Dateien erzeugen.
2. `Tools/Pruefe-Bewerbung.ps1` ausführen.
3. Optional `Tools/Layoutcheck-Bewerbung.ps1` ausführen.
4. Wenn PDF-Dateien gewünscht sind oder ein Browser verfügbar ist: `Tools/Exportiere-PDF.ps1` ausführen.
5. Ergebnis in `Qualitaetscheck.md` oder in der Abschlussnachricht knapp dokumentieren.
6. Bei Fehlern nicht final melden, sondern Dateien korrigieren und den Check erneut ausführen.

## Keine stillen Erfolge

Ein technischer Check gilt nur als erfolgreich, wenn das Tool mit Exitcode `0` endet und eine klare OK-Meldung ausgibt.

Stille Browserprozesse, fehlende Screenshot-Dateien, fehlende oder leere PDFs, PDFs ohne PDF-Header oder durch Shell-Syntax fehlgeschlagene Suchläufe dürfen nicht als bestandene Prüfung behandelt werden.
