import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
TOOLS = PROJECT / "Tools"
FIXTURE = PROJECT / "Tests/Fixtures/CrossPlatform"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from apply_foundry.commands_browser import _assert_runtime_current
from apply_foundry.browser_tools import runtime_fingerprint
from apply_foundry.errors import ContractError


class CrossPlatformFixtureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "origin"
        self.applications = self.root / "Private/Bewerbungen"
        self.applications.mkdir(parents=True)
        data = self.root / "Private/Daten"
        data.mkdir()
        shutil.copy2(FIXTURE / "stammdaten.md", data / "01_PERSOENLICHE_DATEN.md")
        shutil.copy2(FIXTURE / "profil.md", data / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md")
        self.personal = data / "01_PERSOENLICHE_DATEN.md"
        self.profile = data / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
        self.scenario = json.loads((FIXTURE / "scenario.json").read_text(encoding="utf-8"))

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *arguments, cwd=None):
        return subprocess.run(
            [sys.executable, str(TOOLS / "bewerbung.py"), *map(str, arguments)],
            cwd=str(cwd or PROJECT), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30, check=False,
        )

    def create_order(self):
        result = self.run_cli(
            "neu", "--firma", self.scenario["firma"], "--rolle", self.scenario["rolle"],
            "--umfang", self.scenario["umfang"], "--umfang-quelle", self.scenario["umfangQuelle"],
            "--datum", self.scenario["datum"], "--stammdaten-path", self.personal,
            "--profil-path", self.profile, "--stellenbeschreibung-path", FIXTURE / "stelle.md",
            "--bewerbungen-root", self.applications,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        return self.applications / self.scenario["relativeOrderPath"]

    def test_shared_fixture_normalizes_to_the_cross_core_contract(self):
        order_path = self.create_order()
        normalized_path = self.root / "normalized-order.json"
        result = subprocess.run(
            [sys.executable, str(FIXTURE / "normalize_order.py"), str(order_path), str(normalized_path)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=False,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        value = json.loads(normalized_path.read_text(encoding="utf-8"))
        self.assertEqual(5, value["schemaVersion"])
        self.assertEqual("relativ_zu_bewerbungen_root", value["pfadModus"])
        self.assertEqual("Parity-GmbH/2026-08-23--Fullstack-Developer", value["zielOrdner"])
        self.assertEqual("komplette_bewerbung", value["dokumentumfang"]["kennung"])
        self.assertEqual(
            hashlib.sha256((FIXTURE / "stammdaten.md").read_bytes()).hexdigest().upper(),
            value["quellnachweise"]["stammdatenSha256BeiAnlage"],
        )

    def test_relocated_order_continues_but_foreign_runtime_evidence_is_stale(self):
        order_path = self.create_order()
        relocated = Path(self.temp.name) / "relocated"
        shutil.copytree(self.root / "Private", relocated / "Private")
        relocated_work = relocated / "Private/Bewerbungen" / order_path.parent.relative_to(self.applications)
        powershell_runtime = {
            "schemaVersion": 1, "os": "windows", "architecture": "x64",
            "distributionId": None, "distributionVersion": None, "wsl": False,
            "pythonVersion": None,
            "coreRuntime": {
                "platform": "windows", "language": "powershell", "kind": "powershell",
                "version": "7.6.0", "minimumVersion": "7.6",
                "path": "C:/Program Files/PowerShell/7/pwsh.exe", "executable": "C:/Program Files/PowerShell/7/pwsh.exe",
            },
            "browser": None,
        }
        artifact = relocated_work / "Arbeitsnotizen.md"
        (relocated_work / "Finalisierungsbericht.json").write_text(json.dumps({
            "schemaVersion": 7, "status": "bereit_zur_sichtpruefung", "runtime": powershell_runtime,
            "artifacts": {"candidate": [{
                "path": artifact.relative_to(relocated_work).as_posix(), "bytes": artifact.stat().st_size,
                "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest().upper(),
            }]},
        }), encoding="utf-8")
        status = self.run_cli("status", "--arbeitsordner", relocated_work, "--als-json")
        self.assertEqual(0, status.returncode, status.stdout + status.stderr)
        report = json.loads(status.stdout)
        self.assertEqual(str(relocated_work), report["workFolder"])
        self.assertFalse(report["finalReportValid"])
        self.assertNotEqual("persoenliche_pruefung", report["phase"])
        with self.assertRaises(ContractError):
            _assert_runtime_current(powershell_runtime, {}, False)

    def test_runtime_validator_rejects_generic_core_mismatch_but_reads_legacy_python_shape(self):
        current = runtime_fingerprint()
        _assert_runtime_current(current, {}, False)
        wrong_language = deepcopy(current)
        wrong_language["coreRuntime"]["language"] = "powershell"
        with self.assertRaises(ContractError):
            _assert_runtime_current(wrong_language, {}, False)
        legacy = deepcopy(current)
        for key in ("platform", "language", "path"):
            legacy["coreRuntime"].pop(key, None)
        _assert_runtime_current(legacy, {}, False)


if __name__ == "__main__":
    unittest.main()
