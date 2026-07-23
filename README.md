<p align="center">
  <img src=".github/assets/readme-hero.svg" alt="bewerbungs-agent – passgenaue, ehrliche und versandfertige Bewerbungsunterlagen" width="100%">
</p>

<h1 align="center">bewerbungs-agent</h1>

<p align="center">
  <strong>Lokaler Bewerbungsassistent für passgenaue deutsche Bewerbungsunterlagen</strong><br>
  Von der Stellenanalyse bis zu visuell geprüften A4-Layouts und technisch geprüften PDFs.
</p>

<p align="center">
  <a href="CHANGELOG.md"><img src="https://img.shields.io/badge/Version-1.3-2563EB?style=flat-square" alt="Aktuelle Version 1.3"></a>
  <a href="https://github.com/Web-Developer-DB/bewerbungs-agent/actions/workflows/tests.yml"><img src="https://github.com/Web-Developer-DB/bewerbungs-agent/actions/workflows/tests.yml/badge.svg" alt="Status der automatischen Tests"></a>
  <img src="https://img.shields.io/badge/Windows%20%2B%20PowerShell-stabil-16A34A?style=flat-square" alt="Windows und PowerShell stabil unterstützt">
  <a href="LINUX-PORTIERUNGSPLAN.md"><img src="https://img.shields.io/badge/Linux-Alpha-F59E0B?style=flat-square" alt="Linux-Unterstützung im Alpha-Status"></a>
  <img src="https://img.shields.io/badge/Datenschutz-Local--first-7C3AED?style=flat-square" alt="Datenschutz nach dem Local-first-Prinzip">
</p>

<p align="center">
  <a href="#nutzung">👤 Nutzung</a> ·
  <a href="#schnellstart">🚀 Schnellstart</a> ·
  <a href="#ergebnisse">🗂️ Dateien</a> ·
  <a href="#entwicklung">🧰 Entwicklung</a> ·
  <a href="#hilfe">❓ Hilfe</a>
</p>

---

## Auf einen Blick

| 🎯 **Passgenau** | 🔒 **Lokal & privat** | ✅ **Geprüft** |
| :---: | :---: | :---: |
| Jede Bewerbung wird neu aus Stelle und Profil aufgebaut. | Echte Daten und Ergebnisse bleiben unter `Private/`. | Inhalt, A4-Layout, PDFs und ATS-Textschicht werden kontrolliert. |

Aus einer Stellenbeschreibung und deinen Profildaten entstehen:

- ein rollenbezogener Lebenslauf als HTML und PDF
- ein passendes Anschreiben als HTML und PDF
- eine kurze E-Mail-Nachricht
- ein vollständiger privater Arbeits- und Prüfverlauf mit Analyse, Anforderungsmatrix, Screenshots und Qualitätsnachweisen

> [!NOTE]
> **Empfohlener Referenzworkflow:** Windows, PowerShell, OpenAI Codex und Chrome oder Edge. Die PowerShell-Tools sind stabil getestet; die [Linux-Unterstützung befindet sich noch im Alpha-Status](LINUX-PORTIERUNGSPLAN.md).

### So fließen deine Daten

```mermaid
flowchart LR
    A["📋 Stellenanzeige"] --> C["🧭 Auftrag & Matrix"]
    B["🔐 Private Profildaten"] --> C
    C --> D["📝 Kandidat"]
    D --> E["✅ Inhalt · Layout · PDF · ATS"]
    E --> F["👀 Sichtprüfung"]
    F --> G["📦 Versand · Intern · Manifest"]

    classDef input fill:#dbeafe,stroke:#2563eb,color:#172554
    classDef private fill:#ede9fe,stroke:#7c3aed,color:#2e1065
    classDef agent fill:#ccfbf1,stroke:#0f766e,color:#042f2e
    classDef check fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef output fill:#fef3c7,stroke:#d97706,color:#451a03
    class A input
    class B private
    class C agent
    class D input
    class E check
    class F private
    class G output
```

## Wähle deinen Einstieg

<table role="presentation">
  <tr>
    <td width="50%" valign="top">
      <strong>👤 Projekt nutzen</strong><br><br>
      Private Daten einrichten, eine Bewerbung erzeugen, alle Dateien verstehen und nur den geprüften Satz versenden.<br><br>
      <a href="#nutzung"><strong>Zur Nutzungsdokumentation →</strong></a>
    </td>
    <td width="50%" valign="top">
      <strong>🧰 Projekt weiterentwickeln</strong><br><br>
      Architektur, Prompt-System, Werkzeuge, technische Dateiverträge, Tests und Erweiterungspunkte nachvollziehen.<br><br>
      <a href="#entwicklung"><strong>Zur Entwicklerdokumentation →</strong></a>
    </td>
  </tr>
</table>

---

<a id="nutzung"></a>

## 👤 Für Nutzer

Dieser Abschnitt ist für alle, die mit dem Projekt Bewerbungen erstellen möchten. Du brauchst dafür keine Kenntnisse über den internen Code oder die Implementierung der Prüfwerkzeuge.

