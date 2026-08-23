# Technischer Check-Workflow

## Ziel

Dieser Workflow verhindert wiederkehrende technische Probleme bei der Erstellung und Prüfung finaler Bewerbungsunterlagen.

Er ergänzt den inhaltlichen Qualitätscheck. Er ersetzt nicht die fachliche Prüfung aus `Prompts/09_QUALITAETSCHECK.md`, sondern sorgt dafür, dass Dateien, Pfade, Platzhalter und A4-Grundstruktur technisch sauber sind.

## Grundregeln für Agenten

- Kritische Eingabedateien bei jeder Plattform bevorzugt sequenziell lesen, wenn parallele Prozesse fehlschlagen oder instabil wirken.
- Bei Textsuche mit `rg` keine Pfad-Wildcards wie `ORDNER/*.html` verwenden. Stattdessen:

```powershell
rg -g "*.html" "SUCHMUSTER" "ORDNER"
```

- Browser- oder Headless-Checks nur als bestanden werten, wenn die erwartete Ausgabe im aktuellen Lauf frisch erzeugt wurde, die korrekte Dateisignatur und die erwarteten Abmessungen besitzt.
- Browserprozesse ausschließlich mit getrennten Argumentlisten starten. Standardausgabe und Standardfehler begrenzen, einen Timeout erzwingen und bei Überschreitung den gesamten Prozessbaum beenden.
- Wenn ein Browser-Layoutcheck keine Datei erzeugt, ist das kein bestandener Layoutcheck. Dann muss der Fehler klar dokumentiert werden.
- Finale Bewerbungsdateien dürfen erst gemeldet werden, nachdem mindestens der statische Check erfolgreich war.
- PDFs dürfen erst erzeugt werden, nachdem der statische Check erfolgreich war.
- Versandfertige Dateien werden zunächst im privaten `Kandidat`-Ordner geprüft. Der finale Zielordner bleibt bis zur atomaren Veröffentlichung leer.
- Kandidaten liegen nur unter `Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat/`; ein loses Verzeichnis `Bewerbungen/` ist kein Exportpfad.
- `Stellenbeschreibung.md`, `Analyse.md`, `Qualitaetscheck.md` und `Druck-Hinweis.md` sind nichtleere fachliche Nachweise. Sie dürfen niemals als leere oder minimale Dummy-Dateien erzeugt werden, um den Prüfer zu umgehen.
- Eine ausgewählte E-Mail ist ausschließlich `Email-Nachricht--FIRMEN-SLUG.md` in UTF-8-Markdown. Der exakte Slug kommt aus `Bewerbungsauftrag.json`; HTML-Dateien für E-Mails sind unzulässig.
- HTML-Kandidaten müssen vor dem statischen Check die feste A4-Geometrie aus Prompt 08 enthalten: `@page { size: A4; margin: 0; }` und `.page { width: 210mm; height: 297mm; }`. `min-height` ersetzt diese Vertragswerte nicht.
- Bei einem zweiseitigen Lebenslauf muss jeder fachliche `<section>`-Block eine dokumentweit eindeutige `data-cv-section`-Kennung tragen und vollständig auf einer Seite liegen; jeder Seitencontainer benötigt einen mit `data-cv-page-header` markierten Kopf.
- Eine Änderung an einer HTML-Datei nach dem Layoutcheck macht den bisherigen Screenshot- und PDF-Nachweis ungültig. Maßgeblich sind die SHA-256-Werte in den Prüfberichten.
- Kandidatendateien einzeln und vollständig schreiben und danach unmittelbar validieren. Insbesondere JSON-Dateien nach jeder Änderung parsen; keine unübersichtliche Sammeländerung darf bei einem Teilfehler mehrere fertige Dokumente halb aktualisiert zurücklassen.
- Neue `Anforderungsmatrix.json`-Dateien verwenden Schema 5. Vor der Layoutprüfung muss der Inhaltsprüfer die vollständige `recruiterStrategie`, `anschreibenStrategie`, externe Quellen, sichtbare Anker, zulässige Transferbrücken, die Seite-1-Abdeckung sowie die hash- und zeilengebundene Beweiskette aus Stellenbeschreibung, Matrix und Evidenzindex bestätigen; Matrix-Schemata 1 bis 4 bleiben unverändert lesbar.
- Matrix- und Evidenzmigrationen laufen ausschließlich über das Subcommand `migrieren` des jeweiligen Plattform-Dispatchers. Der Standard ist read-only; `--anwenden` erzeugt bei fachlichen Lücken nur private Entwürfe und übernimmt vollständige Zielverträge atomar mit Hash-Recheck und Rollback. Status, Inhaltsprüfung und Finalisierung führen keine automatische Migration aus.
- In einer als verwaltete Sandbox bekannten Umgebung vor dem Browserlauf prüfen, ob eine lokale Browserfreigabe verfügbar ist. Eine vorhandene Freigabe direkt verwenden; andernfalls die Grenze offen melden und keinen erfolgreichen Lauf behaupten.
- Tokenzahlen niemals schätzen oder aus Textlängen beziehungsweise Teilwerten ableiten. Exakte Zahlen sind nur zulässig, wenn die Agentenlaufzeit sie maschinenlesbar bereitstellt.
- Ein Runtime-Fingerprint aus Betriebssystem, Architektur, Sprache und Version der Kernruntime sowie – bei Browserläufen – Browsername, Version und ausführbarer Datei bindet technische Nachweise an die Laufzeit. Nach einem Wechsel zwischen Windows und Linux oder umgekehrt Auftrag und Kandidaten erhalten, Layout-, PDF-, ATS-, Finalisierungs- und Sichtnachweise aber vollständig neu erzeugen.
- Berichte und Zustandsdateien werden in beiden Kernen atomar als UTF-8 geschrieben und innerhalb pfadbasierter Sperren mit begrenzten Wiederholungen aktualisiert. Ein abgebrochener Austausch darf keine Teil-JSON-Datei hinterlassen.
- `Sichtfreigabe.json` ist der einzige technische Veröffentlichungsnachweis. Die Freigabe-ID, der vorbereitete Finalisierungsbericht und jeder geprüfte Artefakt-Hash müssen aktuell übereinstimmen; ein altes `--visuell-geprueft` ersetzt diesen Nachweis nicht.

