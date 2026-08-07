# Prompts

Dieser Ordner enthält die öffentlichen Regeln des Bewerbungsagenten.

Startpunkt ist `00_AGENTEN_START_HIER.md`. `01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md` ist die einzige zentrale Quelle für den interaktiven Umfang A–E, den sparsamen Profilabgleich, auftragsbezogene Angaben und ausdrücklich bestätigte Profilaktualisierungen. Anschließend folgen nur für die ausgewählten Bestandteile die spezialisierten Regeln für Matrix, Lebenslauf, Anschreiben, E-Mail, Rollenlogik, Wahrheit, Design, Qualitätsprüfung und Ablage. Der normalisierte Dialogzustand liegt im privaten Schema-4-`Bewerbungsauftrag.json`, sodass jeder Agent ohne Chatverlauf fortsetzen kann.

Private Bewerberdaten stehen nicht in diesem Ordner. Sie gehören lokal nach `Private/Daten/`.

Repository-kompatible Coding-Agenten erhalten die übergreifenden Routing- und Sicherheitsregeln aus der zentralen `AGENTS.md`. OpenCode nutzt diese Datei direkt; die Root-`opencode.json` deaktiviert nur die Sitzungsfreigabe und dupliziert weder Prompts noch Provider- oder Modellwahl. `CLAUDE.md` und `GEMINI.md` sind minimale Importadapter und enthalten keine eigene Dialogvariante. Ollama stellt bei Bedarf ein Modell für OpenCode bereit und ist selbst kein ausführender Agent. Der private, nicht blockierende Nutzungsbericht `Tokenverbrauch.json` wird über `Tools/Aktualisiere-Tokenbericht.ps1` nur mit exakt bereitgestellten Laufzeitwerten aktualisiert. Fähigkeiten und ein bestehender Arbeitsstand werden anbieterunabhängig geprüft; die vollständigen fachlichen Regeln bleiben ausschließlich in `00_AGENTEN_START_HIER.md` und den bedarfsgerecht geladenen Modulen dieses Ordners.

Wichtiger Standard:

- Lebensläufe sollen wie ruhige deutsche tabellarische CVs wirken, nicht wie Portfolio-Seiten oder Skill-Dashboards.
- Finale HTML-Dokumente müssen für den verbindlichen Chrome-/Edge-Export geeignet sein. Ein Einseiten-Dokument darf bei 100 Prozent Skalierung nicht automatisch auf zwei Seiten umbrechen.
