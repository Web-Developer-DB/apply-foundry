# Prompts

Dieser Ordner enthält die öffentlichen Regeln des Bewerbungsagenten.

Startpunkt ist `00_AGENTEN_START_HIER.md`. Danach legt `01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md` fest, ob eine vollständige stellenbezogene Bewerbung oder nur ein neues Anschreiben mit unverändertem universellem Lebenslauf entsteht. Anschließend folgen die spezialisierten Regeln für Matrix, Lebenslauf, Anschreiben, E-Mail, Rollenlogik, Wahrheit, Design, Qualitätsprüfung und Ablage.

Private Bewerberdaten stehen nicht in diesem Ordner. Sie gehören lokal nach `Private/Daten/`.

Repository-kompatible Coding-Agenten erhalten die übergreifenden Routing- und Sicherheitsregeln aus der zentralen `AGENTS.md`. OpenCode nutzt diese Datei direkt; `CLAUDE.md` und `GEMINI.md` sind minimale Importadapter. Ollama stellt bei Bedarf ein Modell für OpenCode bereit und ist selbst kein ausführender Agent. Der private, nicht blockierende Nutzungsbericht `Tokenverbrauch.json` wird über `Tools/Aktualisiere-Tokenbericht.ps1` nur mit exakt bereitgestellten Laufzeitwerten aktualisiert. Fähigkeiten und ein bestehender Arbeitsstand werden anbieterunabhängig geprüft; die vollständigen fachlichen Regeln bleiben ausschließlich in `00_AGENTEN_START_HIER.md` und den bedarfsgerecht geladenen Modulen dieses Ordners.

Wichtiger Standard:

- Lebensläufe sollen wie ruhige deutsche tabellarische CVs wirken, nicht wie Portfolio-Seiten oder Skill-Dashboards.
- Finale HTML-Dokumente müssen für den Druck geeignet sein. Ein Einseiten-Dokument darf in Firefox bei 100 Prozent Skalierung nicht automatisch auf zwei Seiten umbrechen.
