#!/usr/bin/env python3
"""Render public synthetic README illustrations; never read Private/."""

import argparse
import html
import json
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "Tools"))

from apply_foundry.browser_tools import (
    build_capture_html,
    html_pages,
    render_screenshot,
    resolve_browser,
)

TOKENS = re.compile(r"\{\{([A-Z_0-9]+)\}\}")
HTML_FIELDS = {
    "ARBEITSWEISE_BULLETS", "SPRACHEN_BULLETS",
    "BERUFLICHER_WERDEGANG", "PRAXIS_EINTRAEGE", "BILDUNG_EINTRAEGE",
}


def document_source(template_name, values):
    source = (ROOT / "Vorlagen" / template_name).read_text(encoding="utf-8")

    def replace(match):
        key = match.group(1)
        if key not in values:
            raise ValueError("Missing synthetic value: " + key)
        return values[key] if key in HTML_FIELDS else html.escape(values[key])

    source = TOKENS.sub(replace, source)
    if "{{" in source or "}}" in source:
        raise ValueError("Unresolved template placeholder")
    label_css = (
        "<style>.page{position:relative}.example-label{position:absolute;"
        "bottom:8mm;left:13mm;right:13mm;border-top:1px solid #bccbd9;"
        "padding-top:2mm;color:#526780;font-size:10px;"
        "font-family:Arial,'Liberation Sans',sans-serif}</style>"
    )
    source = source.replace("</head>", label_css + "</head>")
    source = source.replace(
        "</main>",
        '<div class="example-label">SYNTHETISCHE DESIGNVORSCHAU · '
        'ALLE ANGABEN FIKTIV · KEINE FREIGEGEBENE BEWERBUNG</div></main>',
    )
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser-path", help="Optional existing Chromium executable")
    parser.add_argument("--output-dir", type=Path, default=ROOT / ".github/assets")
    args = parser.parse_args()
    browser = resolve_browser(
        executable_path=args.browser_path, require_chromium=True,
    )
    values = json.loads((FIXTURE / "example-data.json").read_text(encoding="utf-8"))
    sources = {
        "cv-example": (document_source("Designreferenz-Lebenslauf.html", values), 1123),
        "cover-letter-example": (document_source("Designreferenz-Anschreiben.html", values), 1123),
        "workflow-example": ((FIXTURE / "workflow-example.html").read_text(encoding="utf-8"), 560),
        "output-example": ((FIXTURE / "output-example.html").read_text(encoding="utf-8"), 560),
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="apply-foundry-readme-") as temporary:
        temp_root = Path(temporary)
        for name, (source, height) in sources.items():
            pages = html_pages(source)
            if len(pages) != 1:
                raise ValueError(name + " must contain exactly one page")
            capture = build_capture_html(source, pages[0])
            if height == 560:
                capture = capture.replace("297mm", "148mm")
            capture_path = temp_root / (name + ".html")
            capture_path.write_text(capture, encoding="utf-8")
            output = args.output_dir / (name + ".png")
            render_screenshot(browser, capture_path, output, 794, height, 45, temp_root)
            print(output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