## Gemeinsamer Plattform- und CLI-Vertrag

Windows, Linux und macOS verwenden denselben Standardbibliothekskern mit System-Python 3.11 oder neuer:

```bash
python3 Tools/bewerbung.py <subcommand> ...
```

Die gemeinsamen 23 Subcommands sind `diagnose`, `neu`, `universal-neu`, `universal-status`, `universal-finalisieren`, `status`, `checkpoint`, `migrieren`, `stammdaten`, `dialog-pruefen`, `dialog-uebernehmen`, `passfoto`, `kontext`, `inhalt`, `pruefen`, `layout`, `pdf`, `ats`, `finalisieren`, `freigabe`, `tokenbericht`, `test-baseline` und `tests`. Sie verwenden dieselben GNU-Langoptionen, Pfadnormalisierung und privaten Artefaktschemata. Exitcode `0` bedeutet Erfolg, `1` einen fachlichen oder technischen Laufzeitfehler und `2` eine ungültige beziehungsweise unsichere CLI-Eingabe, eine nicht unterstützte Umgebung oder eine fehlende Kernruntime. POSIX- und CMD-Dateien sind ausschließlich Bootstrap-Aliase vor dem ersten Python-Start.

Das Subcommand `checkpoint --arbeitsordner "..." --schritt NAME` schreibt einen kompakten, hashgebundenen Fortsetzungsnachweis in den privaten Arbeitsordner. Es ist nach jeder sinnvollen Workflow-Grenze aufzurufen, speichert keine Quellinhalte oder Rohchatdaten und ersetzt keine fachliche Prüfung. Der Statusbefehl verwendet ihn nur bei vollständig übereinstimmenden Arbeitsartefakten als Hinweis; bei Abweichungen bleiben Auftrag, Matrix, Kandidaten und Prüfberichte maßgeblich.

Das Subcommand `passfoto --arbeitsordner "..."` ist der idempotente Einbettungsschritt für einen individuellen Kandidaten-Lebenslauf. Es prüft ausschließlich `Private/Daten/Passfoto.png`, ersetzt den einmaligen markierten Block durch eine bytegleiche eingebettete PNG-Ressource oder leert ihn bei fehlender Datei. Bildbytes werden nie ausgegeben. Universelle oder abgewählte Lebensläufe werden abgelehnt und niemals verändert.

Der getrennte Universalprozess verwendet `universal-neu`, `universal-status` und `universal-finalisieren`. Er arbeitet ausschließlich unter `Private/Bewerbungen/_Universal-Lebenslauf/`, verlangt für den Softwareentwicklungs-Zweiseiter die exakte atomare Abschnittsverteilung aus `Universalauftrag.json` und aktiviert erst nach den beiden persönlich geprüften PNG-Seiten. `Aktiv/` enthält danach nur PDF, HTML und Manifest; der datierte Arbeitsordner wird nach erfolgreicher Aktivierung vollständig entfernt. Scheitert nur diese letzte Bereinigung, erkennt derselbe erneute Freigabeaufruf die bereits hashgleich aktive Fassung und wiederholt ausschließlich die Bereinigung.

