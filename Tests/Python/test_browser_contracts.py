#!/usr/bin/env python3
"""Standard-library contracts and opt-in native Chromium smoke tests."""

import io
import json
import os
import subprocess
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from Tools.apply_foundry.browser_tools import (  # noqa: E402
    BrowserError,
    _chromium_base,
    browser_candidates,
    build_capture_html,
    extract_pdf_text,
    html_pages,
    measure_bottom_whitespace,
    pdf_media_box_summary,
    pdf_page_count,
    print_html,
    read_png_pixels,
    run_process,
    runtime_fingerprint,
    sha256,
)
from Tools.apply_foundry.cli import CommandContext  # noqa: E402
from Tools.apply_foundry.commands_browser import _css_diagnostics, _density_gate, _similarity, ats, layout  # noqa: E402
from Tools.apply_foundry.errors import CliUsageError  # noqa: E402


def png_chunk(kind, payload):
    import binascii

    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)


def synthetic_png(width=40, height=60):
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            dark = 10 <= x <= 29 and 8 <= y <= 20
            row.extend((20, 30, 40) if dark else (255, 255, 255))
        rows.append(b"\x00" + bytes(row))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header) + png_chunk(b"IDAT", zlib.compress(b"".join(rows))) + png_chunk(b"IEND", b"")


