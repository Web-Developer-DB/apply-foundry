# Anschreiben-Regeln

## Ziel

Das Anschreiben verbindet Stellenanforderungen, Bewerberprofil und Motivation glaubwürdig. Es soll individuell wirken, aber nicht übertrieben werblich.

## Aufbau

1. Betreff mit Zielrolle
2. Direkter Einstieg mit Bezug zur Stelle
3. Die stärksten zwei bis vier konkreten Passungen aus Profil und Erfahrung
4. Konkreter Nutzen dieser Belege für Aufgaben oder Arbeitsweise des Unternehmens
5. Stellenart immer; Eintritt und Gehaltswunsch nach Bewerbungsauftrag und Stellenanzeige
6. Abschluss mit Gesprächsbereitschaft

## Verbindlicher Quellen-zu-Anschreiben-Abgleich

Ist ein Lebenslauf ausgewählt, wird der individuelle Kandidat vor dem Anschreiben erstellt beziehungsweise der unverändert übernommene universelle Lebenslauf vollständig geprüft. Ist kein Lebenslauf ausgewählt, gleicht der Agent das Anschreiben unmittelbar gegen private Profildaten, normalisierte Dialogangaben, Anforderungsmatrix und Stellenbeschreibung ab. Erst danach schreibt er den ersten Anschreibenentwurf.

Prüfe die folgenden Bereiche nur soweit sie für die konkrete Stelle und den bestätigten Dokumentumfang relevant sind:

- Schulbildung
- Berufsausbildung, Studium oder Umschulung
- Weiterbildungen und Zertifikate
- Berufserfahrung
- technische Kenntnisse
- KI- und Softwarekenntnisse
- Projekte und sonstige Praxisbelege
- Soft Skills und Arbeitsweise
- besondere Stärken und Motivation

Für jeden relevanten Bereich wird in `Analyse.md` eine kompakte Inhaltsentscheidung dokumentiert. Verweise bevorzugt auf die zugehörigen IDs aus `Anforderungsmatrix.json`, statt Anforderung, Beleg und Bewertung erneut auszuschreiben. Nicht relevante Bereiche dürfen gesammelt als geprüft und ohne Stellenbezug verworfen werden; neun künstliche Einzelzeilen sind nicht erforderlich.

- `Anschreiben`: Der Bereich liefert einen starken, rollenrelevanten Beleg oder erklärt die Motivation und wird im Anschreiben aufgegriffen.
- `nur Lebenslauf`: Der Bereich ist für die Bewerbung relevant, aber in einem ausgewählten Lebenslauf ausreichend sichtbar oder würde das Anschreiben unnötig wiederholen. Ohne ausgewählten Lebenslauf ist diese Entscheidung unzulässig.
- `weggelassen mit Begründung`: Der Bereich ist für die konkrete Rolle nicht relevant, schwächt die Positionierung oder muss aus Platz- beziehungsweise Fokusgründen entfallen. Die Begründung muss konkret sein.
- `keine belegte Angabe`: Zu diesem Bereich liegt keine belastbare Information vor; es darf nichts ergänzt oder erfunden werden.

Pflichtregeln:

- Keine für die Bewerbung relevante Information darf ohne begründete Inhaltsentscheidung entfallen. Eine Begründung in der verknüpften Matrixzeile genügt und wird nicht in mehreren Dateien dupliziert.
- Nicht jeder relevante Bereich gehört automatisch in das Anschreiben. Das Anschreiben hebt die stärksten zwei bis vier Passungen hervor; weitere relevante Angaben bleiben bewusst und nachvollziehbar ausschließlich im Lebenslauf.
- Lebenslauf und Anschreiben ergänzen sich: Der Lebenslauf liefert die scanbaren Fakten und Anwendungskontexte; das Anschreiben verbindet zwei bis vier davon mit den konkreten Aufgaben, Problemen oder Erwartungen der Stelle. Es kopiert weder Bulletpoints noch Tool-Listen.
- Formale Chronologie gehört grundsätzlich in den Lebenslauf. Schulbildung, ältere Stationen oder Abschlüsse werden im Anschreiben nur erwähnt, wenn sie für Motivation, Quereinstieg oder eine formale Stellenanforderung einen konkreten Erklärungswert besitzen.
- Soft Skills werden im Anschreiben bevorzugt durch ein konkretes Beispiel aus Berufserfahrung, Weiterbildung oder Projektpraxis gezeigt, nicht als bloße Eigenschaftsliste.
- Besondere Stärken und Motivation müssen mit der Zielrolle verbunden werden. Allgemeine Aussagen ohne Beleg oder konkreten Bezug reichen nicht.
- Widersprüche oder relevante Lücken zwischen den ausgewählten Quellen und dem Anschreiben werden vor der Finalisierung korrigiert oder in `Offene_Fragen.md` dokumentiert.
- Bei unverändertem universellem Lebenslauf werden Lücken nicht durch Änderungen an diesem Snapshot behoben. Belegte, wichtige Passungen werden im Anschreiben erklärt; reicht dies nicht, wird ein individueller Lebenslauf empfohlen, ohne den Umfang stillschweigend zu wechseln.