`diagnose` prüft Kernruntime, Betriebssystem, Architektur, Paketmanager, Browser, Temp- und Schreibzugriff sowie Fonts read-only und liefert Diagnoseschema 4 mit `coreRuntime`. `Tools/setup.py` liefert Setup-Schema 3; alte technische Nachweise bleiben lesbar. Die privaten Auftrags-, Matrix-, Prüfstands-, Freigabe- und Manifest-Schemata ändern sich dadurch nicht. Linux unterstützt x64/ARM64 mit APT, DNF/YUM, Pacman oder Zypper, Windows ausschließlich winget und macOS ausschließlich Homebrew. Unter Linux gelten Liberation Sans, unter Windows Arial und unter macOS Arial oder Liberation Sans. Fehlt Python, darf nur der POSIX- beziehungsweise CMD-Starter bei explizitem `--runtime --yes` die Runtime installieren und delegiert danach vollständig an Python. PyPI, virtuelle Umgebungen, Snap, AUR und fremde Browserquellen sind ausgeschlossen. Bereits passende Installationen sind idempotent. Unbekannte Paketmanager und macOS ohne Homebrew enden mit Exitcode `2` und einer manuellen Anleitung; Paketfehler enden mit Exitcode `1` und nennen den erreichten Teilzustand.

Der Pacman-Plan setzt `packageManagerOperation.fullSystemUpgrade = true`, kennzeichnet die erste Änderung mit `includesFullSystemUpgrade` und nennt den vollständigen `-Syu`-Lauf; spätere Paketinstallationen desselben Laufs verwenden `-S`. Diese breite Systemaktualisierung ist Bestandteil des vorab zu bestätigenden Plans. Fehlt Chromium unter Ubuntu oder in RHEL-kompatiblen Basis-Repositories, bleibt die Komponente blockiert und `manualInstruction` nennt Voraussetzung sowie exakten `verificationCommand`; Snap, EPEL und andere Communityquellen werden nicht registriert. Liberation Sans wird über eine tatsächlich vorhandene reguläre Fontdatei validiert; eine bloße Namensauflösung oder ein Symlink reicht nicht, und der Dateifallback funktioniert ohne `fc-match`.

## Verbindlicher Finalisierungsworkflow

Der Standardweg verwendet das Subcommand `finalisieren` und den privaten Arbeitsordner.

Bei einer Fortsetzung oder Standabfrage liefert `status --als-json` zuvor die nächste belegte Phase und die dafür benötigten Promptmodule. Es ersetzt keine Prüfung, verhindert aber unnötiges erneutes Laden bereits abgeschlossener Phasen.

Vorbereitung mit allen maschinellen Prüfungen:

```bash
python3 Tools/bewerbung.py finalisieren --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" --browser auto
```

Auf Windows und macOS lautet der identische Einstieg ebenfalls `python3 Tools/bewerbung.py finalisieren ...` (unter Windows alternativ über `Tools\\bewerbung.cmd`).

Dieser Lauf:

- verlangt eine vollständige `Anforderungsmatrix.json`
- validiert den bestätigten Dokumentumfang und den fortsetzbaren Dialogzustand; neue Aufträge verwenden Schema 5, Legacy-Aufträge der Schemata 1 bis 4 werden nicht automatisch umgeschrieben
- sperrt ungeklärte zentrale Bewerbungslogistik
- führt Dialog und Stammdaten, danach statischen HTML-Check, Inhalt, DOM/Layout, PDF und ATS in dieser festen Abbruchreihenfolge aus
- schreibt im `Inhalts-Pruefbericht.json` für Matrix-Schema 5 die maschinenlesbare `recruiterCoverage`, `evidenceCoverage`, `anschreibenCoverage`, `externalSourceCoverage`, `evidenzDisposition` und `sprachqualitaet`; fehlende Prioritätsbelege, falsche Zieldokumente oder Seiten, unbelegte Direktbehauptungen, fehlende Quellenanker und unvollständige Strategien blockieren
- erzeugt frische Layoutscreenshots samt Dichtehinweisen
- misst bei Chromium zusätzlich DOM-Überlauf, Scrollhöhe und Elementgrenzen je isolierter A4-Seite; jeder sichtbare Überlauf blockiert die Vorbereitung
- rendert zusätzlich jedes vollständige Original-HTML in eine temporäre A4-PDF und blockiert, wenn ihre Seitenzahl nicht exakt den expliziten `.page`-Containern entspricht; damit werden Wechselwirkungen zwischen Seiten wie druckwirksame Vorschauabstände erkannt
- exportiert und validiert genau die laut Dokumentumfang ausgewählten HTML-Dokumente als PDFs
- prüft die PDF-Textschicht und Lesbarkeit für ATS
- schreibt Hashnachweise für Quellen, sämtliche Kandidatendateien, PDFs und Seitenscreenshots; bei einem individuellen Lebenslauf mit vorhandenem Passfoto kommt exakt der optionale Quellnachweis `passfoto` hinzu
- schreibt `Pruefstand.json` Schema 2 ausschließlich im privaten Arbeitsordner. Jede Stufe wird vor ihrem Start als `running`, danach als `passed` oder bei einem kontrollierten Werkzeugfehler als `failed` gespeichert. Erfolgreiche Stufen werden nur bei identischen Quellen, Parametern, Werkzeug- und Laufzeithashes wiederverwendet; fehlgeschlagene oder unterbrochene Stufen nie. `--neu-pruefen` umgeht den Prüfstand.
- schreibt den Vorbereitungsbericht für individuelle Bewerbungen im Schema 7 beziehungsweise für den Universal-Lebenslauf im Schema 2 mit einer neuen, eindeutigen `approvalRequest.approvalId`; Schema-6-Vorbereitungen bleiben veröffentlichbar, liefern aber keine Cachetreffer
- schreibt den Runtime-Fingerprint in Layout-, PDF-, ATS- und Finalisierungsbericht
- aktualisiert den nicht blockierenden Diagnosebericht `Tokenverbrauch.json` im Arbeitsordner mindestens mit dem Verfügbarkeitsstatus und referenziert ihn optional im `Finalisierungsbericht.json`
- veröffentlicht noch keine Datei
- leitet ab Schema 4 alle erwarteten Dateien aus `dokumentumfang` ab; bei universellem Lebenslauf prüft er zusätzlich dessen SHA-256-Snapshot
- schreibt bei einem bestätigten reinen E-Mail-Auftrag Layout-, PDF- und ATS-Berichte mit `nicht_erforderlich`, statt einen Browserlauf vorzutäuschen