**Direkt zum Ziel:** [Schnellstart](#schnellstart) · [Ablauf verstehen](#prozess) · [Dateien verwenden](#ergebnisse) · [Private Daten](#daten) · [Finalisieren](#finalisierung) · [Probleme lösen](#hilfe)

<a id="schnellstart"></a>

### 🚀 Schnellstart

#### 1. Repository lokal öffnen

```powershell
git clone https://github.com/Web-Developer-DB/bewerbungs-agent.git
Set-Location bewerbungs-agent
```

Öffne den Ordner anschließend in Visual Studio Code mit Codex-Extension oder in einer lokal installierten Codex-Anwendung.

#### 2. Private Daten vorbereiten

Die mitgelieferten Beispieldateien enthalten ausschließlich fiktive Angaben. Kopiere sie bei einer **frischen Installation** unter Windows als lokale Arbeitsgrundlage. Der Sicherheitscheck bricht ab, falls bereits ein eigener Datenordner vorhanden ist:

```powershell
$privateDataPath = "Private/Daten"

if (Test-Path -LiteralPath $privateDataPath) {
  throw "Private/Daten existiert bereits. Vorhandene Daten werden nicht überschrieben."
}

New-Item -ItemType Directory -Path $privateDataPath | Out-Null
Copy-Item "Private.example/Daten/01_PERSOENLICHE_DATEN.example.md" "Private/Daten/01_PERSOENLICHE_DATEN.md"
Copy-Item "Private.example/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.example.md" "Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
Copy-Item "Private.example/Daten/README.md" "Private/Daten/README.md"
```

Ersetze danach alle Beispieldaten durch deine echten Angaben. Eine genaue Zuordnung findest du unter [Private Daten einrichten](#daten).

> [!IMPORTANT]
> Echte Kontaktdaten, Profildaten und Bewerbungen gehören ausschließlich nach `Private/`. Dieser Ordner wird von Git ignoriert und darf nicht veröffentlicht werden.

#### 3. Bewerbung beauftragen

Gib Codex eine konkrete Stellenbeschreibung mit diesem Auftrag:

```text
Nutze Prompts/00_AGENTEN_START_HIER.md und erstelle eine Bewerbung für diese Stellenbeschreibung:

<Stellenbeschreibung einfügen>
```

Der Agent liest Profildaten, Regeln und Designreferenzen, erstellt einen privaten Arbeitsordner und erzeugt die Bewerbung zunächst als prüfbaren Kandidaten.

#### 4. Ergebnisse prüfen und freigeben

Der Agent führt danach alle fachlichen und technischen Abschlussprüfungen aus. Öffne vor der Veröffentlichung jeden erzeugten A4-Screenshot und kontrolliere ihn vollständig selbst. Die zwei verbindlichen Befehle stehen unter [Finalisierung](#finalisierung).

> [!TIP]
> **Für die erste Bewerbung reicht dieser Pfad:** Daten kopieren → Beispieldaten ersetzen → zentralen Agentenauftrag senden → Screenshots prüfen → Veröffentlichung bestätigen.

<a id="prozess"></a>

### 🧭 So arbeitet der Agent

Der Agent trennt bewusst vier Zustände. Eine Datei ist nicht automatisch versandfertig, nur weil sie bereits einen final wirkenden Namen trägt.

| Zustand | Speicherort | Bedeutung | Versenden? |
| --- | --- | --- | :---: |
| 🟡 **Entwurf** | `_Arbeitsdateien/.../` | Planung, Vorlagen und noch ungeprüfte Entscheidungen | Nein |
| 🔵 **Kandidat** | `_Arbeitsdateien/.../Kandidat/` | vollständige, aber noch nicht freigegebene Bewerbung | Nein |
| 🟣 **Prüfnachweise** | `_Arbeitsdateien/.../Layoutcheck/`, `PDF-Export/` und Arbeitsordner | Screenshots, Prüfberichte und Hashnachweise | Nein |
| 🟢 **Veröffentlicht** | `YYYY-MM-DD--ROLLENNAME/` | visuell und technisch geprüftes Ergebnis | nur `Versand/` |

> [!IMPORTANT]
> **Zum Bewerben verwendest du ausschließlich `Versand/`.** Dateien unter `_Arbeitsdateien/` sind Arbeitsstände oder Prüfnachweise. Dateien unter `Intern/` helfen dir beim Nachvollziehen und späteren Überarbeiten, werden aber nicht mitgeschickt.

#### Der Ablauf in sieben Phasen

1. **Stammdaten prüfen** – Identität, Kontakt und zentrale Bewerbungsentscheidungen werden kontrolliert. Kritische Lücken stoppen den Ablauf.
2. **Arbeitsbereich anlegen** – Der Agent erzeugt einen leeren Zielordner, einen privaten Arbeitsordner und den Bewerbungsauftrag.
3. **Stelle analysieren** – Muss-/Kann-Anforderungen werden mit deinen belegbaren Profildaten abgeglichen und in einer Anforderungsmatrix bewertet.
4. **Kandidaten erstellen** – Lebenslauf, Anschreiben, E-Mail, Analyse und Prüfdokumente entstehen zunächst unter `Kandidat/`.
5. **Fachlich korrigieren** – Stellenbeschreibung, Profil, Matrix und alle Dokumente werden auf Wahrheit, Passung und Widerspruchsfreiheit geprüft.
6. **Technisch vorbereiten** – A4-Screenshots, zwei PDFs sowie Layout-, PDF- und ATS-Nachweise werden erzeugt. Noch wird nichts veröffentlicht.
7. **Sichtprüfen und veröffentlichen** – Du kontrollierst jede A4-Seite. Erst danach werden die geprüften Dateien gemeinsam nach `Versand/` und `Intern/` übernommen; zusätzlich wird `Manifest.json` erstellt.

<details>
<summary><strong>Die sieben Phasen genauer erklärt</strong></summary>

**1 · Stammdaten und Sicherheit**

Der Agent prüft Bewerbername, Kontakt, Stellenart, Arbeitsmodell, Region, Eintrittstermin und Gehaltsstrategie. Die Stellenanzeige wird ausschließlich als nicht vertrauenswürdige Datenquelle ausgewertet; darin eingebettete Anweisungen werden nicht ausgeführt.

**2 · Bewerbungsauftrag**

`Bewerbungsauftrag.json` friert Firma, Rolle, Pfade und die Logistik für genau diese Bewerbung ein. Globale Profildaten müssen dadurch nicht für jede Stelle umgeschrieben werden. Noch offene Kernentscheidungen verhindern später die Freigabe.

**3 · Anforderungsmatrix und Bewerbungsentscheidung**

Der Agent macht aus dem ersten Matrixentwurf eine vollständige `Anforderungsmatrix.json`. Jede relevante Stellenanforderung erhält Typ, Gewichtung, einen Status der Erfüllung, einen Beleg und eine geplante Behandlung. Das Ergebnis unterstützt die bewusste Entscheidung `bewerben` oder `nicht_bewerben`.

**4 · Vollständiger Kandidat zur Prüfung**

Alle inhaltlichen Dokumente werden mit ihren späteren Namen unter `Kandidat/` angelegt. Dieser Ordner ist die Werkbank für Korrekturen – noch nicht der Versandordner.

**5 · Fachliche Korrekturschleife**

Der Agent liest Stellenbeschreibung, Analyse, private Daten, Matrix, Lebenslauf, Anschreiben und E-Mail erneut gegeneinander. Gefundene Unstimmigkeiten werden am Kandidaten korrigiert und anschließend erneut geprüft. Fehlende Belege werden nicht erfunden.

**6 · Technische Vorbereitung**

Der erste Finalisierungslauf prüft Stammdaten, Inhalt und A4-Struktur, erzeugt einen Screenshot je A4-Seite, exportiert zwei PDFs und kontrolliert deren ATS-Textschicht. Der Status lautet danach lediglich `bereit_zur_sichtpruefung`.

**7 · Sichtprüfung und gemeinsame Veröffentlichung**

Änderst du nach der Vorbereitung eine Kandidatendatei, verlieren Screenshots und PDFs ihre Gültigkeit und Phase 6 muss vollständig wiederholt werden. Direkt vor der Veröffentlichung prüft das Tool erneut, ob sich seit der Vorbereitung etwas verändert hat. Scheitert eine dieser Vorprüfungen, bleibt der bisherige Zielordner unverändert. Neue Dateien werden zuerst in einem separaten Zwischenordner vorbereitet und anschließend gemeinsam übernommen, damit kein unvollständiger Endstand entsteht.

</details>

<a id="ergebnisse"></a>

### 🗂️ Welche Dateien entstehen – und wofür sind sie da?

Die im Screenshot sichtbaren Ordner `Intern/`, `Versand/` und die Datei `Manifest.json` bilden den **veröffentlichten Endzustand**. Parallel bleibt unter `_Arbeitsdateien/` die private Werkstatt mit Entwürfen, Kandidaten und technischen Nachweisen erhalten.

#### Der veröffentlichte Bewerbungsordner

```text
Private/Bewerbungen/FIRMA/YYYY-MM-DD--ROLLENNAME/
├─ Versand/
│  ├─ Lebenslauf - NACHNAME.VORNAME.pdf
│  ├─ Anschreiben - NACHNAME.VORNAME.pdf
│  └─ Email-Nachricht--FIRMA.md
├─ Intern/
│  ├─ Stellenbeschreibung.md
│  ├─ Analyse.md
│  ├─ Lebenslauf - NACHNAME.VORNAME.html
│  ├─ Anschreiben - NACHNAME.VORNAME.html
│  ├─ Qualitaetscheck.md
│  ├─ Druck-Hinweis.md
│  └─ optional Offene_Fragen.md
└─ Manifest.json
```

##### `Versand/` – das benutzt du für die Bewerbung

| Datei | Verwendung |
| --- | --- |
| `Lebenslauf - NACHNAME.VORNAME.pdf` | als ersten PDF-Anhang beifügen |
| `Anschreiben - NACHNAME.VORNAME.pdf` | als separaten PDF-Anhang beifügen |
| `Email-Nachricht--FIRMA.md` | Betreff und Nachricht in dein E-Mail-Programm kopieren; die Markdown-Datei nicht anhängen |

Eine Stellenanzeige mit der Bitte um eine Bewerbung „als PDF“ verlangt nicht automatisch eine Gesamt-PDF. Lebenslauf und Anschreiben bleiben standardmäßig zwei getrennte Anlagen; zusammengeführt wird nur bei ausdrücklicher Vorgabe.

##### `Intern/` – deine lesbare Dokumentation

| Datei | Zweck | So kannst du sie nutzen |
| --- | --- | --- |
| `Stellenbeschreibung.md` | gespeicherte Ausgangsanzeige | später nachlesen und zur Gesprächsvorbereitung verwenden, auch wenn die Online-Anzeige nicht mehr verfügbar ist |
| `Analyse.md` | Passung, Profilstrategie, stärkste Argumente, Risiken und bewusste Auslassungen | Bewerbungsentscheidung nachvollziehen und auf ein Vorstellungsgespräch vorbereiten |
| `Lebenslauf - … .html` | geprüfter HTML-Stand des Lebenslaufs | im Browser ansehen und als nachvollziehbare Dokumentquelle archivieren |
| `Anschreiben - … .html` | geprüfter HTML-Stand des Anschreibens | im Browser ansehen und als nachvollziehbare Dokumentquelle archivieren |
| `Qualitaetscheck.md` | fachlicher Anforderungsabgleich plus technischer Abschlussstatus | kontrollieren, was geprüft wurde und welche Warnungen dokumentiert sind |
| `Druck-Hinweis.md` | Anleitung für das manuelle Drucken im Browser | nur verwenden, wenn du eine HTML-Datei manuell drucken oder als PDF sichern musst |
| `Offene_Fragen.md` | nicht erfundene, noch offene oder bewusst dokumentierte Punkte | vor dem Versand lesen und verbleibende Fragen soweit möglich klären |

> [!NOTE]
> Wenn du ein veröffentlichtes Dokument ändern möchtest, bearbeite nicht direkt die Datei unter `Intern/`. Ändere die passende Datei unter `_Arbeitsdateien/.../Kandidat/`, wiederhole die technische Vorbereitung und veröffentliche den neuen geprüften Satz mit `-Ersetzen`.

##### `Manifest.json` – Integrität des veröffentlichten Satzes

Das Manifest enthält Firma, Rolle, Erstellungszeit, Namen und Hashes von Stammdaten, Profil, Bewerbungsauftrag und Anforderungsmatrix sowie für jede veröffentlichte Datei unter `Versand/` und `Intern/` den relativen Pfad, die Bytezahl und den SHA-256-Wert. Es listet sich selbst sowie Entwürfe, Screenshots und Arbeitsberichte bewusst nicht auf.

Nutze das Manifest nicht als Bewerbungsanhang und bearbeite es nicht manuell. Der statische Prüfer kontrolliert damit die veröffentlichten Einträge aus `files[]` auf richtige Pfade, Größen und Hashes; die vier Quellhashes dienen dort nur als Herkunftsnachweis. Die bei der Vorbereitung erfassten Hashes der vier Quellen, der flachen Kandidatendateien und der Layout-PNGs stehen separat in `Finalisierungsbericht.json` – nicht jedoch sämtliche Entwürfe, Arbeitsnotizen oder Prüfberichte.

<details>
<summary><strong>Arbeitsdateien, Kandidaten und Prüfberichte kurz erklärt</strong></summary>

Alles in diesem Bereich bleibt privat und wird nicht versendet.

| Datei oder Ordner | Zweck | Was du damit tun kannst |
| --- | --- | --- |
| `Bewerbungsauftrag.json` | eingefrorener Auftrag mit Firma, Rolle, Logistik, Darstellungsoptionen und Bewerbungsentscheidung | vor der Dokumenterstellung auf richtige Entscheidungen prüfen; nach der Vorbereitung nicht still ändern |
| `Anforderungsmatrix--ENTWURF.json` | vom Ordnerhelfer erzeugtes Startgerüst | nicht als fertige Analyse verwenden; wird durch `Anforderungsmatrix.json` ersetzt |
| `Anforderungsmatrix.json` | vollständiger Muss-/Kann-Abgleich mit Gewichtung, Belegen und Behandlung | Passung und Risiken nachvollziehen; auch zur Interviewvorbereitung nützlich |
| `Arbeitsnotizen.md` | Zuordnung von Firma, Rolle und Ordnern | Arbeitsstand nachvollziehen; wird außerdem zur sicheren Fortsetzung einer Bewerbung benötigt |
| `*--ENTWURF.*` | vorbereitete Schreibgerüste für Analyse, HTML, E-Mail, Qualitätscheck und offene Fragen | nur als Arbeitsgrundlage betrachten; nie versenden |
| `Kandidat/` | vollständig benannter, aber noch nicht freigegebener Satz | hier Korrekturen vornehmen und danach alle Prüfungen erneut ausführen |
| `Kandidat/*.pdf` | während der Vorbereitung erzeugte und validierte PDF-Kandidaten | nicht direkt versenden; erst die veröffentlichten Kopien unter `Versand/` verwenden |
| `Stammdaten-Pruefbericht.json` | Ergebnis der Identitäts-, Kontakt- und Logistikprüfung | bei blockierenden Stammdatenfehlern zur Diagnose öffnen |
| `Inhalts-Pruefbericht.json` | Konsistenz-, Zeitraum-, Darstellungs- und Passungsprüfung | fachliche Fehler und Warnungen nachvollziehen |
| `Layoutcheck/*.png` | ein frischer Screenshot je expliziter A4-Seite | **jede PNG-Datei tatsächlich öffnen und visuell prüfen** |
| `Layoutcheck/Layoutcheck-Bericht.json` | Browser, Abmessungen, Seiten, Screenshot-Hashes und Dichtehinweise | Layoutwarnungen einer konkreten Seite zuordnen |
| `PDF-Export/PDF-Export-Bericht.json` | HTML-/PDF-Hashes, Dateigröße, Seitenzahl und A4-MediaBox | PDF-Exportfehler technisch einordnen |
| `ATS-Pruefbericht.json` | Textabdeckung, Pflichttexte und grundlegende Lesereihenfolge der PDFs | erkennen, ob Bewerbermanagementsysteme den PDF-Text voraussichtlich auslesen können |
| `Finalisierungsbericht.json` | Zustands- und Vorbereitungsnachweis mit den damals erfassten Quellen-, Kandidaten- und Screenshot-Hashes | Status und Prüflauf nachvollziehen; für die Integrität des veröffentlichten Endstands ist `Manifest.json` maßgeblich |

Die Entwurfsgerüste können nach Fertigstellung weiterhin im Arbeitsordner liegen. Sie sind keine zweite freigegebene Bewerbung. Maschinenlesbare Berichte und Screenshots werden absichtlich **nicht** nach `Intern/` kopiert.

</details>

#### Welche Datei nutze ich für welchen Zweck?

- 📤 **Bewerbung verschicken:** ausschließlich die zwei PDFs aus `Versand/` anhängen.
- ✉️ **E-Mail verfassen:** Betreff und Text aus `Versand/Email-Nachricht--FIRMA.md` kopieren.
- 👀 **Layout freigeben:** jede PNG-Datei unter `_Arbeitsdateien/.../Layoutcheck/` öffnen.
- 🔎 **Stellenpassung verstehen:** `Intern/Analyse.md` und bei Bedarf die private `Anforderungsmatrix.json` lesen.
- ✏️ **Dokument korrigieren:** nur den Kandidaten bearbeiten, danach Vorbereitung und Sichtprüfung wiederholen.
- 🧪 **Fehler untersuchen:** die passenden JSON-Berichte unter `_Arbeitsdateien/` öffnen.
- 🔐 **Veröffentlichten Satz prüfen:** die in `Manifest.json` unter `files[]` erfassten Dateien mit dem statischen Prüfer validieren.
- 🗄️ **Bewerbung nachvollziehbar archivieren:** finalen Ordner **und** zugehörigen Arbeitsordner behalten.

> [!WARNING]
> Lösche `_Arbeitsdateien` nicht vorschnell. Die zum Versand bestimmten PDFs bleiben zwar im finalen Ordner, aber du verlierst Kandidaten, Anforderungsmatrix, Screenshots, technische Nachweise und die saubere Grundlage für spätere Korrekturen.

#### Offene Fragen

Fehlen belastbare Informationen, legt der Agent `Offene_Fragen.md` an. Das betrifft zum Beispiel einen unklaren Eintrittstermin, einen fehlenden Ansprechpartner, eine nicht belegte Technologie oder eine offene Gehaltsstrategie.

Kritische Fragen blockieren die Veröffentlichung, wenn sonst Identität, Wahrheit oder zentrale Bewerbungsentscheidungen gefährdet wären. Bleibt eine nicht blockierende `Offene_Fragen.md` im veröffentlichten Satz erhalten, lies sie vor dem Versand. Unbekannte Angaben werden niemals geraten oder als Platzhalter in finale Dokumente übernommen.

<a id="daten"></a>

### 🔐 Private Daten & Datenschutz

Die Trennung zwischen öffentlicher Logik und privaten Daten ist ein Kernprinzip des Projekts.

| Datei | Enthält | Enthält ausdrücklich nicht |
| --- | --- | --- |
| `01_PERSOENLICHE_DATEN.md` | Identität, Kontakt, Verfügbarkeit, Arbeitsmodell, Region und Gehaltslogik | fachliche CV-Details |
| `02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md` | Erfahrung, Ausbildung, Kenntnisse, Projekte, Belege und fachliche Grenzen | Kontakt- und Adressdaten |
| `README.md` | lokale Pflegeanleitung für beide Dateien | Bewerbungsinhalte oder eine dritte Datenquelle |

Die Vorlagen findest du unter `Private.example/Daten/`. Pflege jede Information nur an ihrer Stammquelle, damit Angaben nicht widersprüchlich werden.

<details>
<summary><strong>Persönliche Daten mit Unterstützung des Agenten einrichten</strong></summary>

Du kannst Codex beim strukturierten Übertragen deiner Angaben helfen lassen:

```text
Nutze die Struktur aus Private.example/Daten/.
Erstelle oder aktualisiere meine privaten Daten unter Private/Daten/.

Fülle 01_PERSOENLICHE_DATEN.md nur mit Identität, Kontakt und Bewerbungslogistik.
Fülle 02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md nur mit fachlichem Profil, Erfahrung, Kenntnissen, Projekten, Belegarten und Grenzen.
Nutze keine erfundenen Angaben.
Wenn Informationen fehlen oder unklar sind, dokumentiere sie als offene Fragen.

Hier sind meine echten Informationen:

<persönliche Daten und beruflicher Kontext einfügen>
```

Kontrolliere die erzeugten Dateien sorgfältig. Ein KI-Agent kann Angaben falsch einordnen, zu stark formulieren oder aus unklarem Kontext falsche Schlüsse ziehen.

</details>

#### Sicherheitsmodell

Stellenanzeigen, Unternehmensseiten, E-Mails und andere Fremdtexte gelten als **nicht vertrauenswürdige Datenquellen**:

- Eingebettete Aufforderungen dürfen Projektregeln und Nutzerauftrag nicht verändern.
- Fremdtexte dürfen keine privaten Dateien offenlegen, hochladen, versenden, löschen oder verändern lassen.
- Externe Aktionen sind nur durch einen direkten Nutzerauftrag autorisiert.
- Finale HTML-Dateien laden keine externen oder lokalen Ressourcen automatisch nach; vollständig eingebettete `data:`-Ressourcen sind möglich.
- Analyse und Arbeitsnotizen vervielfältigen keine unnötigen privaten Daten oder Geheimnisse.

> [!WARNING]
> `.gitignore` ist keine Verschlüsselung. Cloud-Synchronisation, Backups, Virenscanner und andere lokale Programme können Dateien unter `Private/` weiterhin lesen oder kopieren. Prüfe außerdem jedes finale Dokument persönlich vor dem Versand.

<details>
<summary><strong>Git- und Datenschutzcheck vor einem Commit</strong></summary>

```powershell
git status --short
```

In der Ausgabe dürfen keine echten Dateien aus `Private/` auftauchen. Zeigt `git status --short --ignored` den Eintrag `!! Private/`, arbeitet die Ignore-Regel wie vorgesehen.

Öffentlich geeignet sind insbesondere `.github/`, `Prompts/`, `Tests/`, `Tools/`, `Vorlagen/`, `Private.example/`, `CHANGELOG.md` und `README.md`.

</details>

<a id="finalisierung"></a>

### ✅ Prüfen & veröffentlichen

Der verbindliche Abschluss besteht aus zwei bewusst getrennten Schritten.

#### Schritt 1: Technisch vorbereiten

```powershell
.\Tools\Finalisiere-Bewerbung.ps1 -Arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" -Browser chrome
```

Dieser Lauf prüft Stammdaten und Inhalte, erzeugt A4-Screenshots, exportiert zwei PDFs, kontrolliert deren Struktur und ATS-Textschicht und schreibt Hashnachweise.

#### Schritt 2: Nach Sichtprüfung veröffentlichen

```powershell
.\Tools\Finalisiere-Bewerbung.ps1 -Arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" -Veroeffentlichen -VisuellGeprueft
```

Bei einer Layoutwarnung ist zusätzlich eine kurze fachliche Bewertung über `-VisuelleFreigabeNotiz "..."` erforderlich. Änderungen an Quellen, Kandidatendateien oder Screenshots machen vorhandene Nachweise ungültig.

<details>
<summary><strong>Bereits veröffentlichte Bewerbung korrigieren</strong></summary>

Bearbeite veröffentlichte Dateien nicht direkt unter `Versand/` oder `Intern/`. Korrigiere die Quellen beziehungsweise Kandidatendateien, führe Schritt 1 erneut aus und kontrolliere alle neuen Screenshots. Erst danach darf der neu geprüfte Satz den bestehenden Zielordner bewusst ersetzen:

```powershell
.\Tools\Finalisiere-Bewerbung.ps1 -Arbeitsordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME" -Veroeffentlichen -VisuellGeprueft -Ersetzen
```

Bei Layoutwarnungen gilt auch hier zusätzlich `-VisuelleFreigabeNotiz "..."`.

</details>

#### Visuelle Kurzcheckliste

- [ ] Jede erwartete A4-Seite ist als frischer Screenshot vorhanden.
- [ ] Kein Text ist abgeschnitten oder verdeckt.
- [ ] Es gibt keine ungewollte Leerseite oder große zufällige Leerfläche.
- [ ] Schrift, Abstände und Spalten sind professionell lesbar.
- [ ] Lebenslauf, Anschreiben und E-Mail enthalten dieselben Kerndaten.
- [ ] Es stehen keine Platzhalter oder erfundenen Angaben in den Dateien.

<details>
<summary><strong>Einzelne Diagnose-, Layout- und Exportbefehle</strong></summary>

Die Einzeltools sind für Diagnose und Entwicklung nützlich. Bei einer neuen Bewerbung ersetzen sie nicht den zweistufigen Freigabeprozess.

In den folgenden Beispielen liegen die prüfbaren HTML-Dateien im Kandidatenordner; Berichte und temporäre Ausgaben bleiben daneben im privaten Arbeitsordner.

**Statischer Check**

```powershell
.\Tools\Pruefe-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat"
```

Warnungen können streng als Fehler behandelt werden:

```powershell
.\Tools\Pruefe-Bewerbung.ps1 -Ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat" -WarnungenAlsFehler
```

**Layout-Screenshots**

```powershell
.\Tools\Layoutcheck-Bewerbung.ps1 `
  -Ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat" `
  -OutputRoot "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Layoutcheck" `
  -Browser chrome
```

**PDF-Export**

```powershell
.\Tools\Exportiere-PDF.ps1 `
  -Ordner "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/Kandidat" `
  -OutputRoot "Private/Bewerbungen/FIRMA/_Arbeitsdateien/YYYY-MM-DD--ROLLENNAME/PDF-Export" `
  -Browser chrome
```

Der statische Prüfer kontrolliert Pflichtdateien, Dateinamen, Platzhalter, A4-Geometrie, eingebettetes CSS, unerlaubte Ressourcen und den E-Mail-Betreff. Layout- und Exporttools validieren zusätzlich PNG-/PDF-Signaturen, Abmessungen, Seitenzahlen und Aktualität.

</details>

<details>
<summary><strong>Manueller PDF-Export mit Firefox</strong></summary>

Wenn kein unterstützter Headless-Export verfügbar ist, kannst du zu Diagnosezwecken manuell drucken:

1. HTML-Datei in Firefox öffnen.
2. Mit <kbd>Strg</kbd> + <kbd>P</kbd> den Druckdialog öffnen.
3. `Weitere Einstellungen` aufklappen.
4. `Kopf- und Fußzeilen drucken` deaktivieren.
5. Skalierung auf `100 %` und Ränder auf `Keine` stellen.

Ein bewusst zweiseitiger Lebenslauf ist besser als ein gequetschtes oder abgeschnittenes Einseiten-Dokument.

> [!CAUTION]
> Dieser manuelle Export ist **kein gleichwertiger Ersatz** für den verbindlichen Finalisierungsworkflow: PDF-Struktur, ATS-Textschicht und Hashnachweise werden dabei nicht automatisch validiert. Eine vollständig geprüfte Veröffentlichung benötigt Chrome oder Edge.

</details>

### 🪟 Voraussetzungen & Plattformstatus

| Komponente | Status | Verwendung |
| --- | --- | --- |
| Windows + PowerShell 7 | 🟢 stabil | vollständig getesteter Referenzworkflow |
| Codex in VS Code oder lokale Codex-App | 🟢 empfohlen | liest Regeln und erzeugt lokale Dateien |
| Chrome oder Edge | 🔵 für Finalisierung erforderlich | Layoutcheck, automatischer PDF-Export und ATS-Prüfung |
| Firefox | 🟡 optional | manuelle Vorschau; kein Ersatz für die verbindliche Finalisierung |
| Linux + Bash | 🟠 Alpha | derzeit vor allem Ordnererstellung; [Portierungsplan](LINUX-PORTIERUNGSPLAN.md) |
| Git Bash | 🟡 Entwicklung | Bash-Regressionsfälle unter Windows |

Für die normale Nutzung brauchst du dieses Repository, gepflegte Daten unter `Private/Daten/`, einen lokal arbeitenden KI-Agenten und eine konkrete Stellenbeschreibung.

<details>
<summary><strong>Bewerbungsordner manuell anlegen</strong></summary>

Normalerweise übernimmt der Agent diesen Schritt.

Windows / PowerShell:

```powershell
.\Tools\Neue-Bewerbung.ps1 -Firma "Muster GmbH" -Rolle "Junior Webentwickler"
```

Linux / Bash (Alpha):

```bash
bash Tools/neue-bewerbung.sh --firma "Muster GmbH" --rolle "Junior Webentwickler"
```

Die Helfer erzeugen einen leeren Zielordner, einen Arbeitsordner und einen Kandidatenordner. Eine vorhandene Kombination aus Firma, Datum und Rolle wird nicht überschrieben. `-Fortsetzen` beziehungsweise `--fortsetzen` ist nur für dieselbe, über `Arbeitsnotizen.md` nachweisbare Bewerbung vorgesehen.

</details>

<a id="hilfe"></a>

### ❓ Häufige Probleme

| Problem | Schnellste Prüfung | Lösung |
| --- | --- | --- |
| Statischer Check ist rot | Fehlermeldung und betroffene Datei lesen | HTML/Markdown korrigieren und Check wiederholen |
| Layoutcheck startet nicht | Ist Chrome oder Edge installiert? | Unter Windows gezielt `-Browser chrome` verwenden |
| Browser scheitert in einer Sandbox | Browserfreigabe der lokalen Agentenumgebung prüfen | denselben Lauf mit lokaler Browserfreigabe wiederholen |
| PDF-Export bricht ab | Statischen Check separat ausführen | Fehler beheben; manueller Firefox-Druck ist nur eine nicht validierte Diagnosealternative |
| Text wirkt abgeschnitten | HTML und alle Seitenscreenshots öffnen | Inhalt fachlich kürzen oder bewusst auf zwei A4-Seiten verteilen |
| Persönliche Dateien erscheinen in Git | `git status --short --ignored` prüfen | Dateien nach `Private/` verschieben; nichts Privates in Git übernehmen |
| Informationen fehlen | `Offene_Fragen.md` lesen | belastbare Angaben ergänzen; keine Werte raten lassen |

Wenn du tiefer diagnostizieren möchtest, findest du die Einzelwerkzeuge im Abschnitt [Prüfen & veröffentlichen](#finalisierung).

### ⚠️ Bekannte Grenzen

- Der vollständig getestete Workflow ist Windows mit PowerShell.
- Linux befindet sich im Alpha-Status und unterstützt noch nicht den gesamten Ablauf in gleicher Qualität.
- Automatischer PDF-Export unterstützt Chrome und Edge, nicht Firefox.
- HTML- und PDF-Prüfungen sind konservativ auf den unterstützten Chromium-Export ausgerichtet; ungewöhnliche Designs und andere PDF-Erzeuger benötigen zusätzliche Regressionstests.
- Eine echte manuelle Sichtprüfung bleibt erforderlich, besonders bei neuen Designs und zweiseitigen Lebensläufen.
- Die Ergebnisqualität hängt von vollständigen, aktuellen und ehrlich gepflegten Profildaten ab.

---

<a id="entwicklung"></a>

## 🧰 Für Entwickler

Dieser Abschnitt richtet sich an Mitwirkende, die Prompts, Tools, Tests oder Dateiverträge verändern möchten. Wenn du das Projekt nur für eigene Bewerbungen verwendest, brauchst du die folgenden Implementierungsdetails nicht.

| Einstieg | Inhalt |
| --- | --- |
| [Änderungsprotokoll](CHANGELOG.md) | Releases, Korrekturen und Testnachweise |
| [Prompt-System](Prompts/README.md) | Agentenablauf und fachliche Regelmodule |
| [Vorlagen](Vorlagen/README.md) | HTML-Designreferenzen und Matrixbeispiel |
| [Technische Dateiverträge](#dateivertraege) | vollständiger Artefaktbaum, Prüfberichte und Hash-Scope |
| [Linux-Portierungsplan](LINUX-PORTIERUNGSPLAN.md) | geplanter gleichwertiger Windows-/Linux-Betrieb |
| [Archivierter Frontend-Plan](frontend-project.old.md) | historischer Plan einer Electron-Oberfläche |
| [CI-Workflow](.github/workflows/tests.yml) | Windows-/Ubuntu-Testmatrix |

### Projektprinzipien

- **Öffentliche Logik, private Daten:** Regeln, Tools und Tests sind öffentlich; Profildaten und Bewerbungen bleiben lokal.
- **Wahrheit durch Konstruktion:** Arbeitgeber, Zeiträume, Kenntnisse und Zertifikate dürfen nicht erfunden werden.
- **Kandidat zuerst:** Die finalen Dateien entstehen zunächst in einem Kandidatenordner und werden erst nach allen Prüfungen veröffentlicht.
- **Gemeinsame Veröffentlichung:** `Versand/`, `Intern/` und `Manifest.json` werden getrennt vom Ziel vorbereitet und anschließend als zusammengehörige Einheit übernommen.
- **Reproduzierbare Nachweise:** Der Finalisierungsbericht bindet den vorbereiteten Kandidaten an Quellen und Screenshots; das Manifest bindet separat den veröffentlichten Satz.

<details>
<summary><strong>Öffentliche und private Projektstruktur</strong></summary>

```text
bewerbungs-agent/
├─ .github/
│  ├─ assets/readme-hero.svg
│  └─ workflows/tests.yml
├─ CHANGELOG.md
├─ LINUX-PORTIERUNGSPLAN.md
├─ README.md
├─ Prompts/                  # Agenten- und Qualitätsregeln
├─ Private.example/          # ausschließlich fiktive Beispieldaten
├─ Tests/                    # PowerShell- und Bash-Regressionstests
├─ Tools/                    # Ordner-, Prüf-, Layout- und Exporttools
└─ Vorlagen/                 # HTML-Designreferenzen und Matrixbeispiel
```

Die lokale, ignorierte Struktur:

```text
Private/
├─ Daten/
│  ├─ README.md
│  ├─ 01_PERSOENLICHE_DATEN.md
│  └─ 02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md
└─ Bewerbungen/
   └─ FIRMA/
      ├─ _Arbeitsdateien/
      │  └─ YYYY-MM-DD--ROLLENNAME/
      │     ├─ Bewerbungsauftrag.json
      │     ├─ Anforderungsmatrix--ENTWURF.json
      │     ├─ Anforderungsmatrix.json
      │     ├─ Arbeitsnotizen.md
      │     ├─ ggf. Stellenbeschreibung--ENTWURF.md
      │     ├─ Analyse--ENTWURF.md
      │     ├─ Lebenslauf--FIRMA--ENTWURF.html
      │     ├─ Anschreiben--FIRMA--ENTWURF.html
      │     ├─ Email-Nachricht--FIRMA--ENTWURF.md
      │     ├─ Qualitaetscheck--ENTWURF.md
      │     ├─ Offene_Fragen--ENTWURF.md
      │     ├─ Stammdaten-Pruefbericht.json
      │     ├─ Inhalts-Pruefbericht.json
      │     ├─ ATS-Pruefbericht.json
      │     ├─ Finalisierungsbericht.json
      │     ├─ Kandidat/
      │     │  ├─ Stellenbeschreibung.md
      │     │  ├─ Analyse.md
      │     │  ├─ Lebenslauf - NACHNAME.VORNAME.html
      │     │  ├─ Anschreiben - NACHNAME.VORNAME.html
      │     │  ├─ Email-Nachricht--FIRMA.md
      │     │  ├─ Qualitaetscheck.md
      │     │  ├─ Druck-Hinweis.md
      │     │  ├─ optional Offene_Fragen.md
      │     │  └─ zwei PDFs nach der Vorbereitung
      │     ├─ Layoutcheck/
      │     │  ├─ Layoutcheck-Bericht.json
      │     │  └─ eine *--seite-X-von-Y--BROWSER.png je A4-Seite
      │     └─ PDF-Export/
      │        └─ PDF-Export-Bericht.json
      └─ YYYY-MM-DD--ROLLENNAME/
         ├─ Versand/
         ├─ Intern/
         └─ Manifest.json
```

`Anforderungsmatrix--ENTWURF.json` ist nur das Startgerüst; verbindlich ist anschließend `Anforderungsmatrix.json`. Entwurfsgerüste können im privaten Arbeitsordner verbleiben, dürfen aber weder als Kandidat noch als Veröffentlichung interpretiert werden.

Weitere private Bereiche wie `Archiv/`, `Bewertungen/` oder `LebenslaufUniversal/` können lokal existieren, gehören jedoch nicht zum aktuellen Standardablauf einer einzelnen Bewerbung.

</details>

### Prompt-System

Zentraler Einstieg ist [`Prompts/00_AGENTEN_START_HIER.md`](Prompts/00_AGENTEN_START_HIER.md). Änderungen gehören in das fachlich passende Modul:

| Datei | Verantwortung |
| --- | --- |
| `02_VORPRUEFUNG_UND_ANFORDERUNGSMATRIX.md` | Stammdaten-Gate, Auftrag und gewichtete Muss-/Kann-Matrix |
| `03_LEBENSLAUF_REGELN.md` | deutscher CV-Standard, Priorisierung und A4-Seitenstrategie |
| `04_ANSCHREIBEN_REGELN.md` | Struktur, Ton, Gehaltswunsch und Grenzen |
| `05_EMAIL_NACHRICHT_REGELN.md` | kurze Versandnachricht |
| `06_ROLLENLOGIK.md` | Zielrolle, Bewerbungslogistik und Profilgewichtung |
| `07_WAHRHEIT_UND_GRENZEN.md` | Belege, Sicherheitsgrenzen und ehrliche Formulierungen |
| `08_HTML_CSS_DESIGNREGELN.md` | A4-Geometrie und eigenständige HTML-Dateien |
| `09_QUALITAETSCHECK.md` | fachliche und technische Checkliste |
| `10_DATEI_UND_ORDNER_REGELN.md` | private Ordner, Dateinamen und Slugs |
| `11_TECHNISCHER_CHECK_WORKFLOW.md` | Staging, Finalisierung, Layout, PDF und Hashnachweise |

### Tools im Überblick

| Tool | Aufgabe | Typischer Einstieg |
| --- | --- | --- |
| `Neue-Bewerbung.ps1` | Arbeits- und Zielstruktur erzeugen | `-Firma "..." -Rolle "..."` |
| `neue-bewerbung.sh` | Bash-Variante des Ordnerhelfers | `--firma "..." --rolle "..."` |
| `Pruefe-Stammdaten.ps1` | Identität, Kontakt und Logistik prüfen | ohne Parameter oder mit Auftragspfad |
| `Pruefe-Bewerbungsinhalt.ps1` | Inhalt gegen Auftrag und Matrix prüfen | `-Ordner "..." -AuftragPath "..." -AnforderungsmatrixPath "..."` |
| `Pruefe-Bewerbung.ps1` | statischen Mindestcheck ausführen | `-Ordner "..."` |
| `Layoutcheck-Bewerbung.ps1` | A4-Screenshots und Dichtebericht erzeugen | Kandidaten- und `-OutputRoot`-Pfad übergeben |
| `Exportiere-PDF.ps1` | zwei PDFs sicher exportieren und prüfen | Kandidaten- und `-OutputRoot`-Pfad übergeben |
| `Pruefe-ATS.ps1` | Unicode-Textschicht und Lesereihenfolge prüfen | Bestandteil der Finalisierung |
| `Finalisiere-Bewerbung.ps1` | verbindliches Prepare-/Publish-Gate | `-Arbeitsordner "..."` |

<a id="dateivertraege"></a>

### Technische Artefakte & Dateiverträge

Die Nutzungsdokumentation beschreibt, wofür Menschen die Dateien verwenden. Für Implementierungen gilt zusätzlich folgender verbindlicher technischer Ablauf:

| Artefaktgruppe | Erzeuger | Verbindlichkeit | Hauptverbraucher |
| --- | --- | --- | --- |
| `Bewerbungsauftrag.json` | Ordnerhelfer, danach Agent | Pflichtquelle für Pfade, Logistik, Darstellungsoptionen und Bewerbungsentscheidung | Stammdaten-, Inhalts- und Finalisierungswerkzeug |
| `Anforderungsmatrix.json` | Agent aus dem Entwurfsgerüst | Pflicht vor Dokumenterstellung und Finalisierung | Inhaltsprüfer und fachlicher Abschlusstest |
| `Kandidat/*` | Agent; PDFs durch Exporttool | vollständiger Release Candidate mit späteren Dateinamen | statischer Prüfer, Inhaltsprüfer, Layout, PDF, ATS und Publisher |
| Prüfberichte und Screenshots | jeweiliges Prüfwerkzeug | im Standard-Finalisierungsworkflow verpflichtende Nachweise | `Finalisiere-Bewerbung.ps1` und menschliche Sichtprüfung |
| `Versand/`, `Intern/`, `Manifest.json` | Finalisierungswerkzeug über privates Staging | einziger veröffentlichter Vertrag | Nutzer, Archivierung und nachträglicher statischer Check |

#### Maschinenlesbare Berichte

| Bericht | Zuständiges Tool | Wesentliche Inhalte |
| --- | --- | --- |
| `Stammdaten-Pruefbericht.json` | `Pruefe-Stammdaten.ps1` | Status, Fehler/Warnungen, Feldzustände sowie aufgelöste Bewerbungslogistik und deren Quelle |
| `Inhalts-Pruefbericht.json` | `Pruefe-Bewerbungsinhalt.ps1` | formale Zeiträume, Darstellungsmodi, Profil-Links, gewichtete Eignung sowie Fehler/Warnungen |
| `Layoutcheck/Layoutcheck-Bericht.json` | `Layoutcheck-Bewerbung.ps1` | Browser, Abmessungen, HTML- und Screenshot-Hashes, Seite/Seitenzahl und Dichtehinweise |
| `PDF-Export/PDF-Export-Bericht.json` | `Exportiere-PDF.ps1` | HTML-/PDF-Hashes, PDF-Größe, Seitenzahl und A4-MediaBox |
| `ATS-Pruefbericht.json` | `Pruefe-ATS.ps1` | extrahierbare Zeichen, Textabdeckung, Pflichttexte, Lesereihenfolge und Ergebnis je PDF |
| `Finalisierungsbericht.json` | `Finalisiere-Bewerbung.ps1` | Release-Status, Pfade, erwartete Screenshots, Warnungen sowie die bei der Vorbereitung erfassten Hashes der vier Quellen, flachen Kandidatendateien und PNGs |

`Pruefe-Bewerbung.ps1` schreibt bewusst keinen eigenen JSON-Bericht; sein Vertrag sind Konsolenausgabe und Exitcode.

#### `Manifest.json` und `Finalisierungsbericht.json` sind nicht dasselbe

| Eigenschaft | `Manifest.json` | `Finalisierungsbericht.json` |
| --- | --- | --- |
| Ablage | finaler Bewerbungsordner | privater Arbeitsordner |
| Entstehung | während der gemeinsamen Veröffentlichung | nach der technischen Vorbereitung, danach bei Veröffentlichung aktualisiert |
| Dateiumfang | nur veröffentlichte Dateien in `Versand/` und `Intern/`, ohne das Manifest selbst | vier Quellartefakte sowie alle bei der Vorbereitung vorhandenen Kandidatendateien einschließlich PDFs und Layout-PNGs |
| Nachweise | relativer Pfad, Bytezahl und SHA-256 je veröffentlichter Datei; Namen und Hashes der vier Quellartefakte als Provenienz | absolute Prüfpfade, vorbereitete Artefakte und SHA-256-Werte, Layoutwarnungen und Sichtfreigabenotiz |
| Statusfunktion | Integrität des veröffentlichten Satzes | Gate `bereit_zur_sichtpruefung` beziehungsweise `veroeffentlicht` |
| Prüfung | `Pruefe-Bewerbung.ps1` validiert Pfade, Größen und Hashes aus `files[]`; `sourceInputs` wird nicht erneut gegen die privaten Quellen geprüft | vor dem Zieltausch verweigert der Veröffentlichungslauf geänderte oder neue Quellen-, Kandidaten- und Screenshot-Artefakte |

Nach erfolgreicher Veröffentlichung ergänzt der Finalisierungsbericht Pfad und SHA-256 des veröffentlichten Manifests. Die Hashes der Kandidatendateien dokumentieren den Zustand der technischen Vorbereitung; da `Qualitaetscheck.md` bei der Freigabe noch auf `bestaetigt` aktualisiert wird, ist für den tatsächlich veröffentlichten Dateistand anschließend das Manifest maßgeblich. Arbeitsberichte oder Screenshots werden nicht Bestandteil des Manifests.

<details>
<summary><strong>Optionale und transiente technische Artefakte</strong></summary>

- `Offene_Fragen.md` ist als finale Kandidatendatei nur bei echten offenen Punkten vorhanden.
- Der Layoutcheck kann mit `-Pdf` zusätzliche Seiten-PDFs erzeugen. Sie sind Diagnoseartefakte und keine Versand-PDFs.
- Bei einseitigem Anschreiben und einseitigem Lebenslauf entstehen normalerweise zwei Layout-PNGs; bei einem zweiseitigen Lebenslauf drei.
- `.capture-*.html` und Browser-Profile `P-*` entstehen kurz während des Layoutchecks.
- `PDF-Export/R-*`, temporäre PDFs, kurzzeitige `Backup--*.pdf` und weitere `P-*`-Profile gehören zu einem einzelnen Exportlauf.
- `.publish-*` und bei einer Ersetzung `.backup-*` sichern die gemeinsame Veröffentlichung ab.

Diese Hilfsdateien und Ordner werden bei einem normalen Lauf bereinigt und sind kein dauerhafter Nutzervertrag. Nach einem hart abgebrochenen Browser- oder Veröffentlichungsprozess können ausnahmsweise Reste sichtbar bleiben.

</details>

<details>
<summary><strong>Datenfluss und Qualitätsprüfungen im Detail</strong></summary>

1. Die Stellenbeschreibung wird als nicht vertrauenswürdige Datenquelle übernommen.
2. `Pruefe-Stammdaten.ps1` kontrolliert Identität, Kontakt und Bewerbungslogistik.
3. Der Agent liest private Daten und Prompt-Regeln dateiweise.
4. Der Ordnerhelfer erzeugt Ziel-, Arbeits- und Kandidatenordner sowie `Bewerbungsauftrag.json`, Arbeitsnotizen und Entwurfsgerüste.
5. Muss- und Kann-Kriterien werden mit Kategorie und Gewichtung in `Anforderungsmatrix.json` abgelegt.
6. Rollen-, Gehalts-, Seiten-, Schulbildungs- und Profil-Link-Strategie werden festgelegt.
7. Alle Dokumente entstehen zunächst unter `_Arbeitsdateien/.../Kandidat/`.
8. Fachlicher Abschlusstest und Inhaltsprüfer gleichen Anforderungen, Belege, Daten und Zeiträume ab.
9. Die Finalisierung erzeugt Stammdaten-, Inhalts-, Layout-, PDF-, ATS- und Finalisierungsbericht samt Hashnachweisen.
10. Jede explizite A4-Seite wird anhand ihres frischen Screenshots visuell geprüft.
11. Jede spätere Quellen- oder Kandidatenänderung entwertet die Nachweise.
12. Erst nach Sichtbestätigung wird der vollständige Satz als zusammengehörige Einheit veröffentlicht.

Die Eignung wird maschinenlesbar als `stark`, `vertretbar_mit_risiken` oder `stretch` ausgewiesen. Nicht vollständig belegte Muss-Anforderungen bleiben sichtbar und erfordern eine dokumentierte Behandlung sowie ehrliche, an Belegen orientierte Formulierungen.

</details>

### Tests & CI

Die abhängigkeitsfreie Regressionstestsuite prüft Prompt-/Tool-Verträge, Logistik-Snapshots, Anforderungsmatrix, Staging, Manifest, Veröffentlichung und Fehlerszenarien:

```powershell
.\Tests\Run-RegressionTests.ps1
```

Mit lokaler Chrome-Matrix:

```powershell
.\Tests\Run-RegressionTests.ps1 -MitBrowser
```

Bash separat:

```bash
bash Tests/Bash/test-neue-bewerbung.sh
```

Die öffentliche CI läuft über [`.github/workflows/tests.yml`](.github/workflows/tests.yml): Windows führt die PowerShell-Suite aus, Ubuntu prüft die Bash-Skripte mit ShellCheck und Regressionstests. Browserfälle bleiben lokal optional, da Runner und Sandboxen keine identische Browserumgebung garantieren.

<details>
<summary><strong>HTML-, PDF- und Browser-Verträge</strong></summary>

Finale HTML-Dateien müssen eigenständig funktionieren:

- CSS liegt direkt im HTML; es gibt keine Skripte oder CDNs.
- Externe oder lokale Ressourcen werden nicht automatisch geladen.
- `@page { size: A4; margin: 0; }` ist gesetzt.
- Jede `.page` misst exakt `210mm × 297mm`.
- `overflow: hidden` ist nur auf der äußeren `.page` zulässig.
- Ein Lebenslauf nutzt bewusst eine oder zwei explizite A4-Seiten.

Der Browserlauf gilt nur als erfolgreich, wenn er rechtzeitig mit Exitcode `0` endet und alle erwarteten Dateien frisch erzeugt. PNGs benötigen gültige Signatur und Abmessungen. PDFs benötigen Header, EOF-Marker, DIN-A4-MediaBox, passende Seitenzahl und eine ATS-lesbare Unicode-Textschicht.

Chrome oder Edge übernimmt den automatischen PDF-Export. Firefox ist für manuelle Druckvorschau und manuellen Export geeignet, aber nicht Teil des verbindlichen CLI-PDF-Exports.

</details>

<details>
<summary><strong>Dateinamen, Ordner- und Slug-Regeln</strong></summary>

Finale HTML- und PDF-Dokumente werden nach Bewerbername benannt:

```text
Lebenslauf - NACHNAME.VORNAME.html
Anschreiben - NACHNAME.VORNAME.html
Lebenslauf - NACHNAME.VORNAME.pdf
Anschreiben - NACHNAME.VORNAME.pdf
```

`NACHNAME.VORNAME` stammt aus `Private/Daten/01_PERSOENLICHE_DATEN.md`. Fehlen Vor- oder Nachname, darf keine finale Datei mit Platzhalter entstehen.

Firmen- und Rollenordner normalisieren Leerzeichen, Umlaute und Sonderzeichen. Beispiel:

```text
Müller & Partner GmbH
→ Mueller-und-Partner-GmbH
```

Die verbindlichen Regeln stehen in `Prompts/10_DATEI_UND_ORDNER_REGELN.md` und sind in beiden Ordnerhelfern gespiegelt.

</details>

<details>
<summary><strong>Erweiterungspunkte</strong></summary>

| Ziel | Zuständige Datei |
| --- | --- |
| Hauptablauf | `Prompts/00_AGENTEN_START_HIER.md` |
| Lebenslauf | `Prompts/03_LEBENSLAUF_REGELN.md` |
| Anschreiben | `Prompts/04_ANSCHREIBEN_REGELN.md` |
| E-Mail | `Prompts/05_EMAIL_NACHRICHT_REGELN.md` |
| Rollen- und Wahrheitslogik | `Prompts/06_ROLLENLOGIK.md`, `Prompts/07_WAHRHEIT_UND_GRENZEN.md` |
| HTML/CSS | `Prompts/08_HTML_CSS_DESIGNREGELN.md` |
| Qualität und Dateiregeln | `Prompts/09_QUALITAETSCHECK.md`, `Prompts/10_DATEI_UND_ORDNER_REGELN.md` |
| technischer Workflow | `Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md` |
| Ordnererstellung | `Tools/Neue-Bewerbung.ps1`, `Tools/neue-bewerbung.sh` |
| Stammdaten und Inhalt | `Tools/Pruefe-Stammdaten.ps1`, `Tools/Pruefe-Bewerbungsinhalt.ps1` |
| Finalisierung | `Tools/Finalisiere-Bewerbung.ps1` |
| statischer Check | `Tools/Pruefe-Bewerbung.ps1` |
| Layout und PDF | `Tools/Layoutcheck-Bewerbung.ps1`, `Tools/Exportiere-PDF.ps1` |
| Regressionstests | `Tests/Run-RegressionTests.ps1`, `Tests/Bash/test-neue-bewerbung.sh` |
| Designreferenzen | `Vorlagen/Designreferenz-Lebenslauf.html`, `Vorlagen/Designreferenz-Anschreiben.html` |

</details>

### Empfohlener Entwickler-Workflow

1. Fachlich zuständige Prompt-, Tool- oder Vorlagendatei ändern.
2. Änderung unter der passenden Version in `CHANGELOG.md` dokumentieren.
3. Mit einer privaten Testbewerbung prüfen.
4. Statischen Check und Regressionstests ausführen.
5. Bei Layout-/Exportänderungen zusätzlich die Browsermatrix ausführen.
6. `git status --short` prüfen und private Dateien ausschließen.

<details>
<summary><strong>PowerShell-Syntaxcheck für alle Tools</strong></summary>

```powershell
$files = Get-ChildItem -LiteralPath "Tools" -Filter "*.ps1" -File

foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    $file.FullName,
    [ref]$tokens,
    [ref]$errors
  ) | Out-Null

  if ($errors.Count -gt 0) {
    $errors
    exit 1
  }
}
```

Für Dateisuche unter PowerShell bevorzugt das Projekt `rg -g "*.html" "MUSTER" "ORDNER"` anstelle von Pfad-Wildcards wie `ORDNER/*.html`.

</details>

---

<p align="center">
  <strong>Bereit für die erste Bewerbung?</strong><br>
  <a href="#schnellstart">Zum Schnellstart</a> · <a href="CHANGELOG.md">Änderungen ansehen</a> · <a href="#hilfe">Hilfe finden</a>
</p>
