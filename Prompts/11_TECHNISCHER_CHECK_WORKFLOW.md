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

## Reihenfolge im Abschluss

1. Finale Dateien erzeugen.
2. `Tools/Pruefe-Bewerbung.ps1` ausführen.
3. Optional `Tools/Layoutcheck-Bewerbung.ps1` ausführen.
4. Ergebnis in `Qualitaetscheck.md` oder in der Abschlussnachricht knapp dokumentieren.
5. Bei Fehlern nicht final melden, sondern Dateien korrigieren und den Check erneut ausführen.

## Keine stillen Erfolge

Ein technischer Check gilt nur als erfolgreich, wenn das Tool mit Exitcode `0` endet und eine klare OK-Meldung ausgibt.

Stille Browserprozesse, fehlende Screenshot-Dateien, leere PDFs oder durch Shell-Syntax fehlgeschlagene Suchläufe dürfen nicht als bestandene Prüfung behandelt werden.