## Stil

- Maximal eine A4-Seite.
- Natürliches Deutsch, keine gestelzten Phrasen.
- Keine erfundenen Unternehmensdetails.
- Keine Übertreibungen wie „perfekt“, wenn die Daten das nicht tragen.
- Einen ausgewählten Lebenslauf nicht wiederholen, sondern die Passung erklären.
- Die im Quellenabgleich als `Anschreiben` markierten Bereiche gezielt aufgreifen und vorhandene `nur Lebenslauf`-Inhalte nicht unnötig wiederholen.
- Visuell ruhig und passend zum Lebenslauf, aber ohne dekorative Karten- oder Marketingoptik.
- Für den verbindlich unterstützten Chrome-/Edge-Export druckstabil als eine feste A4-Seite anlegen, nicht als wachsendes Dokument mit zufälligem Umbruch.

## Inhaltliche Regeln

- Nutze echte Belege aus `Private/Daten/`.
- Nenne die gewünschte oder passende Stellenart im Anschreiben immer: `Vollzeit`, `Teilzeit` oder `Vollzeit/Teilzeit`. Bei Teilzeit darf der gewünschte Stundenumfang genannt werden, wenn der Bewerbungsauftrag ihn enthält.
- Wenn Bewerbungsauftrag und Stellenanzeige bei der Stellenart nicht zusammenpassen, erfinde keine Passung. Dokumentiere den Widerspruch in `Offene_Fragen.md` und formuliere nur wahr.
- Nenne den Gehaltswunsch im Anschreiben, wenn `wunschgehaltVerwenden` im Bewerbungsauftrag auf `ja` steht oder wenn die Stellenanzeige ausdrücklich eine Gehaltsvorstellung verlangt und der Bewerbungsauftrag dies nicht ausschließt.
- Wenn `Wunschgehalt verwenden` auf `nur wenn in der Stellenanzeige verlangt` steht, nenne das Gehalt nur bei ausdrücklicher Aufforderung in der Anzeige.
- Wenn ein manueller Gehaltswunsch im Bewerbungsauftrag steht, verwende diese Angabe.
- Wenn automatische Schätzung im Bewerbungsauftrag ausdrücklich aktiviert ist, ermittle eine plausible Gehaltsangabe oder Gehaltsspanne aus einer aktuellen, nachvollziehbaren Quelle sowie Zielrolle, Seniorität, einschlägiger Berufserfahrung, Region, Arbeitsmodell und Stellenart. Alter, Geschlecht und andere geschützte persönliche Merkmale dürfen die Schätzung nicht beeinflussen. Dokumentiere Quelle, Stand und Kurzbegründung in `Analyse.md`.
- Formuliere Gehalt sachlich, z. B. `Meine Gehaltsvorstellung liegt bei ... EUR brutto jährlich.` oder bei Teilzeit/Stundenlohn passend zum im Bewerbungsauftrag gewählten Gehaltsmodell.
- Wenn die Datengrundlage für eine seriöse Gehaltsschätzung fehlt oder keine aktuelle Quelle geprüft werden kann, nicht raten. In `Offene_Fragen.md` dokumentieren und im Anschreiben neutral bleiben, sofern die Anzeige keinen Gehaltswunsch zwingend verlangt.
- Sprich Lücken oder Grenzen nicht defensiv an, sondern fokussiere passende Stärken.
- Nicht oder nur teilweise belegte Anforderungen werden vorrangig in `Analyse.md`, `Anforderungsmatrix.json`, `Qualitaetscheck.md` oder `Offene_Fragen.md` dokumentiert. Im Anschreiben erscheinen sie nur, wenn eine Nichterwähnung irreführend wäre.
- Vermeide Metaformulierungen wie `nicht belegt`, `noch keine Erfahrung`, `ich erfülle ... nicht` oder `ohne daraus Berufserfahrung abzuleiten`. Formuliere stattdessen positiv auf der belegten Erfahrungsebene.
- Bei Quereinstieg oder Entwicklungsrollen die Brücke zwischen vorhandener Erfahrung und Zielrolle konkret erklären.
- Eine Transferbrücke nennt die fehlende Zieltechnologie nur dann, wenn eine belegte verwandte Grundlage existiert. Sie beschreibt diese Grundlage und eine realistische Einarbeitung, ohne Direktpraxis zu suggerieren.
- Verlangte und belegte Technologien nicht nur nennen, sondern anhand eines konkreten Einsatzes oder eigenen Beitrags verständlich machen.
- Wenn Ansprechpartner fehlt, neutrale Anrede verwenden.
- Wenn Firmenadresse fehlt, kein Fantasie-Adressenblock.

## Finale Datei

Dateiname:

`Anschreiben - NACHNAME.VORNAME.html`

Finale Anschreiben dürfen keine Platzhalter, Warnhinweise oder Entwurfsmarker enthalten. Der Dateiname nutzt den Bewerbernamen aus den privaten Daten, damit E-Mail-Anhänge für Recruiter schnell zuordenbar sind.