Nach der tatsächlichen Sichtprüfung:

```bash
python3 Tools/bewerbung.py freigabe --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" --freigabe-id FR-XXXXXXXXXXXX --bestaetigt --notiz "Sichtprüfung abgeschlossen."
python3 Tools/bewerbung.py finalisieren --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" --veroeffentlichen
```

Liegen automatische Layoutwarnungen vor, muss zusätzlich eine konkrete Sichtbewertung als `--notiz "Alle markierten Seiten geprüft; kein Beschnitt und keine Überlappung."` im `freigabe`-Aufruf angegeben werden.

Die Veröffentlichung wird verweigert, wenn Quellen, Auftrag, Kandidatendateien oder Screenshots nach der Vorbereitung verändert wurden. Das gilt bei individuellen Lebensläufen auch für das spätere Hinzufügen, Ändern oder Löschen von `Private/Daten/Passfoto.png`. Sie kopiert nicht dateiweise in den Zielordner, sondern veröffentlicht das validierte Set über einen privaten Staging-Ordner gemeinsam. `Versand/` enthält ausschließlich die ausgewählten PDF-Anlagen und gegebenenfalls den E-Mail-Text; `Intern/` enthält vorhandene HTML-Quellen und Nachweise. `Manifest.json` bindet Dokumentumfang und jede veröffentlichte Datei an ihren SHA-256-Wert; das Foto selbst wird nicht separat veröffentlicht.

Layout- und PDF-Einzelwerkzeuge lösen relative Berichtspfade gegen das Aufrufverzeichnis auf, nicht gegen ihren Ausgabeordner. Isolierte Browserprofile und Capture-Dateien werden auch nach kontrollierten Fehlern mit begrenzten Wiederholungen entfernt; eine leere `.browser-tmp`-Wurzel bleibt nicht als Arbeitsrest zurück.

Die nachfolgenden Einzelwerkzeuge bleiben für Diagnose, Entwicklung und gezielte Wiederholungen verfügbar. Für neue Bewerbungen ersetzt ihre manuelle Verkettung nicht den verbindlichen Finalisierungsworkflow.

Einzelne Diagnosebefehle sind keine allgemeinen Konverter für lose Dokumentordner. Für den normalen Ablauf ist ausschließlich das Subcommand `finalisieren` auf einem korrekt angelegten Kandidatenstand vorgesehen.

## Tokenverbrauch und Laufzeitmessung

Der standardisierte Bericht wird mit folgendem Werkzeug aktualisiert:

```bash
python3 Tools/bewerbung.py tokenbericht \
  --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" \
  --messbereich lebenslauf
```

Ohne maschinenlesbare Nutzungsdaten schreibt das Werkzeug ausschließlich Nullwerte und den Status `unavailable`. Liegen exakte Laufzeitdaten vor, werden sie ausdrücklich mit `--nutzungsdaten-verfuegbar`, Anbieter, Modell und den tatsächlich bereitgestellten Tokenfeldern übergeben. Fehlende Felder bleiben `null`; insbesondere wird `totalTokens` nicht aus anderen Feldern berechnet.

