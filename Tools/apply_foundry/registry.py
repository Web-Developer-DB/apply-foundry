"""Public subcommand and GNU-option registry."""

from .cli import CommandSpec, OptionSpec


def O(key, kind="string", allowed=(), minimum=None, maximum=None, placeholder="WERT"):
    return OptionSpec(key, kind, tuple(allowed), minimum, maximum, placeholder)


P = lambda key: O(key, "path", placeholder="PFAD")
S = lambda key: O(key, "switch")
E = lambda key, values, placeholder="NAME": O(key, "enum", values, placeholder=placeholder)
I = lambda key, low, high, placeholder: O(key, "int", minimum=low, maximum=high, placeholder=placeholder)


COMMAND_ORDER = (
    "diagnose", "neu", "universal-neu", "universal-status", "universal-finalisieren",
    "status", "checkpoint", "migrieren", "stammdaten", "dialog-pruefen",
    "dialog-uebernehmen", "passfoto", "kontext", "inhalt", "pruefen", "layout",
    "pdf", "ats", "finalisieren", "freigabe", "tokenbericht", "test-baseline", "tests",
)


COMMANDS = {
    "diagnose": CommandSpec("Laufzeit und Plattform read-only prüfen", {
        "--browser": E("browser", ("auto", "chrome", "edge", "chromium", "firefox")),
        "--browser-executable-path": P("browser_executable_path"), "--als-json": S("als_json"),
        "--browser-erforderlich": S("browser_erforderlich"),
    }),
    "neu": CommandSpec("Neuen Bewerbungsauftrag anlegen oder exakt fortsetzen", {
        "--firma": O("firma", placeholder="NAME"), "--rolle": O("rolle", placeholder="NAME"),
        "--dokumentmodus": E("dokumentmodus", ("vollbewerbung", "anschreiben_mit_universalem_lebenslauf", "individuelle_auswahl"), "MODUS"),
        "--umfang": E("umfang", ("A", "B", "C", "D", "E"), "A-E"),
        "--dokumente": O("dokumente", "documents", placeholder="LISTE"),
        "--umfang-quelle": E("umfang_quelle", ("auswahl", "direkter_auftrag", "fortgesetzter_auftrag"), "QUELLE"),
        "--email-allein-bestaetigt": S("email_allein_bestaetigt"),
        "--universal-lebenslauf-path": P("universal_lebenslauf_path"), "--datum": O("datum", placeholder="YYYY-MM-DD"),
        "--stellenbeschreibung-path": P("stellenbeschreibung_path"), "--stammdaten-path": P("stammdaten_path"),
        "--profil-path": P("profil_path"), "--bewerbungen-root": P("bewerbungen_root"), "--fortsetzen": S("fortsetzen"),
    }, ("--firma",)),
    "universal-neu": CommandSpec("Universellen Softwareentwicklungs-Lebenslauf anlegen", {
        "--datum": O("datum", placeholder="YYYY-MM-DD"), "--stammdaten-path": P("stammdaten_path"),
        "--profil-path": P("profil_path"), "--bewerbungen-root": P("bewerbungen_root"), "--fortsetzen": S("fortsetzen"),
    }),
    "universal-status": CommandSpec("Gespeicherten Stand des universellen Lebenslaufs ermitteln", {
        "--arbeitsordner": P("arbeitsordner"), "--bewerbungen-root": P("bewerbungen_root"), "--als-json": S("als_json"),
    }),
    "universal-finalisieren": CommandSpec("Universellen Lebenslauf vorbereiten oder lokal aktivieren", {
        "--arbeitsordner": P("arbeitsordner"), "--browser": E("browser", ("auto", "chrome", "edge", "chromium")),
        "--browser-executable-path": P("browser_executable_path"), "--stammdaten-path": P("stammdaten_path"),
        "--profil-path": P("profil_path"), "--veroeffentlichen": S("veroeffentlichen"),
        "--visuell-geprueft": S("visuell_geprueft"), "--visuelle-freigabe-notiz": O("visuelle_freigabe_notiz", placeholder="TEXT"),
        "--ersetzen": S("ersetzen"), "--timeout-seconds": I("timeout_seconds", 1, 600, "SEKUNDEN"),
    }, ("--arbeitsordner",)),
    "status": CommandSpec("Gespeicherten Bewerbungsstand ermitteln", {"--arbeitsordner": P("arbeitsordner"), "--als-json": S("als_json")}),
    "checkpoint": CommandSpec("Kompakten, hashgebundenen Workflow-Checkpoint aktualisieren", {
        "--arbeitsordner": P("arbeitsordner"),
        "--schritt": E("schritt", ("auftrag_angelegt", "profilabgleich_abgeschlossen", "analyse_abgeschlossen", "dokumente_abgeschlossen", "fachpruefung_abgeschlossen", "technische_vorbereitung_abgeschlossen", "sichtpruefung_bestaetigt", "veroeffentlicht")),
        "--als-json": S("als_json"),
    }, ("--arbeitsordner", "--schritt")),
    "migrieren": CommandSpec("Matrix und Evidenzindex versioniert migrieren", {
        "--arbeitsordner": P("arbeitsordner"), "--als-json": S("als_json"), "--anwenden": S("anwenden"), "--bericht-path": P("bericht_path"),
    }, ("--arbeitsordner",)),
    "stammdaten": CommandSpec("Stammdaten prüfen", {
        "--stammdaten-path": P("stammdaten_path"), "--warnungen-als-fehler": S("warnungen_als_fehler"),
        "--ungeklaerte-logistik-als-fehler": S("ungeklaerte_logistik_als_fehler"),
        "--bewerbungsauftrag-path": P("bewerbungsauftrag_path"), "--bericht-path": P("bericht_path"),
    }),
    "dialog-pruefen": CommandSpec("Dialogstatus eines Auftrags prüfen", {
        "--auftrag-path": P("auftrag_path"), "--stammdaten-path": P("stammdaten_path"), "--profil-path": P("profil_path"),
        "--fuer-dokumenterstellung": S("fuer_dokumenterstellung"),
    }, ("--auftrag-path",)),
    "dialog-uebernehmen": CommandSpec("Bestätigte Dialogangabe kontrolliert übernehmen", {
        "--auftrag-path": P("auftrag_path"), "--angabe-id": O("angabe_id", placeholder="ID"),
        "--speicherentscheidung": E("speicherentscheidung", ("nur_auftrag", "dauerhaft"), "ENTSCHEIDUNG"),
        "--profil-path": P("profil_path"), "--abschnitt": O("abschnitt", placeholder="NAME"),
        "--formulierung": O("formulierung", placeholder="TEXT"), "--erwarteter-datei-hash": O("erwarteter_datei_hash", placeholder="SHA256"),
        "--zustimmung-bestaetigt": S("zustimmung_bestaetigt"),
    }, ("--auftrag-path", "--angabe-id", "--speicherentscheidung")),
    "passfoto": CommandSpec("Optionales Passfoto in individuellen Lebenslauf einbetten", {"--arbeitsordner": P("arbeitsordner")}, ("--arbeitsordner",)),
    "kontext": CommandSpec("Hashgebundenen Kontextplan für eine Schema-5-Bewerbung erzeugen", {
        "--arbeitsordner": P("arbeitsordner"), "--profil-path": P("profil_path"), "--bericht-path": P("bericht_path"),
    }, ("--arbeitsordner",)),
    "inhalt": CommandSpec("Kandidateninhalte fachlich prüfen", {
        "--ordner": P("ordner"), "--stammdaten-path": P("stammdaten_path"), "--profil-path": P("profil_path"),
        "--auftrag-path": P("auftrag_path"), "--anforderungsmatrix-path": P("anforderungsmatrix_path"),
        "--warnungen-als-fehler": S("warnungen_als_fehler"), "--bericht-path": P("bericht_path"),
    }, ("--ordner", "--auftrag-path", "--anforderungsmatrix-path")),
    "pruefen": CommandSpec("Kandidatenstruktur statisch prüfen", {
        "--ordner": P("ordner"), "--auftrag-path": P("auftrag_path"), "--warnungen-als-fehler": S("warnungen_als_fehler"),
    }, ("--ordner",)),
    "layout": CommandSpec("HTML-Layout prüfen und Seitenscreenshots erzeugen", {
        "--ordner": P("ordner"), "--browser": E("browser", ("auto", "chrome", "edge", "chromium", "firefox")),
        "--browser-executable-path": P("browser_executable_path"), "--nur-vorbereiten": S("nur_vorbereiten"), "--pdf": S("pdf"),
        "--erlaube-firefox-fallback": S("erlaube_firefox_fallback"), "--width": I("width", 320, 10000, "PIXEL"),
        "--height": I("height", 320, 10000, "PIXEL"), "--timeout-seconds": I("timeout_seconds", 1, 600, "SEKUNDEN"),
        "--output-root": P("output_root"), "--bericht-path": P("bericht_path"),
        "--dichtepruefung-deaktivieren": S("dichtepruefung_deaktivieren"),
    }, ("--ordner",)),
    "pdf": CommandSpec("Geprüfte HTML-Dateien als PDF exportieren", {
        "--ordner": P("ordner"), "--auftrag-path": P("auftrag_path"), "--browser": E("browser", ("auto", "chrome", "edge", "chromium")),
        "--browser-executable-path": P("browser_executable_path"), "--mit-layoutcheck": S("mit_layoutcheck"),
        "--nicht-ueberschreiben": S("nicht_ueberschreiben"), "--min-pdf-bytes": I("min_pdf_bytes", 100, 100000000, "BYTES"),
        "--timeout-seconds": I("timeout_seconds", 1, 600, "SEKUNDEN"), "--output-root": P("output_root"), "--bericht-path": P("bericht_path"),
    }, ("--ordner",)),
    "ats": CommandSpec("PDF-Textschicht und ATS-Abdeckung prüfen", {
        "--ordner": P("ordner"), "--stammdaten-path": P("stammdaten_path"), "--auftrag-path": P("auftrag_path"),
        "--min-textabdeckung-prozent": I("min_textabdeckung_prozent", 40, 100, "PROZENT"), "--bericht-path": P("bericht_path"),
        "--pdf-export-bericht-path": P("pdf_export_bericht_path"),
    }, ("--ordner", "--auftrag-path")),
    "finalisieren": CommandSpec("Technische Vorbereitung oder lokale Veröffentlichung ausführen", {
        "--arbeitsordner": P("arbeitsordner"), "--browser": E("browser", ("auto", "chrome", "edge", "chromium")),
        "--browser-executable-path": P("browser_executable_path"), "--stammdaten-path": P("stammdaten_path"), "--profil-path": P("profil_path"),
        "--veroeffentlichen": S("veroeffentlichen"), "--visuell-geprueft": S("visuell_geprueft"),
        "--visuelle-freigabe-notiz": O("visuelle_freigabe_notiz", placeholder="TEXT"), "--ersetzen": S("ersetzen"),
        "--neu-pruefen": S("neu_pruefen"), "--timeout-seconds": I("timeout_seconds", 1, 600, "SEKUNDEN"),
    }, ("--arbeitsordner",)),
    "freigabe": CommandSpec("Chat-bestätigte Sichtfreigabe an den aktuellen Artefaktsatz binden", {
        "--arbeitsordner": P("arbeitsordner"), "--freigabe-id": O("freigabe_id", placeholder="ID"),
        "--bestaetigt": S("bestaetigt"), "--notiz": O("notiz", placeholder="TEXT"),
    }, ("--arbeitsordner", "--freigabe-id", "--bestaetigt")),
    "tokenbericht": CommandSpec("Gemessene Nutzungsdaten in den privaten Bericht übernehmen", {
        "--arbeitsordner": P("arbeitsordner"), "--messbereich": E("messbereich", ("lebenslauf", "gesamte_bewerbung", "technische_vorbereitung")),
        "--messumfang": E("messumfang", ("abschnitt", "gesamte_agentensitzung")), "--nutzungsdaten-verfuegbar": S("nutzungsdaten_verfuegbar"),
        "--anbieter": O("anbieter", placeholder="NAME"), "--modell": O("modell", placeholder="NAME"), "--vorgangs-id": O("vorgangs_id", placeholder="ID"),
        "--messquelle": O("messquelle", placeholder="NAME"), "--beginn": O("beginn", "datetime", placeholder="ZEITPUNKT"),
        "--ende": O("ende", "datetime", placeholder="ZEITPUNKT"),
        "--eingabe-tokens": O("eingabe_tokens", "long", minimum=0, maximum=9223372036854775807, placeholder="ANZAHL"),
        "--ausgabe-tokens": O("ausgabe_tokens", "long", minimum=0, maximum=9223372036854775807, placeholder="ANZAHL"),
        "--cache-lese-tokens": O("cache_lese_tokens", "long", minimum=0, maximum=9223372036854775807, placeholder="ANZAHL"),
        "--cache-schreib-tokens": O("cache_schreib_tokens", "long", minimum=0, maximum=9223372036854775807, placeholder="ANZAHL"),
        "--reasoning-tokens": O("reasoning_tokens", "long", minimum=0, maximum=9223372036854775807, placeholder="ANZAHL"),
        "--gesamt-tokens": O("gesamt_tokens", "long", minimum=0, maximum=9223372036854775807, placeholder="ANZAHL"),
    }, ("--arbeitsordner", "--messbereich")),
    "test-baseline": CommandSpec("Aus drei erfolgreichen Testberichten eine Laufzeitbaseline bilden", {
        "--bericht-path": O("bericht_path", "path_list", placeholder="PFAD[,PFAD,PFAD]"), "--baseline-path": P("baseline_path"),
    }, ("--bericht-path",)),
    "tests": CommandSpec("Projektweite synthetische Regressionstests ausführen", {
        "--mit-browser": S("mit_browser"), "--suite": E("suite", ("schnell", "vollstaendig", "browser", "prompt-pr", "prompt-vollstaendig")),
        "--bericht-path": P("bericht_path"), "--test-name-pattern": O("test_name_pattern", placeholder="REGEX"),
    }),
}


__all__ = ["COMMAND_ORDER", "COMMANDS"]
