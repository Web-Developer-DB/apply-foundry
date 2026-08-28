#!/usr/bin/env python3
"""Synthetic contracts for the PowerShell-independent Linux core."""

import base64
import io
import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in os.sys.path:
    os.sys.path.insert(0, str(REPO_ROOT))

from Tools.apply_foundry import load_handlers  # noqa: E402
from Tools.apply_foundry.cli import CommandContext, parse, run  # noqa: E402
from Tools.apply_foundry.commands_core import (  # noqa: E402
    _static_html_errors,
    handle_checkpoint,
    handle_dialog_pruefen,
    handle_dialog_uebernehmen,
    handle_freigabe,
    handle_migrieren,
    handle_neu,
    handle_passfoto,
    handle_pruefen,
    handle_stammdaten,
    handle_status,
    handle_test_baseline,
    handle_tokenbericht,
    handle_universal_neu,
    validate_dialog_order,
)
from Tools.apply_foundry.contracts import (  # noqa: E402
    artifact_set_hash,
    assert_artifacts_current,
    document_scope,
    scope_from_cli,
)
from Tools.apply_foundry.errors import CliUsageError, ContractError, UnsafePathError  # noqa: E402
from Tools.apply_foundry.io import artifact_record, read_json, sha256_file, write_atomic_json, write_atomic_text  # noqa: E402
from Tools.apply_foundry.paths import resolve_order_paths, safe_path, slug, validate_portable_relative  # noqa: E402
from Tools.apply_foundry.registry import COMMANDS  # noqa: E402
from Tools.apply_foundry import runtime  # noqa: E402


MASTER = """# Persönliche Daten

- Vollständiger Name: Test Person
- Vorname: Test
- Nachname: Person
- Dateiname-Name: Person.Test
- Adresse: Testweg 1, 12345 Teststadt
- Telefon: +49 123 456789
- E-Mail: test.person@example.invalid
- Verfügbarkeit: ab sofort
- Gewünschte Stellenart: Vollzeit
- Gewünschtes Arbeitsmodell: hybrid
- Wunschgehalt verwenden: nein
- Gehaltslogik: keine Angabe
"""

PROFILE = """# Bewerberprofil

## Kurzprofil

Synthetisches Softwareentwicklungsprofil für lokale Vertragstests.

## Kenntnisse

- Python
- Webentwicklung

## Berufserfahrung

01/2020 - 12/2024 · Testentwicklung
"""


class SyntheticProject:
    def __init__(self, root: Path):
        self.root = root
        self.private = root / "Private"
        self.data = self.private / "Daten"
        self.applications = self.private / "Bewerbungen"
        self.master = self.data / "01_PERSOENLICHE_DATEN.md"
        self.profile = self.data / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
        self.data.mkdir(parents=True)
        self.master.write_text(MASTER, encoding="utf-8")
        self.profile.write_text(PROFILE, encoding="utf-8")
        self.stdout = io.StringIO()
        self.stderr = io.StringIO()
        self.context = CommandContext(root, root, self.stdout, self.stderr)

    def reset_output(self):
        self.stdout.seek(0)
        self.stdout.truncate()
        self.stderr.seek(0)
        self.stderr.truncate()

    def create_application(self, scope="A"):
        args = {
            "firma": "Beispiel GmbH", "rolle": "Fullstack Developer", "umfang": scope,
            "datum": "2026-08-23", "bewerbungen_root": self.applications,
            "stammdaten_path": self.master, "profil_path": self.profile,
        }
        self.assert_code(handle_neu(self.context, args))
        work = self.applications / "Beispiel-GmbH/_Arbeitsdateien/2026-08-23--Fullstack-Developer"
        return work, args

    @staticmethod
    def assert_code(code):
        if code != 0:
            raise AssertionError("synthetic command returned %s" % code)