Zulässige Messbereiche sind `lebenslauf`, `gesamte_bewerbung` und `technische_vorbereitung`. Anbieter, Modell, eine nicht sensible Vorgangs-ID, Beginn, Ende, Eingabe-, Ausgabe-, Cache-Lese-, Cache-Schreib-, Reasoning- und Gesamt-Tokens werden nur gespeichert, soweit die Laufzeit sie tatsächlich ausweist. Kann sie nur die gesamte Sitzung messen, muss `--messumfang gesamte_agentensitzung` gesetzt und diese Einschränkung in der Konsolenausgabe genannt werden.

`Tokenverbrauch.json` bleibt im privaten Arbeitsordner. Der Bericht ist kein Qualitätsnachweis, blockiert weder Vorbereitung noch Veröffentlichung, gelangt nicht nach `Versand/` und wird standardmäßig nicht in `Manifest.json` aufgenommen. Er speichert keine API-Schlüssel, Zugangsdaten, vollständigen Prompts oder privaten Bewerbungsinhalte.

## Einzelprüfer nur für Diagnose

Der verbindliche Finalisierungslauf führt den statischen Prüfer selbst aus. Ein zusätzlicher separater Vorablauf ist nicht erforderlich. Zur gezielten Diagnose eines Kandidatenfehlers kann er manuell ausgeführt werden:

```bash
python3 Tools/bewerbung.py pruefen --ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat" --auftrag-path "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Bewerbungsauftrag.json"
```

Der Prüfer kontrolliert:

- nichtleere Pflichtdateien im finalen Bewerbungsordner; Verzeichnisse mit Dateinamen zählen nicht
- genau die laut Dokumentumfang ausgewählten Versanddateien
- keine sichtbaren Platzhalter oder Entwurfsmarker
- keine Entwurfsdateien im finalen Bewerbungsordner
- exakte A4-Grundstruktur mit `width: 210mm` und `height: 297mm`
- exakt eine Anschreibenseite sowie ein oder zwei explizite Lebenslaufseiten mit konsistenten Seiten-Footern
- eingebettetes CSS ohne automatisch geladene externe oder lokale Ressourcen, Skripte, Fonts, Medien oder CDNs
- `overflow: hidden` nur auf der äußeren A4-Seite
- kurze, platzhalterfreie E-Mail-Nachricht mit konkretem `Betreff:` in der ersten Zeile
- bei strukturierten Veröffentlichungen: korrekte `Versand/`-/`Intern/`-Trennung und vollständiges Hash-Manifest

Ein erfolgreicher Einzellauf diagnostiziert nur den aktuellen Kandidatenstand. Der technische Abschlusscheck gilt erst nach dem erfolgreichen vollständigen Finalisierungslauf als bestanden.

## Optionaler Layoutcheck für Diagnose

Wenn ein lokaler Browser verfügbar ist, kann zusätzlich ein visueller Layoutcheck erzeugt werden:

```bash
python3 Tools/bewerbung.py layout \
  --ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat" \
  --output-root "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Layoutcheck" \
  --browser auto
```

Der Layoutcheck:

- sucht finale HTML-Dateien im Bewerbungsordner
- erzeugt Screenshots im passenden privaten Arbeitsordner unter `_Arbeitsdateien`
- schreibt keine Kontrollbilder in den finalen Bewerbungsordner
- prüft nach jedem Browserlauf, ob die Ausgabedatei wirklich erzeugt wurde
- entfernt alte erwartete Ausgaben vor dem Lauf und akzeptiert keine veralteten Dateien
- validiert PNG-Signatur, Aktualität und exakte Bildabmessungen
- wertet erwartete nicht-interlaced PNGs mit 8-Bit-Grau-, RGB- oder RGBA-Pixeln und den PNG-Filtern 0 bis 4 über den jeweiligen dependency-freien Laufzeitleser aus; ein nicht auswertbares PNG lässt die erforderliche Dichteprüfung fehlschlagen
- beendet hängende Browser nach dem konfigurierten Timeout
- meldet Fehler sichtbar, statt stille Browserfehler zu übergehen

Als Einzelwerkzeug ist der Browser-Layoutcheck für Diagnose optional. Im verbindlichen Finalisierungsworkflow ist er für jeden ausgewählten HTML-Bestandteil Voraussetzung. Enthält ein ausdrücklich bestätigter Umfang nur eine E-Mail, gibt es keinen Browserlauf; stattdessen bleibt die persönliche Textprüfung Pflicht. Wenn ein erforderlicher Browserlauf wegen lokaler Browser- oder Sandbox-Einschränkungen nicht läuft, darf die Bewerbung nicht veröffentlicht werden.

## Browserauswahl unter Windows und Linux

Im Standardweg wählt das Skript automatisch einen unterstützten installierten Browser aus:

```bash
python3 Tools/bewerbung.py layout --ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat" --browser auto
```