class BrowserPrimitiveTests(unittest.TestCase):

    def test_css_diagnostics_accepts_screen_spacing_with_print_reset(self):
        css = ".page + .page { margin-top: 8mm; } @media print { .page + .page { margin-top: 0; } }"
        self.assertEqual([], _css_diagnostics(css))
        self.assertTrue(_css_diagnostics(".page + .page { margin-top: 8mm; }"))

    def test_density_gate_blocks_sparse_two_page_cv_and_accepts_structured_exception(self):
        layout_report = {"results": [{
            "htmlFile": "Lebenslauf - Muster.Max.html", "pageNumber": 2, "pageCount": 2,
            "bottomWhitespaceMm": 74.2, "densityWarning": "Ungewöhnlich viel freie Fläche.",
        }]}
        blocked = _density_gate(layout_report, None)
        self.assertEqual("ueberarbeitung_erforderlich", blocked["status"])
        reason = (
            "Seite: Die zweite Seite enthält 74,2 mm freie Fläche. Beleglage: Die vorhandenen Quellen enthalten "
            "keine weitere recruiterrelevante, belegte Information. Einseiter: Ein Einseiter würde die vollständige "
            "formale Chronologie und die relevanten Projektbelege unlesbar verdichten."
        )
        exception = _density_gate(layout_report, reason)
        self.assertEqual("ausnahme_bestaetigt", exception["status"])
        self.assertEqual(reason, exception["exceptionReason"])

    def test_density_gate_rejects_unstructured_exception(self):
        layout_report = {"results": [{
            "htmlFile": "Lebenslauf - Muster.Max.html", "pageNumber": 2, "pageCount": 2,
            "bottomWhitespaceMm": 74.2,
        }]}
        with self.assertRaisesRegex(CliUsageError, "Seite:"):
            _density_gate(layout_report, "Bitte ausnahmsweise zulassen.")
    def test_pdf_stream_length_beats_embedded_endstream_bytes(self):
        """A stream payload may legally contain that byte sequence in comments."""
        cmap = b"/CIDInit /ProcSet findresource begin\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n1 beginbfchar\n<0001> <004D>\nendstream\n<0002> <0061>\nendbfchar\nendcmap\n"
        content = b"BT /F1 12 Tf <00010002> Tj ET\n"
        objects = [
            b"1 0 obj << /Type /Font /ToUnicode 2 0 R >> endobj\n",
            b"2 0 obj << /Length " + str(len(cmap)).encode() + b" >> stream\n" + cmap + b"endstream\nendobj\n",
            b"3 0 obj << /Type /Page /Resources << /Font << /F1 1 0 R >> >> /Contents 4 0 R >> endobj\n",
            b"4 0 obj << /Length " + str(len(content)).encode() + b" >> stream\n" + content + b"endstream\nendobj\n",
        ]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "length.pdf"
            path.write_bytes(b"%PDF-1.7\n" + b"".join(objects) + b"%%EOF\n")
            self.assertIn("Ma", extract_pdf_text(path))

    def test_explicit_a4_pages_and_capture_document(self):
        source = '<html><head></head><body><main class="page"><p>Eins</p></main><main class="page"><p>Zwei</p></main></body></html>'
        pages = html_pages(source)
        self.assertEqual(2, len(pages))
        capture = build_capture_html(source, pages[1])
        self.assertIn("Zwei", capture)
        self.assertNotIn("Eins", capture)
        self.assertIn("data-layoutcheck-geometry-b64", capture)

    def test_portable_png_decoder_and_density_measurement(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "page.png"
            path.write_bytes(synthetic_png())
            width, height, color_type, channels, pixels = read_png_pixels(path)
            self.assertEqual((40, 60, 2, 3), (width, height, color_type, channels))
            self.assertEqual(width * height * channels, len(pixels))
            density = measure_bottom_whitespace(path, "Lebenslauf - Muster.Max.html", 1, 1, 3.0)
        self.assertTrue(density["available"])
        self.assertGreater(density["bottomWhitespacePx"], 20)

    def test_png_crc_tampering_is_rejected(self):
        value = bytearray(synthetic_png())
        value[-5] ^= 0xFF
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "tampered.png"
            path.write_bytes(value)
            with self.assertRaises(BrowserError):
                read_png_pixels(path)

    def test_process_timeout_marks_result_and_kills_process_group(self):
        result = run_process(Path(sys.executable), ("-c", "import time; time.sleep(5)"), 1)
        self.assertTrue(result.timed_out)
        self.assertNotEqual(0, result.exit_code)

    def test_balanced_token_and_ngram_contract(self):
        source = "Max Muster entwickelt sichere Shopware Erweiterungen mit PHP Symfony Vue und APIs für digitale Shops."
        equal = _similarity(source, source)
        changed = _similarity(source, source.replace("Shopware", "beliebige"))
        self.assertTrue(equal["passed"])
        self.assertEqual(100.0, equal["orderedTrigramCoveragePercent"])
        self.assertFalse(changed["passed"])

    def test_runtime_fingerprint_names_platform_neutral_python_core(self):
        report = runtime_fingerprint()
        expected_platform = "windows" if sys.platform == "win32" else "macos" if sys.platform == "darwin" else "linux"
        self.assertEqual(1, report["schemaVersion"])
        self.assertEqual(expected_platform, report["os"])
        self.assertEqual(expected_platform, report["coreRuntime"]["platform"])
        self.assertEqual("python", report["coreRuntime"]["language"])
        self.assertEqual("python", report["coreRuntime"]["kind"])
        self.assertEqual("3.11", report["coreRuntime"]["minimumVersion"])
        self.assertTrue(report["coreRuntime"]["path"])
        self.assertIsNone(report["powerShellVersion"])

    def test_layout_prepare_is_read_only_with_respect_to_browser(self):
        with tempfile.TemporaryDirectory() as temp:
            candidate = Path(temp) / "Private/Bewerbungen/Acme/_Arbeitsdateien/2026-08-23--Test/Kandidat"
            candidate.mkdir(parents=True)
            (candidate / "Lebenslauf - Muster.Max.html").write_text(
                '<html><head></head><body><main class="page">Test</main></body></html>', encoding="utf-8"
            )
            output = io.StringIO()
            code = layout(CommandContext(REPO_ROOT, REPO_ROOT, output, io.StringIO()), {"ordner": candidate, "nur_vorbereiten": True})
            self.assertEqual(0, code)
            self.assertIn("kein Browser gestartet", output.getvalue())
            self.assertFalse((candidate.parent / "Layoutcheck/Layoutcheck-Bericht.json").exists())

    def test_layout_rejects_non_a4_dimensions_as_usage_error(self):
        with tempfile.TemporaryDirectory() as temp:
            candidate = Path(temp) / "Private/Bewerbungen/Acme/_Arbeitsdateien/2026-08-23--Test/Kandidat"
            candidate.mkdir(parents=True)
            (candidate / "Lebenslauf - Muster.Max.html").write_text(
                '<html><head></head><body><main class="page">Test</main></body></html>', encoding="utf-8"
            )
            with self.assertRaises(CliUsageError):
                layout(CommandContext(REPO_ROOT, REPO_ROOT, io.StringIO(), io.StringIO()), {"ordner": candidate, "width": 800, "height": 800, "nur_vorbereiten": True})

    def test_explicit_snap_transition_browser_is_rejected_without_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            wrapper = Path(temp) / "chromium-browser"
            marker = Path(temp) / "executed"
            # A launcher that delegates through snap must be rejected before
            # its body runs. Keep the marker command after the snap token so a
            # regression would be observable.
            wrapper.write_text("#!/bin/sh\n# snap run chromium\ntouch '%s'\necho 'Chromium 151.0.0.0'\n" % marker, encoding="utf-8")
            wrapper.chmod(0o755)
            # Snap is a Linux-only packaging transition.  Simulating Linux
            # keeps this safety contract meaningful on every CI platform.
            with mock.patch("Tools.apply_foundry.browser_tools.sys.platform", "linux"):
                with self.assertRaises(BrowserError):
                    browser_candidates("chromium", str(wrapper), False, True)
            self.assertFalse(marker.exists())

    def test_browser_sandbox_is_active_normally_and_root_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            profile = Path(temp)
            # This contract targets Linux root handling. Simulating Linux keeps
            # the same assertion meaningful on the Windows/macOS CI runners.
            with mock.patch("Tools.apply_foundry.browser_tools.sys.platform", "linux"):
                with mock.patch("Tools.apply_foundry.browser_tools.os.geteuid", return_value=1000, create=True):
                    arguments = _chromium_base(profile)
                self.assertNotIn("--no-sandbox", arguments)
                self.assertNotIn("--disable-gpu-sandbox", arguments)
                with mock.patch("Tools.apply_foundry.browser_tools.os.geteuid", return_value=0, create=True):
                    with mock.patch.dict(os.environ, {}, clear=False):
                        os.environ.pop("APPLY_FOUNDRY_ALLOW_UNSANDBOXED_BROWSER", None)
                        with self.assertRaisesRegex(BrowserError, "normalen Benutzer"):
                            _chromium_base(profile)
                with mock.patch("Tools.apply_foundry.browser_tools.os.geteuid", return_value=0, create=True):
                    with mock.patch.dict(os.environ, {"APPLY_FOUNDRY_ALLOW_UNSANDBOXED_BROWSER": "1"}):
                        self.assertIn("--no-sandbox", _chromium_base(profile))


@unittest.skipUnless(os.environ.get("APPLY_FOUNDRY_BROWSER_TEST") == "1", "echter Browser-Smoke nur in der Browser-Suite")
class ChromiumWorkflowSmoke(unittest.TestCase):
    def test_layout_pdf_a4_and_ats_contract(self):
        candidates = browser_candidates("auto", None, False, True)
        self.assertTrue(candidates, "Browser-Suite erfordert einen nativen Chrome-/Chromium-/Edge-Pfad")
        browser = candidates[0]
        with tempfile.TemporaryDirectory(prefix="apply-foundry-browser-") as temp:
            private = Path(temp) / "Private"
            work = private / "Bewerbungen/Acme/_Arbeitsdateien/2026-08-23--Test"
            candidate = work / "Kandidat"
            browser_temp = private / "Bewerbungen/.browser-tmp"
            (private / "Daten").mkdir(parents=True)
            candidate.mkdir(parents=True)
            browser_temp.mkdir()
            stammdaten = private / "Daten/01_PERSOENLICHE_DATEN.md"
            stammdaten.write_text("- Vollständiger Name: Max Muster\n", encoding="utf-8")
            html_path = candidate / "Lebenslauf - Muster.Max.html"
            html_path.write_text(
                '''<!doctype html><html lang="de"><head><meta charset="utf-8"><style>@page { size: A4; margin: 0; } html,body{margin:0}.page { width:210mm;height:297mm;box-sizing:border-box;padding:18mm;font-family:Arial,sans-serif }</style></head><body><main class="page"><h1>Max Muster</h1><h2>Testentwickler</h2><p>Erfahrener Entwickler für sichere Systeme und verständliche Anwendungen. Diese synthetische Datei prüft vollständig die Unicode Textschicht im erzeugten Dokument. Sie enthält genügend Wörter für robuste Token Bigramm und Trigramm Vergleiche ohne echte private Bewerbungsdaten.</p><p>01/2020 - 12/2025</p><footer class="page-footer">Seite 1</footer></main></body></html>''',
                encoding="utf-8",
            )
            context = CommandContext(REPO_ROOT, REPO_ROOT, io.StringIO(), io.StringIO())
            self.assertEqual(0, layout(context, {"ordner": candidate, "browser_executable_path": browser.path, "timeout_seconds": 60}))
            layout_report = json.loads((work / "Layoutcheck/Layoutcheck-Bericht.json").read_text(encoding="utf-8"))
            self.assertEqual(1, layout_report["expectedScreenshots"])
            self.assertFalse(layout_report["results"][0]["domGeometry"]["pageOverflowY"])
            self.assertIsNotNone(layout_report["results"][0]["bottomWhitespaceMm"])

            pdf_path = html_path.with_suffix(".pdf")
            preflight = print_html(browser, html_path, pdf_path, 60, browser_temp)
            self.assertEqual(1, preflight["actualPageCount"])
            self.assertEqual(1, pdf_page_count(pdf_path))
            self.assertRegex(pdf_media_box_summary(pdf_path) or "", r"^594\.\d+ x 841\.\d+ pt$")
            extracted = extract_pdf_text(pdf_path)
            self.assertIn("Max Muster", extracted)
            self.assertIn("Testentwickler", extracted)

            order = {
                "schemaVersion": 5, "firma": "Acme", "rolle": "Testentwickler",
                "dokumentumfang": {"lebenslauf": "individuell", "anschreiben": False, "emailNachricht": False},
            }
            order_path = work / "Bewerbungsauftrag.json"
            order_path.write_text(json.dumps(order), encoding="utf-8")
            export_path = work / "PDF-Export/PDF-Export-Bericht.json"
            export_path.parent.mkdir()
            export_path.write_text(json.dumps({
                "schemaVersion": 1, "runtime": runtime_fingerprint(browser),
                "results": [{
                    "htmlFile": html_path.name, "htmlSha256": sha256(html_path),
                    "pdfFile": pdf_path.name, "pdfSha256": sha256(pdf_path),
                    "pages": 1, "mediaBox": pdf_media_box_summary(pdf_path),
                }],
            }), encoding="utf-8")
            ats_report = work / "ATS-Pruefbericht.json"
            self.assertEqual(0, ats(context, {
                "ordner": candidate, "stammdaten_path": stammdaten, "auftrag_path": order_path,
                "bericht_path": ats_report, "pdf_export_bericht_path": export_path,
            }))
            report = json.loads(ats_report.read_text(encoding="utf-8"))
            self.assertEqual("ok", report["status"])
            self.assertEqual(100.0, report["results"][0]["tokenCoveragePercent"])

    def test_full_finalization_approval_and_atomic_publication(self):
        candidates = browser_candidates("auto", None, False, True)
        self.assertTrue(candidates, "Browser-Suite erfordert einen nativen Chrome-/Chromium-/Edge-Pfad")
        browser = candidates[0]
        with tempfile.TemporaryDirectory(prefix="apply-foundry-finalization-") as temp:
            root = Path(temp)
            data = root / "Private/Daten"
            applications = root / "Private/Bewerbungen"
            data.mkdir(parents=True)
            applications.mkdir()
            master = data / "01_PERSOENLICHE_DATEN.md"
            profile = data / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
            job = root / "synthetische-stelle.md"
            master.write_text(
                "# Persönliche Daten\n\n"
                "- Vollständiger Name: Max Muster\n- Vorname: Max\n- Nachname: Muster\n"
                "- Dateiname-Name: Muster.Max\n- Adresse: Testweg 1, 12345 Teststadt\n"
                "- Telefon: +49 123 456789\n- E-Mail: max.muster@example.invalid\n"
                "- Verfügbarkeit: ab sofort\n- Frühester Eintrittstermin: ab sofort\n"
                "- Gewünschte Stellenart: Vollzeit\n- Gewünschter Stundenumfang: 40 Std./Woche\n"
                "- Gewünschtes Arbeitsmodell: hybrid\n- Gewünschte Region: Deutschland\n"
                "- Wunschgehalt verwenden: nein\n- Wunschgehalt manuell: nicht angegeben\n"
                "- Gehaltsmodell: Jahresbrutto\n- Gehaltsregion: Deutschland\n"
                "- Gehaltslogik: keine Gehaltsangabe verwenden\n",
                encoding="utf-8",
            )
            profile.write_text(
                "# Bewerberprofil\n\n## Kurzprofil\n\nSynthetisches Fullstack-Profil.\n\n"
                "## Berufserfahrung\n\n01/2020 - 12/2024 · Fullstack-Entwicklung mit Python, PHP und Webtechnologien.\n",
                encoding="utf-8",
            )
            job.write_text(
                "# Fullstack Developer\n\nDiese vollständig fiktive Stellenbeschreibung dient ausschließlich dem nativen Linux-Vertragstest. "
                "Gesucht werden wartbare Webentwicklung, API-Integration, Qualitätssicherung und nachvollziehbare Zusammenarbeit.\n",
                encoding="utf-8",
            )

            def cli(*arguments):
                result = subprocess.run(
                    [sys.executable, str(REPO_ROOT / "Tools/bewerbung.py"), *map(str, arguments)],
                    cwd=str(REPO_ROOT), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    timeout=180, check=False,
                )
                self.assertEqual(0, result.returncode, result.stdout + "\n" + result.stderr)
                return result

            cli(
                "neu", "--firma", "Acme GmbH", "--rolle", "Fullstack Developer", "--umfang", "A",
                "--umfang-quelle", "direkter_auftrag", "--datum", "2026-08-23",
                "--stammdaten-path", master, "--profil-path", profile,
                "--stellenbeschreibung-path", job, "--bewerbungen-root", applications,
            )
            work = applications / "Acme-GmbH/_Arbeitsdateien/2026-08-23--Fullstack-Developer"
            candidate = work / "Kandidat"
            order_path = work / "Bewerbungsauftrag.json"
            order = json.loads(order_path.read_text(encoding="utf-8"))
            order["dialog"].update(status="bereit_zur_dokumenterstellung", updatedAtUtc="2026-08-23T00:00:00Z")
            order["bewerbungsentscheidung"] = "bewerben"
            order["seitenstrategie"] = "eine_seite"
            order_path.write_text(json.dumps(order, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            (work / "Anforderungsmatrix.json").write_text(json.dumps({
                "schemaVersion": 1,
                "requirements": [{
                    "id": "muss-1", "anforderung": "Fullstack-Entwicklung", "typ": "muss",
                    "status": "erfuellt", "belegart": "PROJEKTPRAXIS",
                    "beleg": "Synthetische Fullstack-Entwicklung", "behandlung": "Lebenslauf und Anschreiben",
                }],
            }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            evidence = (
                "Dieser vollständig synthetische Nachweis dokumentiert den fachlichen und technischen Teststand. "
                "Er enthält bewusst keine echten Bewerber-, Arbeitgeber- oder Projektdaten und ist inhaltlich abgeschlossen."
            )
            for name, heading in (
                ("Stellenbeschreibung.md", "Stellenbeschreibung"), ("Analyse.md", "Analyse"),
                ("Qualitaetscheck.md", "Qualitätscheck"), ("Druck-Hinweis.md", "Druck-Hinweis"),
            ):
                (candidate / name).write_text("# %s\n\n%s\n" % (heading, evidence), encoding="utf-8")
            css = (
                "@page { size: A4; margin: 0; }html,body{margin:0;padding:0}"
                ".page { width: 210mm; height: 297mm; box-sizing: border-box; padding: 18mm; "
                "font-family: 'Liberation Sans', Arial, sans-serif; overflow:hidden }"
            )
            cv_body = (
                "<h1>Max Muster</h1><h2>Fullstack Developer</h2>"
                "<p>Fullstack-Entwicklung mit Python, PHP und Webtechnologien sowie wartbaren APIs und Qualitätssicherung.</p>"
                "<p>01/2020 - 12/2024</p><p>Acme GmbH · Fullstack Developer</p>"
            )
            letter_body = (
                "<h1>Max Muster</h1><h2>Bewerbung als Fullstack Developer bei Acme GmbH</h2>"
                "<p>Meine synthetisch belegte Fullstack-Entwicklung verbindet wartbare APIs, Webtechnologien und Qualitätssicherung. "
                "Damit unterstütze ich das fiktive Team nachvollziehbar und ohne unbelegte Behauptungen.</p>"
            )
            for name, body in (("Lebenslauf - Muster.Max.html", cv_body), ("Anschreiben - Muster.Max.html", letter_body)):
                (candidate / name).write_text(
                    '<!doctype html><html lang="de"><head><meta charset="utf-8"><style>%s</style></head>'
                    '<body><main class="page">%s<footer class="page-footer">Seite 1</footer></main></body></html>' % (css, body),
                    encoding="utf-8",
                )
            (candidate / "Email-Nachricht--Acme-GmbH.md").write_text(
                "Betreff: Bewerbung als Fullstack Developer - Max Muster\n\n"
                "Guten Tag,\n\nanbei erhalten Sie meine synthetischen Testunterlagen.\n",
                encoding="utf-8",
            )

            cli(
                "finalisieren", "--arbeitsordner", work, "--stammdaten-path", master,
                "--profil-path", profile, "--browser-executable-path", browser.path,
                "--timeout-seconds", "90",
            )
            final_report_path = work / "Finalisierungsbericht.json"
            prepared = json.loads(final_report_path.read_text(encoding="utf-8"))
            self.assertEqual("bereit_zur_sichtpruefung", prepared["status"])
            self.assertEqual(7, len(prepared["stageRuns"]))
            self.assertEqual(2, prepared["expectedScreenshots"])
            check_state = json.loads((work / "Pruefstand.json").read_text(encoding="utf-8"))
            self.assertEqual("finalisierungs_pruefstand", check_state["kind"])
            self.assertEqual(["dialog", "stammdaten", "statisch", "inhalt", "layout", "pdf", "ats"], [item["id"] for item in check_state["stages"]])
            self.assertTrue(all(item["status"] == "passed" for item in check_state["stages"]))

            cli(
                "freigabe", "--arbeitsordner", work,
                "--freigabe-id", prepared["approvalRequest"]["approvalId"], "--bestaetigt",
                "--notiz", "Alle zwei synthetischen A4-Screenshots persönlich geprüft; große Weißräume sind in diesem Test beabsichtigt.",
            )
            cli(
                "finalisieren", "--arbeitsordner", work, "--stammdaten-path", master,
                "--profil-path", profile, "--browser-executable-path", browser.path,
                "--veroeffentlichen",
            )
            target = applications / "Acme-GmbH/2026-08-23--Fullstack-Developer"
            self.assertTrue((target / "Manifest.json").is_file())
            self.assertEqual(2, len(list((target / "Versand").glob("*.pdf"))))
            self.assertEqual(1, len(list((target / "Versand").glob("Email-Nachricht--*.md"))))
            published = json.loads(final_report_path.read_text(encoding="utf-8"))
            self.assertEqual("veroeffentlicht", published["status"])
            self.assertFalse(any(path.name.startswith((".publish-", ".backup-")) for path in target.parent.iterdir()))

    def test_universal_two_page_finalization_approval_and_activation(self):
        candidates = browser_candidates("auto", None, False, True)
        self.assertTrue(candidates, "Browser-Suite erfordert einen nativen Chrome-/Chromium-/Edge-Pfad")
        browser = candidates[0]
        with tempfile.TemporaryDirectory(prefix="apply-foundry-universal-") as temp:
            root = Path(temp)
            data = root / "Private/Daten"
            applications = root / "Private/Bewerbungen"
            data.mkdir(parents=True)
            applications.mkdir()
            master = data / "01_PERSOENLICHE_DATEN.md"
            profile = data / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
            master.write_text(
                "# Persönliche Daten\n\n- Vollständiger Name: Max Muster\n"
                "- Vorname: Max\n- Nachname: Muster\n- Dateiname-Name: Muster.Max\n"
                "- Adresse: Testweg 1, 12345 Teststadt\n- Telefon: +49 123 456789\n"
                "- E-Mail: max.muster@example.invalid\n- Verfügbarkeit: ab sofort\n",
                encoding="utf-8",
            )
            profile.write_text(
                "# Bewerberprofil\n\nSynthetische Softwareentwicklung mit Python, PHP, APIs, Tests und Webtechnologien.\n",
                encoding="utf-8",
            )

            def cli(*arguments):
                result = subprocess.run(
                    [sys.executable, str(REPO_ROOT / "Tools/bewerbung.py"), *map(str, arguments)],
                    cwd=str(REPO_ROOT), text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    timeout=180, check=False,
                )
                self.assertEqual(0, result.returncode, result.stdout + "\n" + result.stderr)
                return result

            cli(
                "universal-neu", "--datum", "2026-08-23", "--stammdaten-path", master,
                "--profil-path", profile, "--bewerbungen-root", applications,
            )
            work = applications / "_Universal-Lebenslauf/_Arbeitsdateien/2026-08-23--Softwareentwicklung"
            candidate = work / "Kandidat"
            evidence = (
                "Dieser vollständig synthetische Nachweis dokumentiert die fachliche Vorbereitung und die lokale "
                "Vertragsprüfung ohne echte Bewerber-, Arbeitgeber- oder Projektdaten in nachvollziehbarer Form."
            )
            for name, heading in (
                ("Stellenbeschreibung.md", "Positionierungsgrundlage"), ("Analyse.md", "Analyse"),
                ("Qualitaetscheck.md", "Qualitätscheck"), ("Druck-Hinweis.md", "Druck-Hinweis"),
            ):
                (candidate / name).write_text("# %s\n\n%s\n" % (heading, evidence), encoding="utf-8")
            css = (
                "@page { size: A4; margin: 0; }html,body{margin:0;padding:0}"
                ".page { width:210mm;height:297mm;box-sizing:border-box;padding:18mm;overflow:hidden;"
                "font-family:'Liberation Sans',Arial,sans-serif;page-break-after:always }"
                ".page:last-child{page-break-after:auto}"
            )
            page_one = (
                "<header data-cv-page-header><h1>Max Muster</h1><p>Softwareentwicklung · Seite 1 von 2</p></header>"
                "<section data-cv-section=\"profil\"><h2>Kurzprofil</h2><p>Synthetische Fullstack-Entwicklung mit wartbaren Schnittstellen, "
                "automatisierten Tests und verständlicher technischer Dokumentation.</p></section>"
                "<section data-cv-section=\"technologien-projekte\"><h2>Technologien und Projekte</h2><p>Python, PHP, HTML, CSS, JavaScript und API-Integration "
                "in vollständig fiktiven Projektbeispielen für sichere lokale Vertragstests.</p></section>"
            )
            page_two = (
                "<header data-cv-page-header><h1>Max Muster</h1><p>Softwareentwicklung · Seite 2 von 2</p></header>"
                "<section data-cv-section=\"berufserfahrung\"><h2>Berufserfahrung</h2><p>01/2020 - 12/2024 · Synthetische Softwareentwicklung mit "
                "nachvollziehbarem eigenem Beitrag.</p></section><section data-cv-section=\"weiterbildung\"><h2>Weiterbildung</h2><p>Kontinuierliche fiktive "
                "Vertiefung in Qualitätssicherung.</p></section><section data-cv-section=\"ausbildung-schulbildung\"><h2>Ausbildung und Schulbildung</h2>"
                "<p>Vollständig synthetische Angaben ausschließlich für diesen Regressionstest.</p></section>"
            )
            (candidate / "Lebenslauf - Muster.Max.html").write_text(
                '<!doctype html><html lang="de"><head><meta charset="utf-8"><style>%s</style></head>'
                '<body><main class="page">%s<footer class="page-footer">Seite 1</footer></main>'
                '<main class="page">%s<footer class="page-footer">Seite 2</footer></main></body></html>'
                % (css, page_one, page_two),
                encoding="utf-8",
            )

            cli(
                "universal-finalisieren", "--arbeitsordner", work, "--stammdaten-path", master,
                "--profil-path", profile, "--browser-executable-path", browser.path,
                "--timeout-seconds", "90",
            )
            report_path = work / "Universal-Finalisierungsbericht.json"
            prepared = json.loads(report_path.read_text(encoding="utf-8"))
            self.assertEqual("bereit_zur_sichtpruefung", prepared["status"])
            self.assertEqual(2, len(prepared["screenshots"]))
            self.assertEqual(1, sum(str(item.get("path", "")).endswith(".html") for item in prepared["candidate"]))
            cli(
                "freigabe", "--arbeitsordner", work,
                "--freigabe-id", prepared["approvalRequest"]["approvalId"], "--bestaetigt",
                "--notiz", "Beide synthetischen A4-Seiten persönlich geprüft; die Weißräume sind beabsichtigt.",
            )
            cli(
                "universal-finalisieren", "--arbeitsordner", work, "--stammdaten-path", master,
                "--profil-path", profile, "--browser-executable-path", browser.path,
                "--veroeffentlichen",
            )
            active = applications / "_Universal-Lebenslauf/Aktiv"
            manifest = json.loads((active / "Manifest.json").read_text(encoding="utf-8"))
            self.assertEqual("universal_lebenslauf", manifest["auftragsart"])
            self.assertTrue(manifest["personalReview"]["confirmed"])
            self.assertEqual(1, len(list((active / "Versand").glob("*.pdf"))))
            self.assertEqual(1, len(list((active / "Intern").glob("*.html"))))
            self.assertFalse(work.exists())
            status = cli("universal-status", "--bewerbungen-root", applications, "--als-json")
            self.assertEqual("aktiv", json.loads(status.stdout)["phase"])


if __name__ == "__main__":
    unittest.main()
