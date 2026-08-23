import json
import tempfile
import unittest
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
import sys

if str(PROJECT / "Tools") not in sys.path:
    sys.path.insert(0, str(PROJECT / "Tools"))

from apply_foundry.finalization_cache import cache_decision, read_state, save_result, stage_fingerprint


class FinalizationCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source.txt"
        self.output = self.root / "report.json"
        self.state_path = self.root / "Pruefstand.json"
        self.source.write_text("Quelle\n", encoding="utf-8")
        self.output.write_text("{}\n", encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def fingerprint(self, stage="statisch"):
        return stage_fingerprint(
            stage,
            self.root,
            implementation_files=[PROJECT / "Tools/apply_foundry/finalization_cache.py"],
            input_files=[self.source],
            parameters={"mode": "test"},
            runtime={"schemaVersion": 1, "coreRuntime": {"kind": "python", "version": "3.11"}},
        )

    def test_schema_two_roundtrip_and_hash_bound_hit(self):
        fingerprint = self.fingerprint()
        save_result(self.state_path, self.root, "statisch", fingerprint, output_files=[self.output], duration_ms=3)
        state = read_state(self.state_path)
        self.assertEqual(2, state["schemaVersion"])
        self.assertEqual("finalisierungs_pruefstand", state["kind"])
        self.assertTrue(cache_decision(state, "statisch", fingerprint, self.root)["reusable"])

    def test_changed_input_or_output_invalidates_cache(self):
        fingerprint = self.fingerprint()
        save_result(self.state_path, self.root, "statisch", fingerprint, output_files=[self.output])
        self.source.write_text("Andere Quelle\n", encoding="utf-8")
        decision = cache_decision(read_state(self.state_path), "statisch", self.fingerprint(), self.root)
        self.assertFalse(decision["reusable"])
        self.assertEqual("input_changed", decision["reason"])
        self.source.write_text("Quelle\n", encoding="utf-8")
        self.output.write_text('{"changed":true}\n', encoding="utf-8")
        decision = cache_decision(read_state(self.state_path), "statisch", fingerprint, self.root)
        self.assertFalse(decision["reusable"])
        self.assertEqual("output_changed", decision["reason"])

    def test_failed_or_interrupted_stage_is_never_reused(self):
        fingerprint = self.fingerprint("pdf")
        save_result(self.state_path, self.root, "pdf", fingerprint, status="running")
        self.assertEqual("interrupted", cache_decision(read_state(self.state_path), "pdf", fingerprint, self.root)["reason"])
        save_result(self.state_path, self.root, "pdf", fingerprint, status="failed", failure={"errorCode": "test"})
        state = read_state(self.state_path)
        self.assertEqual("previous_failed", cache_decision(state, "pdf", fingerprint, self.root)["reason"])
        self.assertEqual("test", state["stages"][0]["failure"]["errorCode"])

    def test_rerunning_earlier_stage_drops_downstream_entries(self):
        static = self.fingerprint("statisch")
        pdf = self.fingerprint("pdf")
        save_result(self.state_path, self.root, "statisch", static, output_files=[self.output])
        save_result(self.state_path, self.root, "pdf", pdf, output_files=[self.output])
        self.assertEqual(["statisch", "pdf"], [item["id"] for item in read_state(self.state_path)["stages"]])
        save_result(self.state_path, self.root, "statisch", static, status="running")
        self.assertEqual(["statisch"], [item["id"] for item in read_state(self.state_path)["stages"]])

    def test_invalid_or_legacy_state_is_ignored(self):
        self.state_path.write_text(json.dumps({"schemaVersion": 1, "stages": []}), encoding="utf-8")
        self.assertIsNone(read_state(self.state_path))


if __name__ == "__main__":
    unittest.main()