`auto` sucht unter Windows in der Reihenfolge Chrome, Edge, Chromium und unter Linux in der Reihenfolge Chrome, Chromium, Edge. `--browser-executable-path` überschreibt die Suche, wird aber auf Existenz, Version und Chromium-Engine geprüft. Firefox ist ausschließlich für das Subcommand `layout` als Diagnose zulässig; PDF-Export und Finalisierung lehnen ihn ab. Besonders in Sandbox-Umgebungen können Headless-Browser ohne echte Layoutursache fehlschlagen oder hängen. Wenn der Lauf im Sandbox-Kontext keine Screenshot-Dateien erzeugt, mit einem Browser-Startfehler endet oder hängen bleibt:

- den Lauf nicht als bestandenen Layoutcheck werten
- nicht automatisch auf Firefox ausweichen, wenn ein unterstützter Chromium-Browser lokal vorhanden ist
- denselben Befehl außerhalb der Sandbox oder mit lokaler Browserfreigabe erneut ausführen
- bei Bedarf den tatsächlich installierten Browser mit `--browser chrome`, `--browser edge` oder `--browser chromium` gezielt diagnostizieren
- den Sandbox-Fehler in `Qualitaetscheck.md` nur als technischen Laufzeitfehler dokumentieren

Auf normalen Hosts bleibt die Chromium-Sandbox aktiv; `--no-sandbox` und `--disable-gpu-sandbox` werden nicht verwendet. Der Linux-Python-Kern lehnt einen Browserstart als Root fail-closed ab. Nur die ephemeren Root-Container von `linux-compatibility.yml` dürfen mit dem ausdrücklich gesetzten `APPLY_FOUNDRY_ALLOW_UNSANDBOXED_BROWSER=1` die eng begrenzte CI-Ausnahme aktivieren; Agenten und Benutzer dürfen diese Variable nicht als lokale Problemlösung setzen.

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

Bei automatischer Auswahl kann im Dateinamen statt `chrome` auch `edge` oder `chromium` stehen.

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
- Ungewöhnlich freie Flächen wurden zuerst gegen fehlende relevante Profilhighlights, Anwendungskontexte und eigene Beiträge geprüft; Layoutanpassungen kaschieren keine inhaltliche Unterdeckung.
- Der Screenshot enthält keine Browser-Kopfzeilen, Dateipfade, URLs oder Druckdialog-Reste.

Der Layoutcheck isoliert jeden expliziten `.page`-Container in einer temporären A4-Ansicht und ergänzt dies durch eine vollständige Druckvorprüfung des unveränderten HTML. Dadurch wird keine Seite von einer festen Screenshot-Höhe abgeschnitten oder übersehen, und gleichzeitig können global wirksame CSS-Regeln zwischen Seiten keine zusätzliche Druckseite unbemerkt erzeugen. Die Dichteheuristik ignoriert Footer und unteren Sicherheitsabstand; ihre Warnung muss fachlich bewertet werden und rechtfertigt kein blindes Auffüllen oder Komprimieren. Bei ungewöhnlich geringer Dichte wird zuerst die Schema-5-Recruiter-, Anschreiben- und Evidenzabdeckung fachlich geprüft, dann die Seitenstrategie und erst danach das Layout verändert.

Die Vorlagen verwenden `Arial, "Liberation Sans", Helvetica, sans-serif`. Windows und Linux müssen weder pixelidentische PNGs noch binär identische PDFs erzeugen. Verbindlich gleich sind Seitenzahl, A4-Geometrie, bestandene Dichteprüfung, Hashbindung und ATS-Prüfung.

## Automatischer PDF-Export

Wenn ausgewählte finale HTML-Dateien technisch im grünen Bereich sind, werden genau diese automatisch als PDF exportiert:

```bash
python3 Tools/bewerbung.py pdf \
  --ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat" \
  --auftrag-path "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Bewerbungsauftrag.json" \
  --output-root "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/PDF-Export" \
  --browser auto
```

Der PDF-Export:

- führt zuerst denselben statischen Vertragsprüfer wie das Subcommand `pruefen` aus
- bricht ab, wenn der statische Check fehlschlägt
- nutzt Chrome, Edge oder Chromium Headless für den PDF-Export
- speichert die PDFs beim Einzellauf im geprüften HTML-/Kandidatenordner; die Finalisierung übernimmt sie anschließend ausschließlich nach `Versand/`
- nutzt dieselben Dateinamen wie die HTML-Dateien, nur mit `.pdf`
- prüft, ob jede PDF-Datei existiert, nicht leer ist und einen PDF-Header enthält
- prüft, ob die PDF-MediaBox DIN A4 entspricht, sofern das Exporttool dies unterstützt
- prüft, ob jede PDF frisch erzeugt wurde, korrekt endet und genauso viele Seiten wie das HTML explizite A4-Seitencontainer enthält
- exportiert und validiert zunächst den vollständigen ausgewählten PDF-Satz in einem eindeutigen privaten Arbeitslauf
- ersetzt bestehende finale PDFs erst danach gemeinsam und stellt sie bei einem Veröffentlichungsfehler wieder her
- nutzt einen privaten Arbeitsordner unter `_Arbeitsdateien/.../PDF-Export` für Browserprofile und Zwischenexporte

