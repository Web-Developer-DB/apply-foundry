# Prompts

Dieser Ordner enthält die öffentlichen Regeln des Bewerbungsagenten.

Startpunkt ist `00_AGENTEN_START_HIER.md`. `01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md` ist die einzige zentrale Quelle für den interaktiven Umfang A–E, den sparsamen Profilabgleich, auftragsbezogene Angaben und ausdrücklich bestätigte Profilaktualisierungen. Anschließend folgen nur für die ausgewählten Bestandteile die spezialisierten Regeln für Matrix, Lebenslauf, Anschreiben, E-Mail, Rollenlogik, Wahrheit, Design, Qualitätsprüfung und Ablage. Der normalisierte Dialogzustand liegt im privaten Schema-5-`Bewerbungsauftrag.json`, sodass jeder Agent ohne Chatverlauf fortsetzen kann; Matrix-Schema 5 ist aktuell, Schemata 1 bis 4 bleiben als Legacy lesbar.

Private Bewerberdaten stehen nicht in diesem Ordner. Sie gehören lokal nach `Private/Daten/`.

Aktuelle technische Leitplanken:

- `08_HTML_CSS_DESIGNREGELN.md` verlangt A4-Seiten mit `210mm × 297mm`; Vorschauabstände, Schatten und Seitenhintergründe stehen ausschließlich in `@media screen`. Ein Selektor wie `.page + .page` wird im Druckmodus ausdrücklich auf `margin-top: 0` zurückgesetzt.
- Der Layoutcheck arbeitet zweistufig: isolierte PNG-/DOM-Prüfung jeder expliziten `.page` und vollständige Druckvorprüfung des Original-HTMLs. Die Druckseitenzahl muss exakt der Zahl der `.page`-Container entsprechen; der Bericht verwendet Schema 3.
- `11_TECHNISCHER_CHECK_WORKFLOW.md` beschreibt den privaten `Pruefstand.json`-Cache in Schema 2 mit den Stufenstatus `running`, `passed` und `failed`. Fehlgeschlagene oder unterbrochene Stufen werden nicht aus dem Cache wiederverwendet; der Status stellt den letzten Versuch über `technicalAttempt` dar.
- Der Finalisierungsbericht individueller Bewerbungen verwendet Schema 8. Relative Einzelpfade und Pfadlisten werden vom Dispatcher gegen das ursprüngliche Aufrufverzeichnis normalisiert; direkte Fachwerkzeuge prüfen ihre Pfade zusätzlich selbst. Zweiseitige Lebensläufe mit unzulässiger freier Fläche erhalten keine Freigabe-ID, solange keine begründete Dichteausnahme vorliegt.

Repository-kompatible Coding-Agenten erhalten die übergreifenden Routing- und Sicherheitsregeln aus der zentralen `AGENTS.md`. OpenCode nutzt diese Datei direkt; die Root-`opencode.json` deaktiviert nur die Sitzungsfreigabe und dupliziert weder Prompts noch Provider- oder Modellwahl. `CLAUDE.md` und `GEMINI.md` sind minimale Importadapter und enthalten keine eigene Dialogvariante. Ollama stellt bei Bedarf ein Modell für OpenCode bereit und ist selbst kein ausführender Agent. Der private, nicht blockierende Nutzungsbericht `Tokenverbrauch.json` wird über `python3 Tools/bewerbung.py tokenbericht` nur mit exakt bereitgestellten Laufzeitwerten aktualisiert. Fähigkeiten und ein bestehender Arbeitsstand werden anbieterunabhängig geprüft; die vollständigen fachlichen Regeln bleiben ausschließlich in `00_AGENTEN_START_HIER.md` und den bedarfsgerecht geladenen Modulen dieses Ordners.

Alle technischen Beispiele verwenden den gemeinsamen Python-3.11+-Dispatcher. Vor Start, Reparatur oder Test läuft `python3 Tools/setup.py --all --dry-run --format json`; Details zu Windows/winget, Linux-Paketmanagern und macOS/Homebrew stehen in Prompt 11.

Wichtiger Standard:

- Lebensläufe sollen wie ruhige deutsche tabellarische CVs wirken, nicht wie Portfolio-Seiten oder Skill-Dashboards.
- Finale HTML-Dokumente müssen für den verbindlichen Chrome-/Edge-/Chromium-Export geeignet sein. Ein Einseiten-Dokument darf bei 100 Prozent Skalierung nicht automatisch auf zwei Seiten umbrechen.
