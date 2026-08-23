#!/usr/bin/env python3
"""Regression contracts for public Python-core documentation."""

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ROOT_DOCUMENTS = (
    REPO_ROOT / "README.md",
    REPO_ROOT / "AGENTS.md",
    REPO_ROOT / "CHANGELOG.md",
    REPO_ROOT / "Console App.md",
)
DOCUMENT_DIRECTORIES = ("Prompts", "Tests", "Vorlagen", "Private.example")
LEGACY_RUNTIME = re.compile(
    r"\.ps(?:1|m1)\b|\bpwsh\b|Tools/linux_py|Python 3\.9|PowerShell 7\.6|setup-windows\.ps1",
    re.IGNORECASE,
)
MARKDOWN_LINK = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")
TOOL_REFERENCE = re.compile(r"\bTools/([A-Za-z0-9_./-]+\.(?:py|sh|cmd))\b")


def documentation_files():
    files = list(ROOT_DOCUMENTS)
    for directory in DOCUMENT_DIRECTORIES:
        files.extend(sorted((REPO_ROOT / directory).rglob("*.md")))
    return files


class DocumentationContractTests(unittest.TestCase):
    def test_active_documentation_has_no_removed_runtime_references(self):
        # This is a sample applicant skill, not documentation for the runtime.
        allowed_example = REPO_ROOT / "Private.example/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.example.md"
        failures = []
        for path in documentation_files():
            if path == allowed_example:
                continue
            match = LEGACY_RUNTIME.search(path.read_text(encoding="utf-8"))
            if match:
                failures.append("%s: %s" % (path.relative_to(REPO_ROOT), match.group(0)))
        self.assertEqual([], failures, "Removed runtime reference(s):\n" + "\n".join(failures))

    def test_local_markdown_links_and_tool_references_exist(self):
        failures = []
        for path in documentation_files():
            content = path.read_text(encoding="utf-8")
            for raw_target in MARKDOWN_LINK.findall(content):
                target = raw_target.strip().split("#", 1)[0]
                if not target or "://" in target or target.startswith(("mailto:", "#")):
                    continue
                candidate = (path.parent / target).resolve()
                if not candidate.is_file():
                    failures.append("%s -> %s" % (path.relative_to(REPO_ROOT), raw_target))
            for raw_tool in TOOL_REFERENCE.findall(content):
                candidate = REPO_ROOT / "Tools" / raw_tool
                if not candidate.is_file():
                    failures.append("%s -> Tools/%s" % (path.relative_to(REPO_ROOT), raw_tool))
        self.assertEqual([], failures, "Broken local documentation reference(s):\n" + "\n".join(failures))


if __name__ == "__main__":
    unittest.main()