Beispielausgabe:

```text
Lebenslauf - Nachname.Vorname.html
Lebenslauf - Nachname.Vorname.pdf
Anschreiben - Nachname.Vorname.html
Anschreiben - Nachname.Vorname.pdf
```

Für Diagnose werden Layoutcheck und PDF-Export mit ihren ausdrücklich genannten Ausgabeordnern getrennt ausgeführt. Der verbindliche Finalisierungslauf koordiniert beide automatisch; `--mit-layoutcheck` ist für den normalen Bewerbungsablauf nicht erforderlich.

Der Export kann auf beiden Plattformen gezielt mit Chrome ausgeführt werden:

```bash
python3 Tools/bewerbung.py pdf \
  --ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat" \
  --auftrag-path "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Bewerbungsauftrag.json" \
  --browser chrome \
  --output-root "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/PDF-Export"
```

Wenn kein unterstützter Chromium-Browser verfügbar ist, wird kein PDF-Export als bestanden gemeldet. Eine manuelle Vorschau oder ein manueller Export über Firefox beziehungsweise einen anderen Browser ist nur eine offen zu dokumentierende Diagnosealternative und erreicht nicht das verbindliche Freigabe-Gate.

## ATS-Prüfung der PDFs

Der verbindliche Finalisierungsworkflow führt nach dem PDF-Export den ATS-Prüfer des jeweiligen Plattformkerns aus. Er extrahiert die Unicode-Textschicht ohne externes PDF-Paket und prüft:

- Pflichttexte wie Bewerbername, Firma und Zielrolle
- formale Zeiträume im Lebenslauf
- Unicode-normalisierte Token-Abdeckung sowie geordnete Bigramm- und Trigramm-Abdeckung zwischen HTML und PDF
- stabile Tokenisierung technischer Schreibweisen wie `C#`, `.NET` und `Node.js`
- eine grundlegende, nachvollziehbare Lesereihenfolge

Ein optisch korrektes PDF ohne ausreichend extrahierbaren Text ist nicht versandfertig. Die ATS-Prüfung ersetzt weiterhin nicht die Sichtprüfung. Mehrere ausgewählte Dokumente bleiben getrennte PDFs; eine Formatforderung „PDF“ wird nicht als Gesamt-PDF interpretiert.

## Reihenfolge im Abschluss

1. Bestätigten Dokumentumfang und Dialogstatus prüfen, danach Stammdaten prüfen und `Anforderungsmatrix.json` vervollständigen.
2. Nur ausgewählte Dateien im privaten Kandidatenordner erzeugen. Einen universellen Lebenslauf übernimmt der Ordnerhelfer unverändert.
3. Nur nach Fertigstellung eines ausgewählten Lebenslauf-Kandidaten den Abschnitt `lebenslauf` in `Tokenverbrauch.json` aktualisieren, ohne den Workflow zu unterbrechen.
4. Finalisierung ohne Veröffentlichung vorbereiten, danach `gesamte_bewerbung` aktualisieren und `technische_vorbereitung` nur bei isoliert verfügbaren Laufzeitwerten mit Zahlen befüllen.
5. Jeden erzeugten Seitenscreenshot visuell öffnen und prüfen; ohne HTML die ausgewählten Textdateien persönlich prüfen.
6. Bei Layoutproblemen Kandidaten-HTML korrigieren und die Vorbereitung vollständig wiederholen.
7. Bei Dichte- oder Layoutwarnungen die Sichtbewertung als Freigabenotiz dokumentieren.
8. Erst nach neuer eindeutiger Sichtprüfungsbestätigung die im Bericht ausgegebene ID mit dem Subcommand `freigabe --bestaetigt` an den unveränderten Artefaktsatz binden und anschließend mit `finalisieren --veroeffentlichen` atomar veröffentlichen. Das Legacy-Argument `--visuell-geprueft` erteilt keine Freigabe.
9. Bei Fehlern nicht final melden; der finale Zielordner muss unverändert bleiben. Der Tokenbericht darf einen ansonsten erfolgreichen Lauf nicht blockieren.

## CI und gestufter Plattform-Rollout

Die browserfreien Verträge laufen über `python3 Tools/bewerbung.py tests` und `python3 -m unittest` auf Windows, Linux und macOS in x64/ARM64. Die CI enthält einen Python-3.11-Mindestversionsjob sowie Browser-Smokes für Chromium-Druck, A4-Geometrie und ATS. `linux-compatibility.yml` prüft zusätzlich Ubuntu 24.04/26.04, Debian 13, Fedora, Rocky 9, Arch und openSUSE in ephemeren Containern. Die Tests verwenden ausschließlich synthetische Fixtures und lesen `Private/` nicht.

