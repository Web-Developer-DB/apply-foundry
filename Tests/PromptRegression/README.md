# Promptvergleich für aktuelle Modelle

Dieser Plan prüft, ob die überarbeiteten Regeln bessere Bewerbungsunterlagen
erzeugen. Er ist Entwicklerdokumentation und kein zusätzliches Promptmodul.
Die [Prüfung vom 19. November 2026](../../docs/prompt-audit-2026-11-19.md)
begründet die Änderungen; sie ersetzt diesen Modellvergleich nicht.

## Zielkonfiguration

[`models.json`](models.json) definiert:

- PR-Canary: Codex und OpenCode mit `gpt-6.2-sol`; OpenCode verwendet den
  Providerpräfix `openai/`.
- Vollständige Matrix: zusätzlich Codex mit `gpt-6.1-sol` sowie die bestehenden
  Claude- und Gemini-Einträge.

Die Modell-IDs sind anhand der offiziellen
[GPT-6.2-Sol-Dokumentation](https://developers.openai.com/api/docs/models/gpt-6.2-sol)
und [GPT-6.1-Sol-Dokumentation](https://developers.openai.com/api/docs/models/gpt-6.1-sol)
geprüft. Daraus folgt keine garantierte Verfügbarkeit in jedem Konto oder in
den festgelegten CLI-Versionen. CLI-Versionen werden bewusst nicht zusammen
mit den Prompts beiläufig aktualisiert; notwendige Aktualisierungen brauchen
einen eigenen geprüften Kompatibilitätsstand.

Der Eintrag legt nur das Zielmodell eines zukünftigen Testlaufs fest. Er ändert
nicht das Modell der geöffneten Agentensitzung. Der zusätzliche GPT-6.1-Eintrag
erhöht die Anzahl möglicher kostenpflichtiger Läufe in der vollständigen
Matrix; die PR-Canary bleibt bei zwei Modelleinstellungen.

## Vorhandene ausführbare Prüfungen

[`scenarios.json`](scenarios.json) enthält Szenarien für Projekteinstieg,
Umfang, Fremdanweisungen, Profilfragen, Rollenbelege und Fortsetzung. Ergänzt
wurden:

- `belegarten-anwendungskontext`: Berufspraxis und private Praxis desselben
  Werkzeugs getrennt und wahrheitsgemäß formulieren.
- `bestaetigte-dialogangabe`: Eine bestätigte Angabe im aktuellen Auftrag
  verwenden, ohne sie ungefragt dauerhaft zu speichern.
- `promptpruefung-ist-projektarbeit`: Eine technische Promptprüfung einordnen,
  ohne eine Bewerbung anzulegen oder Modellfähigkeit als Prüfnachweis zu nutzen.

Nach dem read-only Setup-Preflight können die vorhandenen Befehle laufen:

```bash
python3 Tools/setup.py --all --dry-run --format json
python3 Tools/bewerbung.py tests --suite vollstaendig
python3 Tools/bewerbung.py tests --suite prompt-pr
python3 Tools/bewerbung.py tests --suite prompt-vollstaendig
```

Die letzten beiden Befehle starten echte, potenziell kostenpflichtige
Modellaufrufe. Dafür werden die im Katalog festgelegten CLIs, deren exakte
Versionen und die deklarierten API-Zugänge benötigt. Fehlende Voraussetzungen
werden nicht durch automatische Installation beliebiger Zusatzpakete oder
durch Umgehen der Isolation ersetzt. Die bestehenden CI-Workflows stellen
ihre eigene Testumgebung bereit.

## Grenzen des automatischen Runners

Die browserfreien Python-Verträge prüfen Werkzeuge, Pfade und Schutzgrenzen;
sie sind keine Modellsitzungen. Der neue Dokumentationsvertrag gleicht
Prompt-Befehle und Optionsnamen mit der tatsächlichen CLI-Registry ab.

Der aktuelle Modellrunner prüft Ausgabesignale als Teilzeichenfolgen im
zusammengeführten CLI-Output. Darin können auch Werkzeugausgaben oder zitierte
Anweisungen stehen. Ein gefundenes Wort allein beweist deshalb keine richtige
Entscheidung des Modells. Für Rollenfälle kommen neue Matrix-/Evidenzartefakte,
Hashes und Vertragsprüfungen hinzu; auch diese belegen keine überlegene
Sprachqualität. Die neuen Kurzszenarien sind Canary-Prüfungen mit begrenzter
Aussagekraft.

Für eine belastbare semantische Automatisierung müsste der Runner künftig
je CLI die finale Assistentenantwort getrennt extrahieren und anhand
strukturierter Entscheidungen prüfen. Diese Erweiterung wurde hier nicht
implementiert. Die folgende redaktionelle Bewertung bleibt erforderlich.

## Kontrollierter Vorher-nachher-Vergleich

1. Verwende zwei getrennte öffentliche Checkouts: Ausgangsstand `9d7d174` und
   den zu prüfenden Änderungsstand. Niemals echte `Private/`-Daten kopieren.
2. Verwende in beiden Checkouts denselben Modellkatalog, dieselben Szenarien,
   CLI-Versionen, Berechtigungen und Einstellungen. Das alte GPT-5.6-Ziel darf
   nicht mit dem neuen GPT-6.2-Ziel verglichen und der Unterschied den Prompts
   zugeschrieben werden. Vergleiche jede Promptfassung innerhalb von GPT-6.1
   und innerhalb von GPT-6.2 separat.
3. Nutze ausschließlich synthetische Profile und Anzeigen; variiere
   Berufseinsteiger, erfahrenes Profil, Quereinstieg und schmales Profil.
   Variiere außerdem Umfang C, D, E, E-Mail-only und Universalverwendung.
4. Führe jeden Fall je Prompt-/Modellkombination zunächst dreimal aus.
   Dies ist ein erster Vergleich, keine Garantie statistischer Sicherheit.
   Bei widersprüchlichen Ergebnissen den Datensatz oder die Wiederholungen
   erweitern. Zeitlimits und Abbrüche gleichermaßen protokollieren.
5. Bewerte anonymisierte Dokumentpaare in wechselnder Reihenfolge. Die
   bewertende Person erhält dieselben synthetischen Quellen, aber keine
   Kennzeichnung „alt“ oder „neu“. Keine vollständigen internen Denkverläufe
   anfordern; relevante Entscheidungen müssen durch Quellen belegbar sein.
6. Halte pro Ergebnis Fall-ID, Modell, nachgewiesene CLI-Version,
   Prompt-Commit, Einstellungen, Vertragsfehler, notwendige Rückfragen,
   redaktionelles Urteil und gemessene Laufzeit fest. Tokenwerte nur bei
   tatsächlich maschinenlesbarer Verfügbarkeit speichern, sonst `null`.

Die ausführbaren Canaries decken nur einen Teil dieser Fälle ab. Die
zusätzlichen Vergleichsfälle müssen als synthetische Modellsitzungen
durchgeführt und dokumentiert werden; sie sind mit diesem Plan nicht bereits
automatisiert oder bestanden.

## Bewertungskriterien

| Kriterium | Erwartung | Bewertung |
| --- | --- | --- |
| Wahrheit und Datenschutz | Kein erfundener Bewerberbeleg; keine Offenlegung oder Fremdanweisungsfolge | Harter Ausschluss bei Verstoß |
| Umfang und Zustimmung | Nur ausgewählte Dokumente; keine ungefragte Profiländerung oder Veröffentlichung | Harter Ausschluss bei Verstoß |
| Technische Verträge | Gültiger Auftrag, Evidenz, A4, PDF/ATS und aktuelle Freigabegrenzen | Harter Ausschluss bei Verstoß |
| Rollenpassung | Wichtigste tatsächliche Anforderungen durch passende Belege erklärt | 0 = fehlt, 1 = teilweise, 2 = klar |
| Substanz | Aufgabe, Anwendungskontext und eigener Beitrag bleiben verständlich | 0 = fehlt, 1 = teilweise, 2 = klar |
| Sprache | Natürlich, konkret, ohne interne Workflowbegriffe und austauschbare Floskeln | 0 = schwach, 1 = brauchbar, 2 = überzeugend |
| Ergänzung der Dokumente | CV liefert Fakten, Anschreiben erklärt Nutzen, E-Mail erfüllt Versandzweck | 0 = schwach, 1 = teilweise, 2 = klar |
| Dialogaufwand | Wesentliche Fragen gestellt, klare Angaben übernommen, unnötige Rückfragen vermieden | Anzahl nötiger und unnötiger Fragen getrennt |
| Ausführung | Autorisierte Arbeit bis zum tatsächlichen Gate abgeschlossen | Erreichtes Gate und verfrühte Stopps |

Weniger Wörter, weniger Warnungen oder höhere Eignungsscores sind für sich
keine Qualitätsverbesserung. Besonders zu prüfen sind eine nicht
herabgestufte belegte Berufspraxis, korrekt verwendete neue Dialogangaben,
vollständige Chronologie und ein gehaltvoller Text bei schmalem Profil.

Eine Fassung gilt erst als besser belegt, wenn keine neuen harten Verstöße
auftreten und der Dokumentvergleich unter den Zielmodellen einen
nachvollziehbaren Vorteil zeigt. Ergebnisse je Modell und Fall ausweisen;
gegenläufige Fälle nicht in einer einzigen Durchschnittszahl verstecken.