class CliAndPathTests(unittest.TestCase):
    def test_dispatcher_registers_every_browser_free_command(self):
        handlers = load_handlers()
        expected = {
            "diagnose", "neu", "universal-neu", "universal-status", "status", "checkpoint",
            "migrieren", "stammdaten", "dialog-pruefen", "dialog-uebernehmen", "passfoto",
            "kontext", "inhalt", "pruefen", "freigabe", "tokenbericht", "test-baseline", "tests",
        }
        self.assertTrue(expected.issubset(handlers))

    def test_cli_uses_snake_case_and_resolves_relative_paths_at_invocation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            values = parse(
                "diagnose", ["--browser=ChRoMiUm", "--browser-executable-path", "bin/browser", "--als-json"],
                COMMANDS["diagnose"], root,
            )
        self.assertEqual("chromium", values["browser"])
        self.assertEqual(root / "bin/browser", values["browser_executable_path"])
        self.assertIs(True, values["als_json"])

    def test_cli_rejects_duplicate_unknown_and_positional_options_with_exit_two(self):
        context = CommandContext(REPO_ROOT, REPO_ROOT, io.StringIO(), io.StringIO())
        self.assertEqual(2, run(["diagnose", "--browser", "auto", "--browser", "auto"], context=context))
        self.assertEqual(2, run(["diagnose", "--unbekannt"], context=context))
        self.assertEqual(2, run(["diagnose", "positional"], context=context))

    def test_portable_paths_and_slugs_reject_traversal_and_reserved_names(self):
        self.assertEqual("Mueller-und-Soehne", slug("Müller & Söhne"))
        for value in ("../secret", "a\\b", "CON", "a//b", "/absolute"):
            with self.subTest(value=value), self.assertRaises(ContractError):
                validate_portable_relative(value)

    def test_order_path_contract_rejects_boolean_schema_and_relative_legacy_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            applications = Path(temp) / "Private/Bewerbungen"
            applications.mkdir(parents=True)
            with self.assertRaises(ContractError):
                resolve_order_paths({"schemaVersion": True}, applications)
            with self.assertRaises(ContractError):
                resolve_order_paths({
                    "schemaVersion": 4, "zielOrdner": "Firma/Ziel",
                    "arbeitsOrdner": "Firma/_Arbeitsdateien/Auftrag",
                    "kandidatOrdner": "Firma/_Arbeitsdateien/Auftrag/Kandidat",
                }, applications)

    def test_safe_path_rejects_symbolic_link_components(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "root"
            outside = Path(temp) / "outside"
            root.mkdir()
            outside.mkdir()
            try:
                (root / "linked").symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError):
                self.skipTest("symbolic links are unavailable")
            with self.assertRaises(UnsafePathError):
                safe_path(root / "linked/file.json", root)

    def test_atomic_json_and_artifact_hashes_are_deterministic_and_detect_tampering(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            first, second = root / "eins.json", root / "zwei.txt"
            write_atomic_json(first, {"text": "Grüße", "value": 1})
            write_atomic_text(second, "zwei")
            self.assertEqual("Grüße", read_json(first)["text"])
            records = [artifact_record(first, root), artifact_record(second, root)]
            self.assertEqual(artifact_set_hash(records), artifact_set_hash(list(reversed(records))))
            assert_artifacts_current(records, root)
            second.write_text("verändert", encoding="utf-8")
            with self.assertRaises(ContractError):
                assert_artifacts_current(records, root)


class ScopeContractTests(unittest.TestCase):
    def test_all_scope_choices_and_email_only_gate(self):
        self.assertEqual("individuell", scope_from_cli({"umfang": "A"})["lebenslauf"])
        self.assertEqual("universal_unveraendert", scope_from_cli({"umfang": "B"})["lebenslauf"])
        self.assertFalse(scope_from_cli({"umfang": "C"})["anschreiben"])
        self.assertEqual("nicht_enthalten", scope_from_cli({"umfang": "D"})["lebenslauf"])
        with self.assertRaises(ContractError):
            scope_from_cli({"umfang": "E", "dokumente": ["email_nachricht"]})
        selected = scope_from_cli({"umfang": "E", "dokumente": ["email_nachricht"], "email_allein_bestaetigt": True})
        self.assertTrue(selected["emailNachricht"])

    def test_document_scope_rejects_untyped_json_booleans(self):
        with self.assertRaises(ContractError):
            document_scope({"schemaVersion": 5, "dokumentumfang": {"lebenslauf": "individuell", "anschreiben": 1, "emailNachricht": False}})


class WorkflowCoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="apply-foundry-core-")
        self.addCleanup(self.temporary.cleanup)
        self.project = SyntheticProject(Path(self.temporary.name))

    def test_new_application_is_portable_idempotent_and_checkpointed(self):
        work, args = self.project.create_application()
        order = read_json(work / "Bewerbungsauftrag.json")
        self.assertEqual(5, order["schemaVersion"])
        self.assertEqual("relativ_zu_bewerbungen_root", order["pfadModus"])
        self.assertFalse(Path(order["arbeitsOrdner"]).is_absolute())
        checkpoint = read_json(work / "Workflow-Checkpoint.json")
        self.assertEqual("auftrag_angelegt", checkpoint["lastCompletedStep"])
        self.assertEqual(64, len(checkpoint["artifactSetSha256"]))
        self.assertEqual(0, handle_neu(self.project.context, {**args, "fortsetzen": True}))
        with self.assertRaises(CliUsageError):
            handle_neu(self.project.context, args)

    def test_new_application_rejects_partial_state_and_portable_case_collision(self):
        target = self.project.applications / "Beispiel-GmbH/2026-08-23--Fullstack-Developer"
        target.mkdir(parents=True)
        args = {
            "firma": "Beispiel GmbH", "rolle": "Fullstack Developer", "umfang": "A",
            "datum": "2026-08-23", "bewerbungen_root": self.project.applications,
            "stammdaten_path": self.project.master, "profil_path": self.project.profile,
            "fortsetzen": True,
        }
        with self.assertRaises(CliUsageError):
            handle_neu(self.project.context, args)

        second_root = Path(self.temporary.name) / "case/Private/Bewerbungen"
        second_data = second_root.parent / "Daten"
        second_data.mkdir(parents=True)
        (second_data / self.project.master.name).write_text(MASTER, encoding="utf-8")
        (second_data / self.project.profile.name).write_text(PROFILE, encoding="utf-8")
        second_root.mkdir()
        (second_root / "beispiel-gmbh").mkdir()
        with self.assertRaises(CliUsageError):
            handle_neu(self.project.context, {
                **args, "bewerbungen_root": second_root, "fortsetzen": False,
                "stammdaten_path": second_data / self.project.master.name,
                "profil_path": second_data / self.project.profile.name,
            })

    def test_universal_source_binding_is_relative_hash_bound_and_legacy_readable(self):
        source = self.project.applications / "_Universal-Lebenslauf/Aktiv/Intern/Lebenslauf - Person.Test.html"
        source.parent.mkdir(parents=True)
        source.write_text(
            '<!doctype html><html lang="de"><head><style>@page { size: A4; margin: 0; }'
            '.page { width: 210mm; height: 297mm; }</style></head><body><main class="page">'
            'Vollständig synthetischer universeller Lebenslauf.</main></body></html>',
            encoding="utf-8",
        )
        args = {
            "firma": "Beispiel GmbH", "rolle": "Fullstack Developer", "umfang": "B",
            "datum": "2026-08-23", "bewerbungen_root": self.project.applications,
            "stammdaten_path": self.project.master, "profil_path": self.project.profile,
            "universal_lebenslauf_path": source,
        }
        self.assertEqual(0, handle_neu(self.project.context, args))
        work = self.project.applications / "Beispiel-GmbH/_Arbeitsdateien/2026-08-23--Fullstack-Developer"
        order_path = work / "Bewerbungsauftrag.json"
        order = read_json(order_path)
        binding = order["universalLebenslauf"]
        self.assertEqual("relativ_zu_projekt_root", binding["sourceHtmlPfadModus"])
        self.assertEqual("Private/Bewerbungen/_Universal-Lebenslauf/Aktiv/Intern/Lebenslauf - Person.Test.html", binding["sourceHtmlPath"])
        self.assertEqual(sha256_file(source), binding["sourceHtmlSha256BeiAnlage"])
        self.assertEqual(0, handle_neu(self.project.context, {**args, "fortsetzen": True}))

        # Schema 4 stored an absolute source path; this remains readable during
        # a platform-spanning continuation but is never emitted for new work.
        order["schemaVersion"] = 4
        order["zielOrdner"] = str(self.project.applications / order["zielOrdner"])
        order["arbeitsOrdner"] = str(self.project.applications / order["arbeitsOrdner"])
        order["kandidatOrdner"] = str(self.project.applications / order["kandidatOrdner"])
        order["universalLebenslauf"] = {
            "sourceHtmlPath": str(source),
            "sourceHtmlSha256BeiAnlage": sha256_file(source),
            "kandidatDatei": "Lebenslauf - Person.Test.html",
        }
        write_atomic_json(order_path, order)
        self.assertEqual(0, handle_neu(self.project.context, {**args, "fortsetzen": True}))

        source.write_text(source.read_text(encoding="utf-8") + "\nverändert", encoding="utf-8")
        with self.assertRaises(CliUsageError):
            handle_neu(self.project.context, {**args, "fortsetzen": True})

    def test_status_reconstructs_state_and_marks_changed_checkpoint_stale(self):
        work, _ = self.project.create_application()
        self.project.reset_output()
        self.assertEqual(0, handle_status(self.project.context, {"arbeitsordner": work, "als_json": True}))
        current = json.loads(self.project.stdout.getvalue())
        self.assertTrue(current["workflowCheckpoint"]["valid"])
        (work / "neuer-nachweis.txt").write_text("synthetisch", encoding="utf-8")
        self.project.reset_output()
        handle_status(self.project.context, {"arbeitsordner": work, "als_json": True})
        changed = json.loads(self.project.stdout.getvalue())
        self.assertFalse(changed["workflowCheckpoint"]["valid"])
        self.assertEqual(0, handle_checkpoint(self.project.context, {"arbeitsordner": work, "schritt": "profilabgleich_abgeschlossen"}))

    def test_stammdaten_report_uses_schema_two(self):
        work, _ = self.project.create_application()
        report = work / "Stammdaten-Pruefbericht.json"
        code = handle_stammdaten(self.project.context, {
            "stammdaten_path": self.project.master, "bewerbungsauftrag_path": work / "Bewerbungsauftrag.json",
            "bericht_path": report,
        })
        self.assertEqual(0, code)
        self.assertEqual(2, read_json(report)["schemaVersion"])

    def test_dialog_only_order_update_is_valid_and_idempotent(self):
        work, _ = self.project.create_application()
        order_path = work / "Bewerbungsauftrag.json"
        order = read_json(order_path)
        order["dialog"] = {
            "schemaVersion": 1, "status": "speicherentscheidung_offen", "updatedAtUtc": "2026-08-23T10:00:00Z",
            "rueckfragen": [{
                "id": "frage-speicher-1", "art": "speicherentscheidung", "status": "offen", "frage": "Nur im Auftrag speichern?",
                "runde": 1, "blockiertDokumenterstellung": True, "widerspruch": False, "widerspruchGeklaert": True,
                "angabeIds": ["angabe-1"],
            }],
            "angaben": [{
                "id": "angabe-1", "wert": "Synthetischer Fakt", "wahrheitsstatus": "bestaetigt",
                "widerspruch": False, "widerspruchGeklaert": True, "speicherentscheidung": "ausstehend",
                "profilaktualisierung": {"status": "ausstehend"},
            }],
        }
        write_atomic_json(order_path, order)
        self.assertEqual([], validate_dialog_order(order))
        args = {"auftrag_path": order_path, "angabe_id": "angabe-1", "speicherentscheidung": "nur_auftrag"}
        self.assertEqual(0, handle_dialog_uebernehmen(self.project.context, args))
        self.assertEqual(0, handle_dialog_uebernehmen(self.project.context, args))
        updated = read_json(order_path)
        self.assertEqual("nur_auftrag", updated["dialog"]["angaben"][0]["speicherentscheidung"])
        self.assertEqual("bereit_zur_dokumenterstellung", updated["dialog"]["status"])
        self.assertEqual(0, handle_dialog_pruefen(self.project.context, {"auftrag_path": order_path, "fuer_dokumenterstellung": True}))

    def test_durable_dialog_update_is_hash_bound_and_atomic(self):
        work, _ = self.project.create_application()
        order_path = work / "Bewerbungsauftrag.json"
        order = read_json(order_path)
        formulation = "Nachweisbare synthetische API-Erfahrung."
        before = sha256_file(self.project.profile)
        order["dialog"] = {
            "schemaVersion": 1, "status": "speicherentscheidung_offen", "updatedAtUtc": "2026-08-23T10:00:00Z",
            "rueckfragen": [{
                "id": "frage-speicher-2", "art": "speicherentscheidung", "status": "offen", "frage": "Dauerhaft speichern?",
                "runde": 1, "blockiertDokumenterstellung": True, "widerspruch": False, "widerspruchGeklaert": True,
                "angabeIds": ["angabe-2"],
            }],
            "angaben": [{
                "id": "angabe-2", "wert": formulation, "wahrheitsstatus": "bestaetigt", "widerspruch": False,
                "widerspruchGeklaert": True, "speicherentscheidung": "ausstehend",
                "profilaktualisierung": {
                    "status": "ausstehend", "datei": "Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md",
                    "abschnitt": "Kenntnisse", "vorgeschlageneFormulierung": formulation,
                    "fachlicherZieltyp": "kenntnis", "vorherSha256": before,
                },
            }],
        }
        write_atomic_json(order_path, order)
        code = handle_dialog_uebernehmen(self.project.context, {
            "auftrag_path": order_path, "angabe_id": "angabe-2", "speicherentscheidung": "dauerhaft",
            "profil_path": self.project.profile, "abschnitt": "Kenntnisse", "formulierung": formulation,
            "erwarteter_datei_hash": before, "zustimmung_bestaetigt": True,
        })
        self.assertEqual(0, code)
        self.assertIn(formulation, self.project.profile.read_text(encoding="utf-8"))
        update = read_json(order_path)["dialog"]["angaben"][0]["profilaktualisierung"]
        self.assertEqual(sha256_file(self.project.profile), update["nachherSha256"])

    def test_migration_preview_and_draft_preserve_original(self):
        work, _ = self.project.create_application()
        matrix = {"schemaVersion": 1, "requirements": [{"id": "muss-1", "typ": "muss", "anforderung": "Synthetisch", "status": "unklar"}]}
        matrix_path = work / "Anforderungsmatrix.json"
        write_atomic_json(matrix_path, matrix)
        before = sha256_file(matrix_path)
        report_path = work / "Migrationsbericht.json"
        code = handle_migrieren(self.project.context, {"arbeitsordner": work, "anwenden": True, "bericht_path": report_path})
        self.assertEqual(1, code)
        report = read_json(report_path)
        self.assertEqual(1, report["schemaVersion"])
        self.assertEqual("entwurf_erzeugt", report["status"])
        self.assertEqual(before, sha256_file(matrix_path))
        self.assertTrue((work / "Anforderungsmatrix--MIGRATION-ENTWURF.json").is_file())

    def test_passfoto_is_embedded_byte_exact_and_idempotent(self):
        work, _ = self.project.create_application(scope="C")
        candidate = work / "Kandidat"
        html_path = candidate / "Lebenslauf - Person.Test.html"
        html_path.write_text(
            '<!doctype html><html lang="de"><head><style>@page { size: A4; margin: 0; }.page { width: 210mm; height: 297mm; }</style></head><body><main class="page"><!-- passfoto:start --><!-- passfoto:end --></main></body></html>',
            encoding="utf-8",
        )
        png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
        (self.project.data / "Passfoto.png").write_bytes(png)
        self.assertEqual(0, handle_passfoto(self.project.context, {"arbeitsordner": work}))
        first = html_path.read_bytes()
        self.assertIn(base64.b64encode(png), first)
        self.assertEqual(0, handle_passfoto(self.project.context, {"arbeitsordner": work}))
        self.assertEqual(first, html_path.read_bytes())

    def test_universal_static_check_accepts_universal_order(self):
        args = {
            "datum": "2026-08-23", "bewerbungen_root": self.project.applications,
            "stammdaten_path": self.project.master, "profil_path": self.project.profile,
        }
        self.assertEqual(0, handle_universal_neu(self.project.context, args))
        work = self.project.applications / "_Universal-Lebenslauf/_Arbeitsdateien/2026-08-23--Softwareentwicklung"
        candidate = work / "Kandidat"
        support = "Dieser vollständig synthetische Nachweis dokumentiert eine belastbare lokale Vertragsprüfung mit ausreichendem Inhalt."
        for name in ("Stellenbeschreibung.md", "Analyse.md", "Qualitaetscheck.md", "Druck-Hinweis.md"):
            (candidate / name).write_text("# Nachweis\n\n" + support, encoding="utf-8")
        (candidate / "Lebenslauf - Person.Test.html").write_text(
            '<!doctype html><html lang="de"><head><style>@page { size: A4; margin: 0; }.page { width: 210mm; height: 297mm; }</style></head><body>'
            '<main class="page"><header data-cv-page-header>Seite 1</header><section data-cv-section="profil">Profil</section><footer class="page-footer">Seite 1 von 2</footer></main>'
            '<main class="page"><header data-cv-page-header>Seite 2</header><section data-cv-section="chronologie">Chronologie</section><footer class="page-footer">Seite 2 von 2</footer></main></body></html>',
            encoding="utf-8",
        )
        self.assertEqual(0, handle_pruefen(self.project.context, {"ordner": candidate, "auftrag_path": work / "Universalauftrag.json"}))

    def test_two_page_cv_requires_structured_headers_sections_and_footer(self):
        path = self.project.root / "Lebenslauf - Person.Test.html"
        path.write_text(
            '<!doctype html><html lang="de"><head><style>@page { size: A4; margin: 0; }.page { width: 210mm; height: 297mm; }</style></head><body>'
            '<main class="page"><section data-cv-section="profil">Profil</section><section>Unmarkiert</section><footer class="footer">Seite 1</footer></main>'
            '<main class="page"><section data-cv-section="profil">Chronologie</section><footer class="page-footer">Seite 2</footer></main></body></html>',
            encoding="utf-8",
        )
        errors = _static_html_errors(path, "lebenslauf")
        self.assertTrue(any("data-cv-page-header" in item for item in errors))
        self.assertTrue(any("page-footer" in item for item in errors))
        self.assertTrue(any("data-cv-section" in item for item in errors))
        self.assertTrue(any("dokumentweit eindeutig" in item for item in errors))


class ApprovalTokenAndBaselineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="apply-foundry-contract-")
        self.addCleanup(self.temporary.cleanup)
        self.project = SyntheticProject(Path(self.temporary.name))
        self.work, _ = self.project.create_application()

    def test_approval_is_bound_to_current_artifact_set(self):
        artifact = self.work / "Kandidat/Pruefseite.txt"
        artifact.write_text("persönlich zu prüfender synthetischer Inhalt", encoding="utf-8")
        record = artifact_record(artifact, self.work)
        records = [record]
        report = {
            "schemaVersion": 7, "status": "bereit_zur_sichtpruefung", "personalReview": "textpruefung",
            "artifacts": {"candidate": records},
            "approvalRequest": {"approvalId": "FR-ABCDEF123456", "artifactSetSha256": artifact_set_hash(records, self.work)},
        }
        write_atomic_json(self.work / "Finalisierungsbericht.json", report)
        self.assertEqual(0, handle_freigabe(self.project.context, {
            "arbeitsordner": self.work, "freigabe_id": "FR-ABCDEF123456", "bestaetigt": True,
            "notiz": "  geprüft   und bestätigt ",
        }))
        approval = read_json(self.work / "Sichtfreigabe.json")
        self.assertEqual(1, approval["schemaVersion"])
        self.assertTrue(approval["humanConfirmation"])
        self.assertEqual("geprüft und bestätigt", approval["note"])
        self.assertEqual(record["path"], approval["artifacts"][0]["path"])
        artifact.write_text("nachträglich verändert", encoding="utf-8")
        with self.assertRaises(ContractError):
            handle_freigabe(self.project.context, {"arbeitsordner": self.work, "freigabe_id": "FR-ABCDEF123456", "bestaetigt": True})

    def test_approval_requires_explicit_confirmation_and_exact_id(self):
        with self.assertRaises(ContractError):
            handle_freigabe(self.project.context, {"arbeitsordner": self.work, "freigabe_id": "FR-ABCDEF123456"})
        with self.assertRaises(ContractError):
            handle_freigabe(self.project.context, {"arbeitsordner": self.work, "freigabe_id": "bad", "bestaetigt": True})

    def test_token_report_preserves_measured_values_on_later_unavailability(self):
        available = {
            "arbeitsordner": self.work, "messbereich": "gesamte_bewerbung", "nutzungsdaten_verfuegbar": True,
            "anbieter": "OpenAI", "modell": "synthetic-test", "messquelle": "runtime",
            "beginn": datetime(2026, 8, 23, 10, 0, tzinfo=timezone.utc),
            "ende": datetime(2026, 8, 23, 10, 1, tzinfo=timezone.utc),
            "eingabe_tokens": 10, "ausgabe_tokens": 5, "gesamt_tokens": 15,
        }
        self.assertEqual(0, handle_tokenbericht(self.project.context, available))
        self.assertEqual(0, handle_tokenbericht(self.project.context, {
            "arbeitsordner": self.work, "messbereich": "gesamte_bewerbung",
        }))
        report = read_json(self.work / "Tokenverbrauch.json")
        self.assertEqual("available", report["availability"])
        self.assertEqual(15, report["sections"][0]["totalTokens"])

    def test_unavailable_token_report_uses_required_literal_and_no_estimate(self):
        self.project.reset_output()
        self.assertEqual(0, handle_tokenbericht(self.project.context, {
            "arbeitsordner": self.work, "messbereich": "lebenslauf",
        }))
        self.assertIn("Tokenverbrauch: Von dieser Agentenumgebung nicht bereitgestellt.", self.project.stdout.getvalue())
        section = read_json(self.work / "Tokenverbrauch.json")["sections"][0]
        self.assertIsNone(section["inputTokens"])
        with self.assertRaises(ContractError):
            handle_tokenbericht(self.project.context, {
                "arbeitsordner": self.work, "messbereich": "lebenslauf", "eingabe_tokens": 99,
            })

    def test_three_python_reports_create_generic_schema_one_baseline(self):
        reports = []
        for index, duration in enumerate((1100, 900, 1000), 1):
            path = Path(self.temporary.name) / ("report-%d.json" % index)
            write_atomic_json(path, {
                "schemaVersion": 1, "suite": "schnell", "testNamePattern": None, "status": "bestanden",
                "durationMs": duration,
                "runtime": {"os": "linux", "architecture": "x86_64", "coreRuntime": {"language": "python", "version": "3.11.9"}},
                "timing": {"testDurationMs": duration - 100, "p95TestDurationMs": 100},
            })
            reports.append(path)
        baseline = Path(self.temporary.name) / "baseline.json"
        self.assertEqual(0, handle_test_baseline(self.project.context, {"bericht_path": reports, "baseline_path": baseline}))
        entry = read_json(baseline)["baselines"][0]
        self.assertEqual(1000, entry["durationMsMedian"])
        self.assertEqual("python", entry["runtime"]["coreRuntime"]["language"])

    def test_baseline_rejects_filtered_or_mixed_runtime_reports(self):
        reports = []
        for index in range(3):
            path = Path(self.temporary.name) / ("mixed-%d.json" % index)
            write_atomic_json(path, {
                "schemaVersion": 1, "suite": "schnell", "testNamePattern": "filter" if index == 0 else None,
                "status": "bestanden", "durationMs": 100,
                "runtime": {"os": "linux", "architecture": "x86_64", "python": "3.11.9"},
                "timing": {"testDurationMs": 80, "p95TestDurationMs": 20},
            })
            reports.append(path)
        with self.assertRaises(ContractError):
            handle_test_baseline(self.project.context, {"bericht_path": reports, "baseline_path": Path(self.temporary.name) / "baseline.json"})