Plattformübergreifende Fixtures erzeugen aus denselben öffentlichen synthetischen Quellen portable Schema-5-Aufträge. Ein Plattformwechsel muss Status und Checkpoint fortsetzen können, während ein fremder technischer Runtime-Fingerprint als erneuerungspflichtig erkannt wird. Dies belegt die Portabilität der Auftragsdaten, nicht binär identische Browserartefakte.

Der Windows-Browser-Smoke läuft bei jedem Pull Request sowie zeitgesteuert/manuell unter einem stabilen Checknamen. Linux läuft zunächst nur zeitgesteuert/manuell und führt die native Python-Browsersuite mit synthetischen Layout-, PDF-, ATS-, Finalisierungs- und Freigabefällen aus. Das Linux-Promotion-Gate ist damit noch nicht erfüllt: Erst wenn Collector, Validator und öffentlicher Nachweis je Zielprofil drei aufeinanderfolgende vollständige Läufe mit Screenshot, A4-PDF, Seitenzahl, ATS-Textschicht, Hashbindung, Timeout-Cleanup und ohne Restprozesse belegen, darf ein dokumentierter Promotion-PR Linux als stabil und PR-verbindlich einstufen. Ein administrativer Ruleset-Eintrag ist zusätzlich erforderlich; ohne Adminzugriff bleibt er nur vorbereitet.

`browser-stability-evidence.yml` darf aus der GitHub-Actions-API nur einen read-only Nachweisentwurf erzeugen. Der aktuelle Entwurf ist noch auf Ubuntu 24.04 beschränkt; die Distributionsmatrix lädt deshalb bereinigte Vollsuite- und verfügbare Browserberichte je Zielprofil getrennt hoch. Vor einer Promotion müssen Collector, Validator und öffentlicher Stabilitätsnachweis auf alle Zielprofile erweitert werden. Der Entwurf gilt nicht als Promotion; ein eigener PR muss danach je Profil drei aufeinanderfolgende Läufe und alle Kriterien übernehmen.

Echte Prompt-Regressionen verwenden `Tests/PromptRegression/models.json` und `scenarios.json` und laufen unter Linux über `python3 Tools/bewerbung.py tests --suite prompt-pr` beziehungsweise `prompt-vollstaendig`. Codex und OpenCode bilden die PR-Canary mit identischer OpenAI-Modell-ID; Claude Code und Gemini CLI laufen in der vollständigen wöchentlichen/manuellen Matrix. Die Testworkflows installieren `bubblewrap` ausschließlich als CI-Sandbox-Voraussetzung und prüfen den Namespace vor jedem Modelllauf; es gehört nicht zu den Benutzerabhängigkeiten von `setup-linux.py`. Versionsprobe und Agentlauf sehen im Mount-/PID-/User-Namespace nur die synthetische Arbeitskopie sowie read-only eingebundene Systemruntimes, nicht das Host-Home. Das Netz bleibt ausschließlich für die Provider-API geteilt. Fehlt `bwrap` oder sind User-Namespaces gesperrt, entsteht fail-closed ein Schema-1-Fehlerbericht.

Der Runner reicht nur das deklarierte Credential weiter, lädt `AGENTS.md` über die jeweilige Umgebung und prüft Mutationsgrenzen sowie Ausgabesignale. Das Zielmodell muss im kataloggebundenen Argumentvektor stehen; weist die CLI ein tatsächlich verwendetes Modell maschinenlesbar aus, muss es exakt passen. Die Rollenfixtures beginnen ohne Matrix und Evidenzindex und müssen beide neu, schema-, SHA-, Evidenz- und strategievalidiert erzeugen; der direkte Rollenfall prüft zusätzlich ausgewählte Dokumente, A4-Grundstruktur und Platzhalterfreiheit. Fehlende Secrets und CLI-Versionsdrift schlagen fehl. Ein grüner Lauf belegt diese definierten Verträge, nicht jedes fachliche Verhalten beliebiger Modelle. Reports speichern keine Zugangsdaten oder privaten Inhalte.

Prompt-, Kern-, Browser- und Distributionsjobs verwenden den gemeinsamen Python-Kern; CI installiert keine zusätzlichen Bewerbungsruntime-Implementierungen.

## Keine stillen Erfolge

Ein technischer Check gilt nur als erfolgreich, wenn das Tool mit Exitcode `0` endet und eine klare OK-Meldung ausgibt.

Stille Browserprozesse, veraltete oder ungültige Screenshots, fehlende oder leere PDFs, PDFs ohne gültige Struktur, zusätzliche Druckseiten oder durch Shell-Syntax fehlgeschlagene Suchläufe dürfen nicht als bestandene Prüfung behandelt werden.
