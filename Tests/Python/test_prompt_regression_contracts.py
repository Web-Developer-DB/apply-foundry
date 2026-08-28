#!/usr/bin/env python3
"""Offline contracts for the native prompt-regression orchestrator."""

import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in os.sys.path:
    os.sys.path.insert(0, str(REPO_ROOT))

from Tools.apply_foundry.cli import CommandContext  # noqa: E402
from Tools.apply_foundry.prompt_regression import (  # noqa: E402
    _arguments,
    _copy_public_repository,
    _initialize_fixture,
    _mutation_error,
    _reported_model,
    _require_sandbox,
    _sandbox_arguments,
    _sandbox_runtime_path,
    _scenario_artifact_error,
    _scenario_output_error,
    run_prompt_regression,
)
from Tools.apply_foundry.io import sha256_file, write_atomic_json  # noqa: E402


class PromptRegressionContractTests(unittest.TestCase):
    def test_argument_vectors_preserve_prompt_as_one_argument(self):
        prompt = "Mehrzeiliger Prompt\nmit Sonderzeichen $()"
        codex = _arguments({
            "id": "codex", "agent": "codex", "model": "gpt-test",
            "arguments": ["exec", "--ignore-user-config", "--sandbox", "read-only", "--model", "gpt-test", "--json"],
        }, prompt)
        gemini = _arguments({
            "id": "gemini", "agent": "gemini", "model": "gemini-test",
            "arguments": ["--prompt", "", "--model", "gemini-test", "--output-format", "json", "--approval-mode", "plan"],
        }, prompt)
        self.assertEqual(prompt, codex[-1])
        self.assertEqual(prompt, gemini[1])
        self.assertEqual("workspace-write", codex[codex.index("--sandbox") + 1])
        self.assertEqual("auto_edit", gemini[gemini.index("--approval-mode") + 1])
        with self.assertRaisesRegex(Exception, "Zielmodell"):
            _arguments({"id": "unsafe", "agent": "codex", "model": "gpt-test", "arguments": ["exec"]}, prompt)

    def test_every_catalog_agent_gets_an_explicit_synthetic_workspace_policy(self):
        catalog = json.loads((REPO_ROOT / "Tests/PromptRegression/models.json").read_text(encoding="utf-8"))
        expected = {
            "codex": ("--sandbox", "workspace-write"),
            "claude": ("--permission-mode", "acceptEdits"),
            "gemini": ("--approval-mode", "auto_edit"),
        }
        for model in catalog["models"]:
            with self.subTest(model=model["id"]):
                arguments = _arguments(model, "synthetic")
                if model["agent"] in expected:
                    flag, value = expected[model["agent"]]
                    self.assertEqual(value, arguments[arguments.index(flag) + 1])

    def test_output_and_mutation_contracts_are_fail_closed(self):
        scenario = {"requiredPatterns": ["Matrix", "Evidenz"], "forbiddenPatterns": ["PRIVATE_SENTINEL"]}
        self.assertIsNone(_scenario_output_error(scenario, "matrix und EVIDENZ wurden geprüft"))
        self.assertIn("Pflichtsignal", _scenario_output_error(scenario, "Matrix") or "")
        self.assertIn("Verbotenes", _scenario_output_error(scenario, "Matrix Evidenz PRIVATE_SENTINEL") or "")
        self.assertIsNone(_mutation_error([" M Private/Test.json"], ["Private/**"]))
        self.assertIn("Nicht erlaubte", _mutation_error([" M README.md"], ["Private/**"]) or "")

    def test_public_copy_excludes_private_and_agent_state(self):
        with tempfile.TemporaryDirectory() as temp:
            source, target = Path(temp) / "source", Path(temp) / "target"
            (source / "Private").mkdir(parents=True)
            (source / ".codex").mkdir()
            (source / "Tools").mkdir()
            (source / "Private/secret.txt").write_text("secret", encoding="utf-8")
            (source / ".codex/state.json").write_text("{}", encoding="utf-8")
            (source / "Tools/public.txt").write_text("public", encoding="utf-8")
            _copy_public_repository(source, target)
            self.assertTrue((target / "Tools/public.txt").is_file())
            self.assertFalse((target / "Private").exists())
            self.assertFalse((target / ".codex").exists())

    def test_synthetic_fixture_contains_only_synthetic_bound_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _initialize_fixture(root, "softwareentwicklung")
            work = root / "Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle"
            order = json.loads((work / "Bewerbungsauftrag.json").read_text(encoding="utf-8"))
            self.assertEqual(5, order["schemaVersion"])
            self.assertEqual("relativ_zu_bewerbungen_root", order["pfadModus"])
            self.assertEqual(
                "Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle/Kandidat",
                order["kandidatOrdner"],
            )
            self.assertFalse((work / "Anforderungsmatrix.json").exists())
            self.assertFalse((work / "Evidenzindex.json").exists())
            self.assertNotIn("PRIVATE_SENTINEL", (root / "Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md").read_text(encoding="utf-8"))

    def test_role_scenario_requires_real_new_hash_bound_artifacts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _initialize_fixture(root, "softwareentwicklung", "rollenstrategie-transfer")
            scenario = {"id": "rollenstrategie-transfer"}
            self.assertIn("fehlt", _scenario_artifact_error(scenario, root, []) or "")
            base = Path("Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle")
            work = root / base
            job = work / "Kandidat/Stellenbeschreibung.md"
            profile = root / "Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
            order = work / "Bewerbungsauftrag.json"
            write_atomic_json(work / "Anforderungsmatrix.json", {
                "schemaVersion": 5,
                "requirements": [{"id": "muss-1", "belegRefIds": ["profil-1"]}],
                "stellenanzeigeAbdeckung": {"sourceSha256": sha256_file(job), "fundstellen": []},
                "recruiterStrategie": {"kernbotschaft": "Belegte Transferstrategie", "profilSubstanz": "ausreichend"},
                "anschreibenStrategie": {"status": "final", "argumente": [{"id": "arg-1", "belegRefIds": ["profil-1"]}]},
            })
            write_atomic_json(work / "Evidenzindex.json", {
                "schemaVersion": 1, "profilSha256": sha256_file(profile), "auftragSha256": sha256_file(order),
                "belege": [{"id": "profil-1", "quelle": "profil", "text": "Synthetischer Beleg"}],
            })
            changes = [
                "?? %s" % (base / "Anforderungsmatrix.json").as_posix(),
                "?? %s" % (base / "Evidenzindex.json").as_posix(),
            ]
            self.assertIsNone(_scenario_artifact_error(scenario, root, changes))

    def test_model_evidence_validates_reported_values_and_allows_transparent_argument_evidence(self):
        self.assertEqual(
            ("gpt-test", None),
            _reported_model('{"type":"turn.completed","model":"gpt-test"}', "gpt-test"),
        )
        actual, error = _reported_model('{"providerID":"openai","modelID":"gpt-test"}', "openai/gpt-test")
        self.assertEqual("openai/gpt-test", actual)
        self.assertIsNone(error)
        self.assertEqual((None, None), _reported_model('{"status":"ok"}', "gpt-test"))
        self.assertIn("Unerwartete", _reported_model('{"model":"other"}', "gpt-test")[1] or "")

    @unittest.skipUnless(sys.platform.startswith("linux"), "bubblewrap-Vertrag ist Linux-spezifisch")
    def test_bubblewrap_vector_hides_host_home_and_missing_sandbox_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            arguments = _sandbox_arguments("/usr/bin/true", ("--version",), root)
            self.assertIn("--unshare-all", arguments)
            self.assertIn("--disable-userns", arguments)
            self.assertIn(str(root), arguments)
            self.assertIn("/workspace", arguments)
            self.assertNotIn(str(REPO_ROOT), arguments)
            with mock.patch.dict(os.environ, {"PATH": "/home/comp/private-bin:/opt:/usr/bin"}, clear=False):
                sandbox_path = _sandbox_runtime_path().split(os.pathsep)
            self.assertIn("/opt", sandbox_path)
            self.assertNotIn("/home/comp/private-bin", sandbox_path)
            with mock.patch("Tools.apply_foundry.prompt_regression.shutil.which", return_value=None):
                with self.assertRaisesRegex(Exception, "bubblewrap fehlt"):
                    _require_sandbox(root)

    def test_contradiction_fixture_is_only_enabled_for_that_scenario(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            _initialize_fixture(root, "it-support-quereinstieg", "widerspruch-und-fortsetzung")
            order_path = root / "Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle/Bewerbungsauftrag.json"
            order = json.loads(order_path.read_text(encoding="utf-8"))
            self.assertEqual("rueckfragen_offen", order["dialog"]["status"])
            self.assertTrue(order["dialog"]["rueckfragen"][0]["widerspruch"])

    def test_missing_agent_cli_produces_schema_one_failure_report(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            catalog = root / "Tests/PromptRegression"
            catalog.mkdir(parents=True)
            (catalog / "models.json").write_text(json.dumps({
                "schemaVersion": 1, "defaultTimeoutSeconds": 10,
                "models": [{
                    "id": "missing", "agent": "missing", "provider": "synthetic", "model": "none",
                    "command": "apply-foundry-command-that-does-not-exist", "cliPackage": "none", "cliVersion": "1",
                    "credentialVariable": "SYNTHETIC_TOKEN", "tier": "pr", "arguments": [],
                }],
            }), encoding="utf-8")
            (catalog / "scenarios.json").write_text(json.dumps({
                "schemaVersion": 1, "scenarios": [{
                    "id": "offline", "tier": "pr", "prompt": "offline", "fixture": None,
                    "allowedFileChanges": [], "requiredPatterns": [], "forbiddenPatterns": [],
                }],
            }), encoding="utf-8")
            report = root / "report.json"
            stdout, stderr = io.StringIO(), io.StringIO()
            context = CommandContext(root, root, stdout, stderr)
            self.assertEqual(1, run_prompt_regression(context, "pr", report, None))
            value = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(1, value["schemaVersion"])
            self.assertEqual("fehlgeschlagen", value["status"])
            self.assertIn("Agenten-CLI fehlt", value["failures"][0])


if __name__ == "__main__":
    unittest.main()