class RuntimeDetectionTests(unittest.TestCase):
    def test_explicit_browser_is_identified_from_version_output(self):
        with tempfile.TemporaryDirectory() as temp:
            executable = Path(temp) / "browser"
            executable.write_text("synthetic", encoding="utf-8")
            with mock.patch.object(runtime, "_version_output", return_value="Google Chrome 151.0.1234.5"):
                details = runtime.browser_details("auto", executable)
                mismatch = runtime.browser_details("edge", executable)
        self.assertTrue(details["available"])
        self.assertEqual("chrome", details["name"])
        self.assertEqual("chromium", details["engine"])
        self.assertFalse(mismatch["available"])

    def test_firefox_uses_gecko_engine(self):
        with tempfile.TemporaryDirectory() as temp:
            executable = Path(temp) / "firefox"
            executable.write_text("synthetic", encoding="utf-8")
            with mock.patch.object(runtime, "_version_output", return_value="Mozilla Firefox 142.0"):
                details = runtime.browser_details("firefox", executable)
        self.assertEqual("gecko", details["engine"])

    def test_diagnose_schema_four_has_generic_python_core(self):
        report = runtime.diagnose()
        self.assertEqual(4, report["schemaVersion"])
        self.assertEqual("python", report["coreRuntime"]["language"])
        self.assertEqual("3.11", report["coreRuntime"]["minimumVersion"])
        self.assertIn(report["exitCode"], (0, 1, 2))

    def test_diagnose_marks_arm_as_unsupported(self):
        with mock.patch.object(runtime.platform, "machine", return_value="arm64"):
            report = runtime.diagnose()
        platform_check = next(item for item in report["checks"] if item["name"] == "plattform")
        self.assertEqual("error", platform_check["status"])
        self.assertEqual(2, report["exitCode"])


if __name__ == "__main__":
    unittest.main()
