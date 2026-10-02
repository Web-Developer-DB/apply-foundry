# Technischer Workflow und Freigabe

Diese Referenz richtet sich an Agenten und technisch Interessierte. Für den normalen Nutzer führt der [Quickstart](../README.md#schnellstart) durch den Dialog. Verbindlich bleiben [AGENTS.md](../AGENTS.md), die [kanonische Startdatei](../Prompts/00_AGENTEN_START_HIER.md) und die jeweils zuständigen Promptmodule.

## Ablauf und feste Verträge

1. Dokumentumfang, Firma, Rolle und offene Tatsachen klären.
2. Privaten Auftrag mit dem Dispatcher `neu` anlegen oder aus Originalartefakten fortsetzen.
3. Stellenbeschreibung, Profilabgleich, Anforderungsmatrix und Evidenz vorbereiten.
4. Aus belegten Angaben genau die gewählten Kandidatendateien erstellen.
5. Dialog, Stammdaten, Inhalt und statische A4-Struktur prüfen.
6. Umfangsabhängige Layoutbilder, PDFs und ATS-Nachweise über `finalisieren` erzeugen.
7. Alle genannten PNGs beziehungsweise bei bestätigter reiner E-Mail die Textdatei persönlich prüfen.
8. Eine neue eindeutige Bestätigung abwarten, Sichtfreigabe an den unveränderten Artefaktsatz binden und lokal veröffentlichen.

Nach jeder sinnvollen Grenze aktualisiert der Agent den privaten Checkpoint über den Dispatcher. Der Checkpoint speichert Schritt, Status, Pfade, Größen und SHA-256-Werte; er ersetzt weder Wahrheits- noch Freigabenachweise.

HTML-Dokumente verwenden eingebettetes CSS mit `@page { size: A4; margin: 0; }` und `.page { width: 210mm; height: 297mm; }`. Eine feste Höhe darf nicht durch `min-height` ersetzt werden. Eine ausgewählte E-Mail ist ausschließlich UTF-8-Markdown mit dem Firmen-Slug aus dem Auftrag.

`Stellenbeschreibung.md`, `Analyse.md`, `Qualitaetscheck.md` und `Druck-Hinweis.md` enthalten die tatsächlichen gemeinsamen Nachweise. Leere oder als Dummy gedachte Dateien sind unzulässig.

<a id="arbeitsordner-und-ergebnisse"></a>

## Arbeitsordner und Ergebnisse

Während der Bearbeitung liegen Quellen, Kandidaten und Prüfnachweise ausschließlich unter einem privaten Arbeitsordner:

```text
Private/Bewerbungen/
└── FIRMA/
    └── _Arbeitsdateien/
        └── YYYY-MM-DD--ROLLE/
            ├── Bewerbungsauftrag.json
            ├── Anforderungsmatrix.json
            ├── Kandidat/
            ├── Layoutcheck/
            ├── PDF-Export/
            ├── ATS-Pruefbericht.json
            ├── Finalisierungsbericht.json
            └── Sichtfreigabe.json
```

Nach der lokalen Veröffentlichung entsteht ein getrennter Zielordner:

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLE/
├── Versand/
├── Intern/
└── Manifest.json
```

### Der veröffentlichte Bewerbungsordner

| Bereich | Zweck |
| --- | --- |
| `Versand/` | Nur die ausgewählten PDF-Anlagen und gegebenenfalls die E-Mail-Nachricht. Diesen Ordner nutzt du für einen späteren Versand. |
| `Intern/` | HTML-Quellen und interne Nachweise zur eigenen Dokumentation. Nicht mitsenden. |
| `Manifest.json` | Hashgebundene Liste der veröffentlichten Dateien und ihres Dokumentumfangs. |

### Welche Datei nutze ich für welchen Zweck?

| Datei | Verwendung |
| --- | --- |
| `Lebenslauf - NACHNAME.VORNAME.pdf` | Versand, wenn ein individueller oder universeller Lebenslauf ausgewählt wurde |
| `Anschreiben - NACHNAME.VORNAME.pdf` | Versand, wenn ein Anschreiben ausgewählt wurde |
| `Email-Nachricht--FIRMEN-SLUG.md` | Vorlage für eine manuelle E-Mail, wenn sie ausgewählt wurde |
| `Finalisierungsbericht.json` | technischer Nachweis des aktuellen Vorbereitungsstands, nicht versenden |
| `Sichtfreigabe.json` | persönlicher Freigabenachweis, nicht versenden |
| `Tokenverbrauch.json` | optionaler privater Diagnosebericht, nicht versenden |

### Offene Fragen

Unklare, aber für eine Bewerbung wichtige Angaben stehen im Arbeitsstand. Der Agent darf offene Fragen nicht durch plausible Formulierungen ersetzen. Kläre sie, bevor du die Kandidatendateien freigibst.

---

## Technische Vorbereitung

Der verbindliche technische Abschluss verwendet immer den vollständigen Dispatcher:

```bash
python3 Tools/bewerbung.py finalisieren \
  --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLE" \
  --browser auto
```

Er prüft Dialog und Stammdaten, statische Kandidatenstruktur, Inhalt, Browserlayout, PDF-Export und ATS-Textschicht in fester Reihenfolge. Bei ausgewählten HTML-Dokumenten gehören frische PNG-Screenshots und PDFs zum Ergebnis. Bei einer ausgewählten reinen E-Mail werden Browser-, PDF- und ATS-Schritte korrekt als nicht erforderlich dokumentiert.

Nach der technischen Vorbereitung gilt:

- `bereit_zur_sichtpruefung`: Öffne jede genannte PNG-Datei und bestätige erst danach die Freigabe.
- `layout_ueberarbeitung_erforderlich`: Der zweiseitige Lebenslauf hat eine unzulässige freie Fläche; verteile belegte, relevante Inhalte neu oder dokumentiere eine zulässige Ausnahme.
- Fehler oder geänderte Quellen: Unterlagen überarbeiten und den vollständigen Lauf erneut ausführen.

Die Freigabe-ID und alle geprüften Artefakthashes müssen beim späteren Veröffentlichen noch aktuell sein. Ein veralteter Screenshot oder ein geänderter Kandidat kann nicht weiterverwendet werden.

## Persönliche Prüfung, Layout und Veröffentlichung

### Seiten persönlich prüfen

Bei HTML-Unterlagen erzeugt die technische Vorbereitung eine PNG-Datei pro A4-Seite. Öffne jede genannte Datei und prüfe Inhalt, Namen, Daten, Lesbarkeit, Seitenaufteilung und vollständige Darstellung. Änderungen am Kandidaten oder an seinen Quellen entwerten frühere PNG-, PDF-, ATS- und Sichtnachweise; danach muss der Agent alles erneut vorbereiten.

Bei einem zweiseitigen Lebenslauf gilt zusätzlich:

- Seite 1 zeigt die stärksten belegten Auswahlkriterien für die Zielrolle.
- Seite 2 ist ein geschlossener fachlicher Block und keine Restseite.
- Beide Seiten haben einen markierten Seitenkopf, eindeutige Abschnittskennungen und einen festen `page-footer`.
- Eine ungewöhnlich große freie Fläche im nutzbaren Inhaltsbereich sperrt die Sichtfreigabe. Inhalte werden dabei nicht erfunden oder künstlich zusammengedrückt.

In seltenen Fällen kann der Agent nur mit einer konkreten, im Finalisierungsbericht gespeicherten Begründung eine Dichteausnahme vorbereiten:

```bash
python3 Tools/bewerbung.py finalisieren \
  --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLE" \
  --dichteausnahme-begruendung "Seite: ... Beleglage: ... Einseiter: ..."
```

Diese Ausnahme ersetzt nie deine persönliche Sichtprüfung.

### Lokale Freigabe bestätigen

Nach einem erfolgreichen Vorbereitungslauf stoppt der Agent bei `bereit_zur_sichtpruefung`. Erst nach deiner eindeutigen Bestätigung speichert er die hashgebundene Sichtfreigabe und darf anschließend lokal veröffentlichen:

```bash
python3 Tools/bewerbung.py freigabe \
  --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLE" \
  --freigabe-id FR-XXXXXXXXXXXX \
  --bestaetigt \
  --notiz "Alle finalen Seiten persönlich geprüft."

python3 Tools/bewerbung.py finalisieren \
  --arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLE" \
  --veroeffentlichen
```

Die Veröffentlichung ist ausschließlich eine lokale Freigabe in deinem privaten Bewerbungsordner. Der Workflow lädt nichts hoch und sendet keine E-Mail an ein Unternehmen.

## Hashbindung und Prüfgrenzen

SHA-256-Werte binden Quellen, Kandidaten, Screenshots, PDFs und Freigabe an ihren aktuellen Stand. Jede relevante Quellen- oder Kandidatenänderung entwertet bestehende Nachweise. Ein vollständiger neuer Vorbereitungslauf und eine neue persönliche Bestätigung sind erforderlich.

Der Browser prüft zuerst eine lokale A4-Druckprobe, danach Seitengeometrie und Dichte. Der PDF-Export prüft Seitenzahl, A4-Format und zulässige Linkannotationen; die ATS-Prüfung untersucht die Textschicht. Diese technischen Nachweise beweisen keine fachliche Wahrheit oder allgemeine Kompatibilität mit jedem Bewerbermanagementsystem.

Details stehen in [HTML-/CSS-Regeln](../Prompts/08_HTML_CSS_DESIGNREGELN.md), [Datei- und Ordnerregeln](../Prompts/10_DATEI_UND_ORDNER_REGELN.md) und [technischem Abschluss](../Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md).

[Zurück zur README](../README.md#pruefen-und-lokal-freigeben)
