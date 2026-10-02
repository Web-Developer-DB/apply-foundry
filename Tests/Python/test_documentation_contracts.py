#!/usr/bin/env python3
"""Regression contracts for public Python-core documentation."""

import re
import tempfile
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


REPO_ROOT = Path(__file__).resolve().parents[2]
ROOT_DOCUMENTS = (
    REPO_ROOT / "README.md",
    REPO_ROOT / "AGENTS.md",
    REPO_ROOT / "CHANGELOG.md",
)
DOCUMENT_DIRECTORIES = ("Prompts", "Tests", "Vorlagen", "Private.example", "docs")
LEGACY_RUNTIME = re.compile(
    r"\.ps(?:1|m1)\b|\bpwsh\b|Tools/linux_py|Python 3\.9|PowerShell 7\.6|setup-windows\.ps1",
    re.IGNORECASE,
)
MARKDOWN_LINK = re.compile(r"!?\[[^]]*\]\((<[^>]+>|[^)]+)\)")
TOOL_REFERENCE = re.compile(r"\bTools/([A-Za-z0-9_./-]+\.(?:py|sh|cmd))\b")


def without_fenced_code(content):
    """Example commands and literal markup are not rendered document links."""
    lines = []
    fence = None
    for line in content.splitlines():
        marker = re.match(r"^\s*(`{3,}|~{3,})", line)
        if marker and fence is None:
            fence = marker.group(1)
        elif marker and fence and marker.group(1)[0] == fence[0] and len(marker.group(1)) >= len(fence):
            fence = None
        elif fence is None:
            lines.append(line)
    return "\n".join(lines)


class DocumentHTML(HTMLParser):
    def __init__(self):
        super().__init__()
        self.targets = []
        self.anchors = set()

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        for name in ("src", "href"):
            if attributes.get(name):
                self.targets.append(attributes[name])
        if attributes.get("id"):
            self.anchors.add(attributes["id"])
        if tag == "a" and attributes.get("name"):
            self.anchors.add(attributes["name"])

    handle_startendtag = handle_starttag


def document_references(content):
    content = without_fenced_code(content)
    parser = DocumentHTML()
    parser.feed(content)
    targets = list(parser.targets)
    for raw in MARKDOWN_LINK.findall(content):
        # Angle brackets permit spaces; optional Markdown link titles are not paths.
        if raw.startswith("<"):
            targets.append(raw[1:raw.index(">")])
        else:
            targets.append(re.split(r'\s+["\']', raw.strip(), maxsplit=1)[0])
    return targets


def document_anchors(content):
    content = without_fenced_code(content)
    parser = DocumentHTML()
    parser.feed(content)
    anchors = set(parser.anchors)
    seen = {}
    for line in content.splitlines():
        heading = re.match(r"^ {0,3}#{1,6}\s+(.+?)(?:\s+#+)?$", line)
        if not heading:
            continue
        title = re.sub(r"<[^>]*>", "", heading.group(1))
        title = re.sub(r"!?\[([^]]*)\]\([^)]*\)", r"\1", title)
        slug = re.sub(r"[^\w\- ]", "", title.lower()).replace(" ", "-")
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        anchors.add(slug if count == 0 else "%s-%d" % (slug, count))
    return anchors


def local_reference_error(document, target):
    url = urlsplit(target)
    if url.scheme or url.netloc:
        return None
    candidate = (document.parent / unquote(url.path)).resolve() if url.path else document
    if not candidate.is_file():
        return "missing file"
    if url.fragment and candidate.suffix.lower() in (".md", ".html", ".svg"):
        anchors = document_anchors(candidate.read_text(encoding="utf-8"))
        if unquote(url.fragment) not in anchors:
            return "missing fragment"
    return None


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

    def test_local_document_links_images_fragments_and_tool_references_exist(self):
        failures = []
        for path in documentation_files():
            content = path.read_text(encoding="utf-8")
            for raw_target in document_references(content):
                error = local_reference_error(path, raw_target)
                if error:
                    failures.append("%s -> %s (%s)" % (path.relative_to(REPO_ROOT), raw_target, error))
            for raw_tool in TOOL_REFERENCE.findall(content):
                candidate = REPO_ROOT / "Tools" / raw_tool
                if not candidate.is_file():
                    failures.append("%s -> Tools/%s" % (path.relative_to(REPO_ROOT), raw_tool))
        self.assertEqual([], failures, "Broken local documentation reference(s):\n" + "\n".join(failures))


class DocumentationReferenceParserTests(unittest.TestCase):
    def test_markdown_and_html_images_and_links_are_collected(self):
        content = '''[Page](guide.md#entry) ![Image](image.png)
<img src="other.png"><a href="#explicit" id="explicit">Go</a>
[With spaces](<other guide.md#intro>) [Titled](guide.md "Guide")
```html
<img src="not-a-real-image.png">
```
'''
        self.assertEqual(
            ["other.png", "#explicit", "guide.md#entry", "image.png", "other guide.md#intro", "guide.md"],
            document_references(content),
        )

    def test_valid_and_invalid_relative_files_and_fragments(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            document = root / "README.md"
            document.write_text('<a id="explicit"></a>\n# Einführung\n# Einführung\n', encoding="utf-8")
            (root / "image.png").write_bytes(b"synthetic test fixture")
            (root / "other guide.md").write_text("# Intro\n", encoding="utf-8")
            for target in ("#explicit", "#einführung", "#einführung-1", "image.png", "other%20guide.md#intro", "https://example.invalid/missing", "mailto:max@example.invalid"):
                with self.subTest(target=target):
                    self.assertIsNone(local_reference_error(document, target))
            self.assertEqual("missing file", local_reference_error(document, "missing.png"))
            self.assertEqual("missing fragment", local_reference_error(document, "#missing"))
            self.assertEqual("missing fragment", local_reference_error(document, "other%20guide.md#missing"))


if __name__ == "__main__":
    unittest.main()
