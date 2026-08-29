"""Native Python handlers for browser, PDF, ATS and finalization stages."""

from __future__ import annotations

import html as html_module
import json
import os
import re
import shutil
import tempfile
import time
import unicodedata
import uuid
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Mapping, Optional, Sequence, TextIO, Tuple, Union

from .browser_tools import (
    BrowserError,
    BrowserInfo,
    browser_candidates,
    build_capture_html,
    candidate_link_contract,
    check_chromium_readiness,
    extract_pdf_text,
    html_page_bodies,
    html_pages,
    measure_bottom_whitespace,
    pdf_media_box_summary,
    pdf_page_count,
    print_html,
    render_screenshot,
    resolve_browser,
    runtime_fingerprint,
    safe_name,
    verify_pdf_link_targets,
)
from .errors import CliUsageError, ContractError, WorkflowError
from .finalization_cache import STAGE_ORDER, cache_decision, read_state, save_result, stage_fingerprint
from .io import artifact_record, canonical_json, read_json, read_text, sha256_bytes, sha256_file, utc_now, write_atomic_json, write_atomic_text
from .paths import infer_work_context, require_private_applications_root, safe_path
from .contracts import approval_records, artifact_set_hash, assert_artifacts_current, new_approval_id


def _emit(ctx: Any, message: str = "", *, error: bool = False) -> None:
    stream: TextIO = ctx.stderr if error else ctx.stdout
    stream.write(message + "\n")


def _arg(values: Mapping[str, Any], name: str, default: Any = None) -> Any:
    value = values.get(name, default)
    return default if value is None else value


def _path(values: Mapping[str, Any], name: str, default: Optional[Path] = None) -> Optional[Path]:
    value = values.get(name)
    if value is None or value == "":
        return default
    return Path(str(value))


def _applications_root_from(path: Path) -> Path:
    current = Path(os.path.abspath(str(path)))
    if current.is_file():
        current = current.parent
    for candidate in (current, *current.parents):
        if candidate.name == "Bewerbungen" and candidate.parent.name == "Private":
            return require_private_applications_root(candidate, must_exist=True)
    raise CliUsageError(f"Pfad liegt nicht unter einem Private/Bewerbungen-Root: {path}")


def _safe_folder(path: Path) -> Tuple[Path, Path]:
    if not path.is_dir():
        raise ContractError(f"Ordner existiert nicht oder ist kein Verzeichnis: {path}")
    root = _applications_root_from(path)
    return safe_path(path, root, must_exist=True, kind="dir"), root


def _document_scope(order: Mapping[str, Any]) -> Dict[str, Any]:
    schema = order.get("schemaVersion")
    if not isinstance(schema, int) or not 1 <= schema <= 5:
        raise ContractError("Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 5.")
    scope = order.get("dokumentumfang")
    if schema < 4 and scope is None:
        return {"lebenslauf": "individuell", "anschreiben": True, "emailNachricht": True}
    if not isinstance(scope, dict):
        raise ContractError("Bewerbungsauftrag enthält keinen gültigen dokumentumfang.")
    cv = scope.get("lebenslauf")
    letter = scope.get("anschreiben")
    email = scope.get("emailNachricht")
    if cv not in ("individuell", "universal_unveraendert", "nicht_enthalten") or not isinstance(letter, bool) or not isinstance(email, bool):
        raise ContractError("dokumentumfang enthält ungültige oder nicht typisierte Werte.")
    if cv == "nicht_enthalten" and not letter and not email:
        raise ContractError("dokumentumfang wählt kein Dokument aus.")
    return {"lebenslauf": cv, "anschreiben": letter, "emailNachricht": email}


def _selected_html(folder: Path, order: Optional[Mapping[str, Any]] = None) -> List[Path]:
    cvs = sorted(folder.glob("Lebenslauf - *.html"), key=lambda item: item.name)
    letters = sorted(folder.glob("Anschreiben - *.html"), key=lambda item: item.name)
    for value in [*cvs, *letters]:
        safe_path(value, folder, must_exist=True, kind="file")
    if len(cvs) > 1 or len(letters) > 1:
        raise ContractError(f"Es wird höchstens ein Lebenslauf und ein Anschreiben erwartet; gefunden: {len(cvs)} / {len(letters)}.")
    if order is not None:
        scope = _document_scope(order)
        expected_cv = scope["lebenslauf"] != "nicht_enthalten"
        expected_letter = scope["anschreiben"]
        if len(cvs) != int(expected_cv) or len(letters) != int(expected_letter):
            raise ContractError("HTML-Dateien stimmen nicht exakt mit dem ausgewählten Dokumentumfang überein.")
    if not cvs and not letters:
        raise ContractError("Es wurde kein ausgewähltes HTML-Dokument gefunden.")
    return sorted([*letters, *cvs], key=lambda item: item.name)


def _work_output(candidate: Path, name: str, explicit: Optional[Path], root: Path) -> Path:
    if explicit is not None:
        result = explicit
    elif candidate.name == "Kandidat" and candidate.parent.parent.name == "_Arbeitsdateien":
        result = candidate.parent / name
    else:
        result = candidate.parent / "_Arbeitsdateien" / candidate.name / name
    result = safe_path(result, root, kind="dir")
    if "_Arbeitsdateien" not in result.parts:
        raise ContractError(f"{name}-Ausgabe muss unter Private/Bewerbungen/.../_Arbeitsdateien liegen: {result}")
    result.mkdir(parents=True, exist_ok=True)
    return safe_path(result, root, must_exist=True, kind="dir")


def _report_path(output: Path, explicit: Optional[Path], name: str) -> Path:
    value = explicit or output / name
    if value.suffix != ".json":
        raise CliUsageError(f"Bericht muss eine JSON-Datei sein: {value}")
    return safe_path(value, output, kind="file")


def _browser_temp(root: Path) -> Path:
    value = safe_path(root / ".browser-tmp", root, kind="dir")
    value.mkdir(parents=True, exist_ok=True)
    return safe_path(value, root, must_exist=True, kind="dir")


def _css_diagnostics(text: str) -> List[str]:
    values: List[str] = []
    print_rule = re.search(r"(?is)@media\s+print\s*\{.*?\.page\s*\+\s*\.page\s*\{(?P<rules>[^}]*)\}", text)
    print_reset = bool(print_rule and re.search(
        r"(?i)\bmargin(?:-top)?\s*:\s*0(?:[a-z%]+)?\s*(?:!important\s*)?;", print_rule.group("rules")
    ))
    for match in re.finditer(r"(?is)\.page\s*\+\s*\.page\s*\{(?P<rules>[^}]*)\}", text):
        rules = match.group("rules")
        margin = re.search(r"(?i)margin(?:-top)?\s*:\s*(?!0(?:[a-z%]+)?\s*(?:;|$))[^;}]+", rules)
        padding = re.search(r"(?i)padding-top\s*:\s*(?!0(?:[a-z%]+)?\s*(?:;|$))[^;}]+", rules)
        if (margin or padding) and not print_reset:
            values.append("Seitenabstand über `.page + .page` gefunden. Vertikale Vorschauabstände müssen im Druckmodus auf 0 zurückgesetzt werden.")
    return list(dict.fromkeys(values))


def layout(ctx: Any, args: Mapping[str, Any]) -> int:
    folder, root = _safe_folder(Path(str(args["ordner"])))
    width = int(_arg(args, "width", 794))
    height = int(_arg(args, "height", 1123))
    if abs(width / float(height) - 210.0 / 297.0) > 0.01:
        raise CliUsageError(f"Screenshot-Abmessungen müssen dem DIN-A4-Seitenverhältnis entsprechen: {width} x {height}.")
    documents = _selected_html(folder)
    snapshots: List[Tuple[Path, str, str, List[str], List[str]]] = []
    for document in documents:
        text = read_text(document)
        pages = html_pages(text)
        if not pages:
            raise ContractError(f"HTML enthält keine expliziten A4-Seitencontainer: {document.name}")
        snapshots.append((document, sha256_file(document), text, pages, html_page_bodies(text)))
    output = _work_output(folder, "Layoutcheck", _path(args, "output_root"), root)
    report_path = _report_path(output, _path(args, "bericht_path"), "Layoutcheck-Bericht.json")
    for document, _, _, _, _ in snapshots:
        prefix = safe_name(document.stem) + "--"
        for old in output.iterdir():
            if old.is_file() and old.name.startswith(prefix) and old.suffix in (".png", ".pdf"):
                old.unlink()
    expected = sum(len(value[3]) for value in snapshots)
    if bool(_arg(args, "nur_vorbereiten", False)):
        _emit(ctx, f"[OK] Vorbereitung erfolgreich. {expected} A4-Seitenscreenshot(s) sind vorgesehen; es wurde kein Browser gestartet.")
        return 0

    requested = str(_arg(args, "browser", "auto"))
    explicit = str(_arg(args, "browser_executable_path", "")) or None
    allow_firefox = bool(_arg(args, "erlaube_firefox_fallback", False)) or requested == "firefox"
    timeout = int(_arg(args, "timeout_seconds", 60))
    candidates = browser_candidates(requested, explicit, allow_firefox, False)
    if not candidates:
        raise ContractError("Kein passender Browser gefunden. Erlaubt: Chrome, Edge, Chromium oder Firefox für die Layoutdiagnose.")
    temp_root = _browser_temp(root)
    failures: List[str] = []
    for browser in candidates:
        produced: List[Path] = []
        try:
            if browser.engine != "chromium":
                raise BrowserError("Firefox ist nur eine unverbindliche Diagnose; für den vollständigen Geometrie- und PDF-Vertrag wird Chromium benötigt.")
            results: List[Dict[str, Any]] = []
            preflights: List[Dict[str, Any]] = []
            for document, expected_hash, source, pages, bodies in snapshots:
                for warning in _css_diagnostics(source):
                    _emit(ctx, f"[WARNUNG] {document.name}: {warning}")
                with tempfile.TemporaryDirectory(prefix="preflight-", dir=str(temp_root)) as raw_temp:
                    preflight_pdf = Path(raw_temp) / "document.pdf"
                    preflight = print_html(browser, document, preflight_pdf, timeout, temp_root)
                    preflights.append({
                        "htmlFile": document.name,
                        "htmlSha256": expected_hash,
                        "expectedPageCount": preflight["expectedPageCount"],
                        "actualPageCount": preflight["actualPageCount"],
                        "pdfBytes": preflight["pdfBytes"],
                        "mediaBox": preflight["mediaBox"],
                        "a4": True,
                        "status": "bestanden",
                        "cssDiagnostics": _css_diagnostics(source),
                    })
                for index, page_html in enumerate(pages):
                    if sha256_file(document) != expected_hash:
                        raise BrowserError(f"HTML-Datei wurde während des Layoutchecks geändert: {document}")
                    capture = output / f".capture-{safe_name(document.stem)}--{uuid.uuid4().hex}.html"
                    try:
                        write_atomic_text(capture, build_capture_html(source, page_html))
                        screenshot = output / f"{safe_name(document.stem)}--seite-{index + 1}-von-{len(pages)}--{browser.name}.png"
                        geometry = render_screenshot(browser, capture, screenshot, width, height, timeout, temp_root)
                        produced.append(screenshot)
                        page_pdf: Optional[Path] = None
                        if bool(_arg(args, "pdf", False)):
                            page_pdf = output / f"{safe_name(document.stem)}--seite-{index + 1}-von-{len(pages)}--{browser.name}.pdf"
                            print_html(browser, capture, page_pdf, timeout, temp_root)
                            produced.append(page_pdf)
                        footer = bool(re.search(r"(?is)<footer\b[^>]*>", bodies[index]))
                        reserve = 17.0 if footer else 3.0
                        density = ({"available": False, "bottomWhitespacePx": None, "bottomWhitespaceMm": None, "scanBottomReserveMm": reserve, "warning": None}
                                   if bool(_arg(args, "dichtepruefung_deaktivieren", False))
                                   else measure_bottom_whitespace(screenshot, document.name, index + 1, len(pages), reserve))
                        if not bool(_arg(args, "dichtepruefung_deaktivieren", False)) and not density["available"]:
                            raise BrowserError(f"Erforderliche Layoutdichteprüfung fehlgeschlagen: {density['warning']}")
                        results.append({
                            "htmlFile": document.name,
                            "htmlSha256": expected_hash,
                            "pageNumber": index + 1,
                            "pageCount": len(pages),
                            "hasDocumentFooter": footer,
                            "screenshot": str(screenshot),
                            "screenshotSha256": sha256_file(screenshot),
                            "screenshotBytes": screenshot.stat().st_size,
                            "bottomWhitespacePx": density["bottomWhitespacePx"],
                            "bottomWhitespaceMm": density["bottomWhitespaceMm"],
                            "scanBottomReserveMm": density["scanBottomReserveMm"],
                            "densityWarning": density["warning"],
                            "domGeometry": {
                                "pageOverflowX": geometry.get("pageOverflowX"),
                                "pageOverflowY": geometry.get("pageOverflowY"),
                                "outsideElements": geometry.get("outsideElements") or [],
                                "pageClientWidth": geometry.get("pageClientWidth"),
                                "pageClientHeight": geometry.get("pageClientHeight"),
                                "pageScrollWidth": geometry.get("pageScrollWidth"),
                                "pageScrollHeight": geometry.get("pageScrollHeight"),
                            },
                        })
                    finally:
                        try:
                            capture.unlink()
                        except FileNotFoundError:
                            pass
            if any(sha256_file(document) != expected_hash for document, expected_hash, _, _, _ in snapshots):
                raise BrowserError("HTML-Datei wurde während des Layoutchecks geändert.")
            report = {
                "schemaVersion": 3,
                "checkedAtUtc": utc_now(),
                "runtime": runtime_fingerprint(browser),
                "browser": browser.name,
                "sourceFolder": str(folder),
                "captureMode": "eine_png_pro_a4_seite",
                "pageWidth": width,
                "pageHeight": height,
                "expectedScreenshots": len(results),
                "printPreflight": {"mode": "vollstaendiges_original_html", "documents": preflights},
                "results": results,
            }
            write_atomic_json(report_path, report)
            _emit(ctx, f"[OK] Layoutcheck erfolgreich mit Browser: {browser.name}")
            _emit(ctx, f"[OK] Layoutcheck-Bericht geschrieben: {report_path}")
            return 0
        except (OSError, BrowserError, ValueError, ContractError) as exc:
            failures.append(f"{browser.name}: {exc}")
            for value in produced:
                try:
                    value.unlink()
                except FileNotFoundError:
                    pass
    raise ContractError("Layoutcheck fehlgeschlagen: " + " | ".join(failures))


def _run_core(ctx: Any, name: str, args: Mapping[str, Any]) -> None:
    from .commands_core import CORE_HANDLERS

    result = CORE_HANDLERS[name](ctx, args)
    if result not in (None, 0):
        raise ContractError(f"Teilschritt '{name}' ist mit Exitcode {result} fehlgeschlagen.")


def _cache_implementation_files() -> List[Path]:
    package = Path(__file__).resolve().parent
    tools = package.parent
    return sorted(package.glob("*.py"), key=lambda item: item.name) + [tools / "bewerbung.py"]


def _failure_metadata(stage: str, exc: BaseException) -> Dict[str, Any]:
    message = re.sub(r"(?i)(?:[a-z]:)?[/\\][^\r\n]+", "<Pfad>", str(exc))
    return {
        "stage": stage,
        "tool": None,
        "exitCode": None,
        "errorCode": "workflow_error" if isinstance(exc, WorkflowError) else "unexpected_error",
        "message": message[:500],
    }


def _cached_stage(
    ctx: Any,
    *,
    work: Path,
    state_path: Path,
    stage: str,
    inputs: Sequence[Path],
    outputs: Union[Sequence[Path], Callable[[], Sequence[Path]]],
    parameters: Mapping[str, Any],
    runtime: Mapping[str, Any],
    force: bool,
    action: Callable[[], None],
) -> Dict[str, Any]:
    fingerprint = stage_fingerprint(
        stage,
        work,
        implementation_files=_cache_implementation_files(),
        input_files=inputs,
        parameters=parameters,
        runtime=runtime,
    )
    decision = cache_decision(read_state(state_path), stage, fingerprint, work, force=force)
    if decision["reusable"]:
        return {
            "id": stage, "status": "reused", "cacheKey": fingerprint["cacheKey"],
            "cacheReason": decision["reason"], "durationMs": 0,
        }
    save_result(state_path, work, stage, fingerprint, status="running")
    started = time.monotonic()
    try:
        action()
        output_values = list(outputs() if callable(outputs) else outputs)
        for output in output_values:
            if not output.is_file() or output.is_symlink():
                raise ContractError(f"Finalisierungsstufe '{stage}' erzeugte nicht das erwartete reguläre Artefakt: {output}")
        duration = max(0, int(round((time.monotonic() - started) * 1000)))
        save_result(state_path, work, stage, fingerprint, output_files=output_values, duration_ms=duration)
        return {
            "id": stage, "status": "executed", "cacheKey": fingerprint["cacheKey"],
            "cacheReason": decision["reason"], "durationMs": duration,
        }
    except Exception as exc:
        duration = max(0, int(round((time.monotonic() - started) * 1000)))
        failure = _failure_metadata(stage, exc)
        save_result(state_path, work, stage, fingerprint, duration_ms=duration, status="failed", failure=failure)
        raise ContractError(f"Finalisierungsschritt '{stage}' fehlgeschlagen: {failure['message']}") from exc


def pdf(ctx: Any, args: Mapping[str, Any]) -> int:
    folder, root = _safe_folder(Path(str(args["ordner"])))
    order_path = _path(args, "auftrag_path")
    order: Optional[Mapping[str, Any]] = None
    if order_path is not None:
        order_path = safe_path(order_path, root, must_exist=True, kind="file")
        value = read_json(order_path)
        if not isinstance(value, dict):
            raise ContractError("Bewerbungsauftrag ist kein JSON-Objekt.")
        order = value
    _run_core(ctx, "pruefen", {"ordner": str(folder), **({"auftrag_path": str(order_path)} if order_path else {})})
    if bool(_arg(args, "mit_layoutcheck", False)):
        layout(ctx, {
            "ordner": str(folder),
            "browser": _arg(args, "browser", "auto"),
            "browser_executable_path": _arg(args, "browser_executable_path", None),
            "timeout_seconds": _arg(args, "timeout_seconds", 60),
        })
    documents = _selected_html(folder, order)
    output = _work_output(folder, "PDF-Export", _path(args, "output_root"), root)
    report_path = _report_path(output, _path(args, "bericht_path"), "PDF-Export-Bericht.json")
    final_paths = [safe_path(document.with_suffix(".pdf"), folder, kind="file") for document in documents]
    if bool(_arg(args, "nicht_ueberschreiben", False)) and any(value.exists() for value in final_paths):
        raise ContractError("Mindestens eine PDF existiert bereits und --nicht-ueberschreiben ist gesetzt.")
    snapshots = []
    for document in documents:
        targets, link_errors = candidate_link_contract(read_text(document))
        if link_errors:
            raise ContractError(f"HTML-Linkvertrag ist vor dem PDF-Export verletzt: {document.name}: {' | '.join(link_errors)}")
        snapshots.append((document, sha256_file(document), targets))
    browser = browser_candidates(
        str(_arg(args, "browser", "auto")),
        str(_arg(args, "browser_executable_path", "")) or None,
        False,
        True,
    )
    if not browser:
        raise ContractError("Kein Chromium-Browser für den PDF-Export gefunden.")
    timeout = int(_arg(args, "timeout_seconds", 60))
    minimum = int(_arg(args, "min_pdf_bytes", 5000))
    temp_root = _browser_temp(root)
    errors: List[str] = []
    for candidate in browser:
        run = Path(tempfile.mkdtemp(prefix="pdf-export-", dir=str(temp_root)))
        try:
            staged: List[Tuple[Path, Path, Path, str, List[str], Dict[str, Any]]] = []
            for index, (document, expected_hash, expected_targets) in enumerate(snapshots):
                temporary = run / f"document-{index + 1}.pdf"
                print_html(candidate, document, temporary, timeout, temp_root, minimum)
                link_verification = verify_pdf_link_targets(temporary, expected_targets)
                if not link_verification["passed"]:
                    raise BrowserError(
                        f"PDF-Linkprüfung fehlgeschlagen für {document.name}: "
                        f"fehlend={link_verification['missingTargets']}, zusätzlich={link_verification['unexpectedTargets']}"
                    )
                staged.append((document, final_paths[index], temporary, expected_hash, expected_targets, link_verification))
            if any(sha256_file(document) != expected for document, _, _, expected, _, _ in staged):
                raise BrowserError("HTML-Datei wurde während des PDF-Exports verändert.")
            backups: List[Tuple[Path, Path]] = []
            published: List[Path] = []
            try:
                for _, target, _, _, _, _ in staged:
                    if target.exists():
                        backup = run / ("backup-" + target.name)
                        os.replace(target, backup)
                        backups.append((target, backup))
                for _, target, temporary, _, _, _ in staged:
                    os.replace(temporary, target)
                    published.append(target)
                results = [{
                    "htmlFile": document.name,
                    "htmlSha256": expected,
                    "pdfFile": target.name,
                    "pdfPath": str(target),
                    "pdfSha256": sha256_file(target),
                    "pdfBytes": target.stat().st_size,
                    "pages": pdf_page_count(target),
                    "mediaBox": pdf_media_box_summary(target),
                    "linkVerification": {**link_verification, "pdfSha256": sha256_file(target)},
                } for document, target, _, expected, _, link_verification in staged]
                write_atomic_json(report_path, {
                    "schemaVersion": 2,
                    "exportedAtUtc": utc_now(),
                    "runtime": runtime_fingerprint(candidate),
                    "browser": candidate.name,
                    "sourceFolder": str(folder),
                    "results": results,
                })
            except Exception:
                for target in published:
                    try:
                        target.unlink()
                    except FileNotFoundError:
                        pass
                for target, backup in backups:
                    if backup.exists():
                        os.replace(backup, target)
                raise
            _emit(ctx, f"[OK] PDF-Export erfolgreich mit Browser: {candidate.name}")
            _emit(ctx, f"[OK] PDF-Export-Bericht geschrieben: {report_path}")
            return 0
        except (OSError, BrowserError, ValueError) as exc:
            errors.append(f"{candidate.name}: {exc}")
        finally:
            shutil.rmtree(run, ignore_errors=True)
    raise ContractError("PDF-Export fehlgeschlagen: " + " | ".join(errors))


def _markdown_fields(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    for line in read_text(path).splitlines():
        match = re.match(r"^\s*-\s*([^:]+):\s*(.*)$", line)
        if match and match.group(1).strip() not in values:
            values[match.group(1).strip()] = match.group(2).strip()
    return values


def _html_text(value: str) -> str:
    text = re.sub(r"(?is)<head\b[^>]*>.*?</head>", " ", value)
    text = re.sub(r"(?is)<(?:script|style|noscript|template)\b[^>]*>.*?</(?:script|style|noscript|template)>", " ", text)
    text = re.sub(r"(?i)<br\s*/?>|</(?:p|div|li|h[1-6]|section|article|header|footer|main|tr)\s*>", "\n", text)
    return html_module.unescape(re.sub(r"(?s)<[^>]+>", " ", text))


def _normalize_text(value: str) -> str:
    value = html_module.unescape(value)
    value = unicodedata.normalize("NFC", value).replace("\u00a0", " ")
    for source in "‐‑–—−":
        value = value.replace(source, "-")
    for source, target in (("ﬀ", "ff"), ("ﬁ", "fi"), ("ﬂ", "fl"), ("ﬃ", "ffi"), ("ﬄ", "ffl")):
        value = value.replace(source, target)
    return re.sub(r"\s+", " ", value).strip().lower()


_TOKEN = re.compile(r"(?:\.[^\W_][\w+#._-]*|[^\W_]+(?:[._-][^\W_]+)*[+#]?)", re.UNICODE)


def _tokens(value: str) -> List[str]:
    return _TOKEN.findall(_normalize_text(value))


def _similarity(source_text: str, extracted_text: str) -> Dict[str, Any]:
    source = _tokens(source_text)
    actual = _tokens(extracted_text)
    source_counts: Dict[str, int] = {}
    actual_counts: Dict[str, int] = {}
    for value in source:
        source_counts[value] = source_counts.get(value, 0) + 1
    for value in actual:
        actual_counts[value] = actual_counts.get(value, 0) + 1
    matched = sum(min(count, actual_counts.get(token, 0)) for token, count in source_counts.items())
    missing = [{"token": token, "count": count - actual_counts.get(token, 0)} for token, count in source_counts.items() if actual_counts.get(token, 0) < count]

    def coverage(size: int) -> float:
        wanted: Dict[Tuple[str, ...], int] = {}
        found: Dict[Tuple[str, ...], int] = {}
        for index in range(max(0, len(source) - size + 1)):
            key = tuple(source[index : index + size])
            wanted[key] = wanted.get(key, 0) + 1
        for index in range(max(0, len(actual) - size + 1)):
            key = tuple(actual[index : index + size])
            found[key] = found.get(key, 0) + 1
        total = sum(wanted.values())
        hit = sum(min(count, found.get(key, 0)) for key, count in wanted.items())
        return 100.0 if total == 0 else round(100.0 * hit / total, 2)

    token_coverage = 100.0 if not source else round(100.0 * matched / len(source), 2)
    bigram = coverage(2)
    trigram = coverage(3)
    short = len(source) < 25
    thresholds = {"token": 100.0 if short else 98.0, "bigram": 100.0 if short else 95.0, "trigram": 100.0 if short else 90.0}
    return {
        "sourceTokenCount": len(source), "extractedTokenCount": len(actual),
        "tokenCoveragePercent": token_coverage,
        "orderedBigramCoveragePercent": bigram,
        "orderedTrigramCoveragePercent": trigram,
        "missingTokens": missing, "thresholds": thresholds,
        "passed": token_coverage >= thresholds["token"] and bigram >= thresholds["bigram"] and trigram >= thresholds["trigram"],
    }


def ats(ctx: Any, args: Mapping[str, Any]) -> int:
    folder, root = _safe_folder(Path(str(args["ordner"])))
    order_path = safe_path(Path(str(args["auftrag_path"])), root, must_exist=True, kind="file")
    order = read_json(order_path)
    if not isinstance(order, dict):
        raise ContractError("Bewerbungsauftrag ist kein JSON-Objekt.")
    documents = _selected_html(folder, order)
    pdfs = [safe_path(value.with_suffix(".pdf"), folder, must_exist=True, kind="file") for value in documents]
    private_root = root.parent
    stammdaten = _path(args, "stammdaten_path", private_root / "Daten" / "01_PERSOENLICHE_DATEN.md")
    assert stammdaten is not None
    stammdaten = safe_path(stammdaten, private_root, must_exist=True, kind="file")
    report_path = _path(args, "bericht_path")
    pdf_report_path = _path(args, "pdf_export_bericht_path")
    report_root = folder.parent if folder.name == "Kandidat" else folder
    if report_path is not None:
        report_path = safe_path(report_path, report_root, kind="file")
        if pdf_report_path is None and folder.name == "Kandidat":
            default = folder.parent / "PDF-Export" / "PDF-Export-Bericht.json"
            if default.is_file():
                pdf_report_path = default
        if pdf_report_path is None:
            raise ContractError("Ein ATS-Prüfbericht erfordert den zugehörigen PDF-Export-Bericht mit Browser-Fingerprint.")
        pdf_report_path = safe_path(pdf_report_path, root, must_exist=True, kind="file")
        export = read_json(pdf_report_path)
        export_results = export.get("results") if isinstance(export, dict) else None
        expected = [(document.name, sha256_file(document), pdf_path.name, sha256_file(pdf_path)) for document, pdf_path in zip(documents, pdfs)]
        if not isinstance(export, dict) or export.get("schemaVersion") not in (1, 2) or not isinstance(export_results, list):
            raise ContractError("PDF-Export-Bericht besitzt kein gültiges Ergebnisformat für die ATS-Bindung.")
        if len(export_results) != len(expected):
            raise ContractError("PDF-Export-Bericht deckt nicht exakt die erwarteten ATS-Artefakte ab.")
        for html_name, html_hash, pdf_name, pdf_hash in expected:
            matches = [value for value in export_results if isinstance(value, dict) and value.get("htmlFile") == html_name and value.get("pdfFile") == pdf_name]
            if len(matches) != 1 or str(matches[0].get("htmlSha256", "")).upper() != html_hash or str(matches[0].get("pdfSha256", "")).upper() != pdf_hash:
                raise ContractError(f"PDF-Export-Bericht ist nicht exakt an die aktuellen ATS-Artefakte gebunden: {pdf_name}")
            if export.get("schemaVersion") == 2:
                links = matches[0].get("linkVerification")
                if not isinstance(links, dict) or links.get("passed") is not True or str(links.get("pdfSha256", "")).upper() != pdf_hash:
                    raise ContractError(f"PDF-Export-Bericht enthält keinen gültigen Linknachweis: {pdf_name}")
        runtime = export.get("runtime")
        if not isinstance(runtime, dict) or runtime.get("schemaVersion") != 1 or not isinstance(runtime.get("browser"), dict):
            raise ContractError("PDF-Export-Bericht enthält keinen vollständigen Runtime-/Browser-Fingerprint.")
        _assert_runtime_current(runtime, {}, True)
    fields = _markdown_fields(stammdaten)
    full_name = fields.get("Vollständiger Name", "")
    if not full_name:
        raise ContractError("Stammdaten enthalten keinen Wert für 'Vollständiger Name'.")
    scope = _document_scope(order)
    minimum = int(_arg(args, "min_textabdeckung_prozent", 70))
    errors: List[str] = []
    warnings: List[str] = []
    oks: List[str] = []
    results: List[Dict[str, Any]] = []
    for document, pdf_path in zip(documents, pdfs):
        try:
            source_text = _html_text(read_text(document))
            extracted = extract_pdf_text(pdf_path)
            similarity = _similarity(source_text, extracted)
            coverage = similarity["tokenCoveragePercent"]
            required = [full_name]
            if not (document.name.startswith("Lebenslauf -") and scope["lebenslauf"] == "universal_unveraendert"):
                required.append(str(order.get("rolle", "")))
            if document.name.startswith("Anschreiben -"):
                required.append(str(order.get("firma", "")))
            if document.name.startswith("Lebenslauf -"):
                required.extend(sorted(set(re.findall(r"(?i)\b(?:0[1-9]|1[0-2])/\d{4}\s*[-–—]\s*(?:(?:0[1-9]|1[0-2])/\d{4}|fortlaufend)\b", source_text))))
            missing_required = [value for value in required if value and _normalize_text(value) not in _normalize_text(extracted)]
            if coverage < minimum:
                errors.append(f"{pdf_path.name}: Textabdeckung ist zu gering ({coverage} % statt mindestens {minimum} %).")
            if not similarity["passed"]:
                errors.append(f"{pdf_path.name}: Token-/N-Gramm-Abgleich unterschreitet die Vertragsschwellen.")
            elif coverage < 99.5 or similarity["orderedBigramCoveragePercent"] < 98.0 or similarity["orderedTrigramCoveragePercent"] < 95.0:
                warnings.append(f"{pdf_path.name}: geringe, tolerierte Extraktionsabweichung im Token-/N-Gramm-Abgleich.")
            if missing_required:
                errors.append(f"{pdf_path.name}: Pflichttext fehlt in der PDF-Textschicht: {', '.join(missing_required)}")
            normalized = _normalize_text(extracted)
            name_index = normalized.find(_normalize_text(full_name))
            role_required = not (document.name.startswith("Lebenslauf -") and scope["lebenslauf"] == "universal_unveraendert")
            role_index = normalized.find(_normalize_text(str(order.get("rolle", ""))))
            reading_order = name_index >= 0 and name_index < max(80, int(len(normalized) * 0.3))
            if role_required:
                reading_order = reading_order and role_index >= name_index and role_index < max(80, int(len(normalized) * 0.3))
            if not reading_order:
                warnings.append(f"{pdf_path.name}: Name beziehungsweise Zielrolle liegt in der extrahierten Lesereihenfolge nicht früh genug.")
            if coverage >= minimum and not missing_required:
                oks.append(f"{pdf_path.name}: Unicode-Textschicht extrahierbar, Pflichttexte vorhanden, Abdeckung {coverage} %.")
            results.append({
                "htmlFile": document.name, "htmlSha256": sha256_file(document),
                "pdfFile": pdf_path.name, "pdfSha256": sha256_file(pdf_path),
                "sourceComparableCharacters": len(re.sub(r"\s+", "", _normalize_text(source_text))),
                "extractedComparableCharacters": len(re.sub(r"\s+", "", _normalize_text(extracted))),
                "sourceTokenCount": similarity["sourceTokenCount"], "extractedTokenCount": similarity["extractedTokenCount"],
                "textCoveragePercent": coverage, "tokenCoveragePercent": coverage,
                "orderedBigramCoveragePercent": similarity["orderedBigramCoveragePercent"],
                "orderedTrigramCoveragePercent": similarity["orderedTrigramCoveragePercent"],
                "tokenThresholds": similarity["thresholds"], "shortDocument": similarity["sourceTokenCount"] < 25,
                "tokenComparisonPassed": similarity["passed"], "missingTokens": similarity["missingTokens"],
                "missingRequiredText": missing_required, "readingOrderPlausible": reading_order,
                "extractionEngine": "interner_tounicode_parser",
            })
        except (OSError, BrowserError, ValueError) as exc:
            errors.append(f"{pdf_path.name}: ATS-Textprüfung fehlgeschlagen: {exc}")
            results.append({
                "htmlFile": document.name, "htmlSha256": sha256_file(document),
                "pdfFile": pdf_path.name, "pdfSha256": sha256_file(pdf_path),
                "extractionEngine": "interner_tounicode_parser", "extractionError": str(exc),
            })
    if report_path is not None:
        write_atomic_json(report_path, {
            "schemaVersion": 2, "checkedAtUtc": utc_now(), "runtime": runtime,
            "folder": str(folder), "status": "fehler" if errors else ("warnung" if warnings else "ok"),
            "errors": errors, "warnings": warnings, "oks": oks, "results": results,
        })
    for value in errors:
        _emit(ctx, f"[FEHLER] {value}", error=True)
    for value in warnings:
        _emit(ctx, f"[WARNUNG] {value}")
    for value in oks:
        _emit(ctx, f"[OK] {value}")
    if errors:
        raise ContractError(f"ATS-Prüfung meldet {len(errors)} Fehler.")
    _emit(ctx, "ERGEBNIS: OK")
    return 0


def _record(path: Path, root: Optional[Path] = None) -> Dict[str, Any]:
    stat = path.stat()
    return {
        "path": path.relative_to(root).as_posix() if root is not None else str(path),
        "bytes": stat.st_size,
        "sha256": sha256_file(path),
    }


def _regular_files(folder: Path, pattern: str = "*") -> List[Path]:
    values: List[Path] = []
    for path in sorted(folder.glob(pattern), key=lambda item: item.name):
        if path.is_symlink():
            raise CliUsageError(f"Symbolischer Link ist als Workflowartefakt nicht zulässig: {path}")
        if path.is_file():
            values.append(path)
    return values


def _not_required(path: Path, kind: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    write_atomic_json(path, {
        "schemaVersion": 1,
        "checkedAtUtc": utc_now(),
        "runtime": runtime_fingerprint(),
        "status": "nicht_erforderlich",
        "kind": kind,
        "reason": "Der gewählte Dokumentumfang enthält kein HTML-/PDF-Dokument.",
        "results": [],
    })


def _source_record(path: Path, root: Optional[Path] = None) -> Dict[str, Any]:
    value = _record(path, root)
    value["name"] = path.name
    return value


def _assert_source_current(record: Mapping[str, Any], fallback_root: Path) -> None:
    raw = str(record.get("path", ""))
    path = Path(raw)
    if not path.is_absolute():
        path = fallback_root / path
    if not path.is_file() or path.is_symlink():
        raise ContractError(f"Gebundene Quelldatei fehlt oder ist unsicher: {raw}")
    if path.stat().st_size != int(record.get("bytes", -1)) or sha256_file(path) != str(record.get("sha256", "")).upper():
        raise ContractError(f"Gebundene Quelldatei wurde seit der Vorbereitung verändert: {raw}")


def _assert_runtime_current(prepared: Any, args: Mapping[str, Any], require_browser: bool) -> None:
    if not isinstance(prepared, dict) or prepared.get("schemaVersion") != 1:
        raise ContractError("Technischer Bericht enthält keinen unterstützten Runtime-Fingerprint.")
    current = runtime_fingerprint()
    for key in ("os", "architecture", "distributionId", "distributionVersion", "wsl", "pythonVersion"):
        if prepared.get(key) != current.get(key):
            raise ContractError("Technischer Nachweis stammt aus einer anderen Plattform oder Kernruntime; erneut vorbereiten.")
    prepared_core = prepared.get("coreRuntime")
    current_core = current.get("coreRuntime")
    if not isinstance(prepared_core, dict) or not isinstance(current_core, dict):
        raise ContractError("Technischer Nachweis enthält keine vollständige Kernruntime-Bindung.")
    for key in ("kind", "version", "executable"):
        if prepared_core.get(key) != current_core.get(key):
            raise ContractError("Technischer Nachweis stammt aus einer anderen Python-Runtime; erneut vorbereiten.")
    # Neue Fingerprints beschreiben den Kern generisch. Alte Schema-1-Berichte
    # ohne diese Zusatzfelder bleiben lesbar, vorhandene Felder dürfen aber
    # nicht von der tatsächlich verwendeten Linux-Python-Runtime abweichen.
    for key in ("platform", "language", "path"):
        if key in prepared_core and prepared_core.get(key) != current_core.get(key):
            raise ContractError("Technischer Nachweis stammt aus einer anderen Python-Runtime; erneut vorbereiten.")
    if require_browser:
        bound = prepared.get("browser")
        if not isinstance(bound, dict):
            raise ContractError("Technischer Bericht enthält keinen gebundenen Browser-Fingerprint.")
        requested = str(_arg(args, "browser", bound.get("name") or "auto"))
        explicit_value = _arg(args, "browser_executable_path", None) or bound.get("executable")
        try:
            browser = resolve_browser(requested, str(explicit_value) if explicit_value else None, False, True)
        except (BrowserError, OSError, ValueError) as exc:
            raise ContractError("Gebundener Browser ist nicht mehr sicher verfügbar; erneut vorbereiten.") from exc
        current = runtime_fingerprint(browser)
        prepared_browser = prepared.get("browser")
        current_browser = current.get("browser")
        if not isinstance(prepared_browser, dict) or not isinstance(current_browser, dict):
            raise ContractError("Technischer Nachweis enthält keine vollständige Browserbindung.")
        for key in ("name", "version", "executable"):
            if prepared_browser.get(key) != current_browser.get(key):
                raise ContractError("Technischer Nachweis stammt aus einem anderen Browserlauf; erneut vorbereiten.")


def _candidate_groups(candidate: Path, layout_folder: Path, work: Path) -> Dict[str, List[Dict[str, Any]]]:
    candidate_files = _regular_files(candidate)
    return {
        "html": [_record(path, work) for path in candidate_files if path.suffix.lower() == ".html"],
        "pdf": [_record(path, work) for path in candidate_files if path.suffix.lower() == ".pdf"],
        "screenshots": [_record(path, work) for path in _regular_files(layout_folder, "*.png")] if layout_folder.is_dir() else [],
        "candidate": [_record(path, work) for path in candidate_files],
    }


def _validated_density_exception(exception_reason: Any) -> Optional[str]:
    """Validate the exception form before any browser process is started."""

    reason = re.sub(r"\s+", " ", str(exception_reason or "").strip())
    if not reason:
        return None
    required_labels = ("seite:", "beleglage:", "einseiter:")
    if len(reason) < 120 or any(label not in reason.lower() for label in required_labels):
        raise CliUsageError(
            "--dichteausnahme-begruendung benötigt mindestens 120 Zeichen und die Abschnitte "
            "'Seite:', 'Beleglage:' und 'Einseiter:'."
        )
    return reason


def _density_gate(layout_data: Mapping[str, Any], exception_reason: Optional[str]) -> Dict[str, Any]:
    findings = []
    for value in layout_data.get("results", []) if isinstance(layout_data, Mapping) else []:
        if not isinstance(value, Mapping) or not str(value.get("htmlFile", "")).startswith("Lebenslauf -"):
            continue
        if value.get("pageCount") != 2:
            continue
        whitespace = value.get("bottomWhitespaceMm")
        if isinstance(whitespace, (int, float)) and whitespace > 55.0:
            findings.append({
                "htmlFile": value.get("htmlFile"), "pageNumber": value.get("pageNumber"), "pageCount": value.get("pageCount"),
                "bottomWhitespaceMm": whitespace, "thresholdMm": 55.0,
                "warning": value.get("densityWarning") or "Ungewöhnlich viel freie Fläche im nutzbaren Inhaltsbereich.",
            })
    reason = exception_reason
    if not findings:
        if reason:
            raise CliUsageError("--dichteausnahme-begruendung ist nur bei einer tatsächlichen Dichteblockade zulässig.")
        return {"status": "nicht_ausgeloest", "findings": [], "exceptionReason": None}
    if not reason:
        return {"status": "ueberarbeitung_erforderlich", "findings": findings, "exceptionReason": None}
    return {"status": "ausnahme_bestaetigt", "findings": findings, "exceptionReason": reason}


def _quality_evidence(candidate: Path) -> None:
    for name in ("Stellenbeschreibung.md", "Analyse.md", "Qualitaetscheck.md", "Druck-Hinweis.md"):
        path = safe_path(candidate / name, candidate, must_exist=True, kind="file")
        value = read_text(path)
        if len(value) < 80 or re.search(r"(?i)\[ergänzen|\bTODO\b|DOKUMENT NOCH NICHT FINAL|\bDUMMY\b", value):
            raise ContractError(f"Interner Nachweis ist noch nicht fachlich abgeschlossen: {name}")


def _normal_final_paths(work: Path, args: Mapping[str, Any]) -> Dict[str, Any]:
    context = infer_work_context(work, universal=False)
    root = context.applications_root
    candidate = safe_path(work / "Kandidat", root, must_exist=True, kind="dir")
    order_path = safe_path(work / "Bewerbungsauftrag.json", root, must_exist=True, kind="file")
    matrix_path = safe_path(work / "Anforderungsmatrix.json", root, must_exist=True, kind="file")
    private_root = root.parent
    stammdaten = _path(args, "stammdaten_path", private_root / "Daten" / "01_PERSOENLICHE_DATEN.md")
    profil = _path(args, "profil_path", private_root / "Daten" / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md")
    assert stammdaten is not None and profil is not None
    stammdaten = safe_path(stammdaten, private_root, must_exist=True, kind="file")
    profil = safe_path(profil, private_root, must_exist=True, kind="file")
    return {
        "context": context, "root": root, "private": private_root, "work": work,
        "candidate": candidate, "order_path": order_path, "matrix_path": matrix_path,
        "stammdaten": stammdaten, "profil": profil,
        "layout": safe_path(work / "Layoutcheck", root, kind="dir"),
        "pdf_dir": safe_path(work / "PDF-Export", root, kind="dir"),
        "layout_report": safe_path(work / "Layoutcheck" / "Layoutcheck-Bericht.json", root, kind="file"),
        "pdf_report": safe_path(work / "PDF-Export" / "PDF-Export-Bericht.json", root, kind="file"),
        "ats_report": safe_path(work / "ATS-Pruefbericht.json", root, kind="file"),
        "final_report": safe_path(work / "Finalisierungsbericht.json", root, kind="file"),
        "check_state": safe_path(work / "Pruefstand.json", root, kind="file"),
        "target": safe_path(context.target, root, kind="dir"),
    }


def _normal_prepare(ctx: Any, paths: Mapping[str, Any], args: Mapping[str, Any]) -> int:
    work: Path = paths["work"]
    candidate: Path = paths["candidate"]
    order = read_json(paths["order_path"])
    matrix = read_json(paths["matrix_path"])
    if not isinstance(order, dict) or not isinstance(matrix, dict):
        raise ContractError("Bewerbungsauftrag und Anforderungsmatrix müssen JSON-Objekte sein.")
    scope = _document_scope(order)
    expected_html = int(scope["lebenslauf"] != "nicht_enthalten") + int(scope["anschreiben"])
    density_exception = _validated_density_exception(_arg(args, "dichteausnahme_begruendung", None))
    _quality_evidence(candidate)
    force = bool(_arg(args, "neu_pruefen", False))
    base_runtime = runtime_fingerprint()
    stage_runs: List[Dict[str, Any]] = []
    stammdaten_report = work / "Stammdaten-Pruefbericht.json"
    content_report = work / "Inhalts-Pruefbericht.json"
    candidate_inputs = _regular_files(candidate)
    evidence = work / "Evidenzindex.json"

    stage_runs.append(_cached_stage(
        ctx, work=work, state_path=paths["check_state"], stage="dialog",
        inputs=[paths["order_path"], paths["stammdaten"], paths["profil"]], outputs=[],
        parameters={"fuerDokumenterstellung": True}, runtime=base_runtime, force=force,
        action=lambda: _run_core(ctx, "dialog-pruefen", {
            "auftrag_path": paths["order_path"], "stammdaten_path": paths["stammdaten"],
            "profil_path": paths["profil"], "fuer_dokumenterstellung": True,
        }),
    ))
    stage_runs.append(_cached_stage(
        ctx, work=work, state_path=paths["check_state"], stage="stammdaten",
        inputs=[paths["order_path"], paths["stammdaten"]], outputs=[stammdaten_report],
        parameters={"ungeklaerteLogistikAlsFehler": True}, runtime=base_runtime, force=force,
        action=lambda: _run_core(ctx, "stammdaten", {
            "stammdaten_path": paths["stammdaten"], "bewerbungsauftrag_path": paths["order_path"],
            "ungeklaerte_logistik_als_fehler": True, "bericht_path": stammdaten_report,
        }),
    ))
    stage_runs.append(_cached_stage(
        ctx, work=work, state_path=paths["check_state"], stage="statisch",
        inputs=[paths["order_path"], *candidate_inputs], outputs=[], parameters={}, runtime=base_runtime, force=force,
        action=lambda: _run_core(ctx, "pruefen", {"ordner": candidate, "auftrag_path": paths["order_path"]}),
    ))
    content_inputs = [paths["order_path"], paths["stammdaten"], paths["profil"], paths["matrix_path"], *candidate_inputs]
    if evidence.is_file():
        content_inputs.append(evidence)
    stage_runs.append(_cached_stage(
        ctx, work=work, state_path=paths["check_state"], stage="inhalt",
        inputs=content_inputs, outputs=[content_report], parameters={}, runtime=base_runtime, force=force,
        action=lambda: _run_core(ctx, "inhalt", {
            "ordner": candidate, "stammdaten_path": paths["stammdaten"], "profil_path": paths["profil"],
            "auftrag_path": paths["order_path"], "anforderungsmatrix_path": paths["matrix_path"],
            "bericht_path": content_report,
        }),
    ))

    timeout = int(_arg(args, "timeout_seconds", 60))
    browser_args: Dict[str, Any] = {"timeout_seconds": timeout}
    if expected_html:
        requested = str(_arg(args, "browser", "auto"))
        explicit = _arg(args, "browser_executable_path", None)
        browser_info = resolve_browser(requested, str(explicit) if explicit else None, False, True)
        browser_runtime = runtime_fingerprint(browser_info)
        browser_args.update({"browser": browser_info.name, "browser_executable_path": str(browser_info.path)})
        try:
            check_chromium_readiness(browser_info, timeout, _browser_temp(paths["root"]))
        except BrowserError as exc:
            raise ContractError(
                "Browser-Vorprüfung fehlgeschlagen. Bitte die lokale Chromium-Sandbox beziehungsweise Browserfreigabe "
                f"bereitstellen; es wurde kein unsicherer Ersatzmodus verwendet. Ursache: {exc}"
            ) from exc
        html_inputs = _regular_files(candidate, "*.html")
        stage_runs.append(_cached_stage(
            ctx, work=work, state_path=paths["check_state"], stage="layout",
            inputs=html_inputs,
            outputs=lambda: [paths["layout_report"], *_regular_files(paths["layout"], "*.png")],
            parameters={"browser": browser_info.name, "browserVersion": browser_info.version, "timeoutSeconds": timeout},
            runtime=browser_runtime, force=force,
            action=lambda: layout(ctx, {"ordner": candidate, "output_root": paths["layout"], "bericht_path": paths["layout_report"], **browser_args}),
        ))
    else:
        paths["layout"].mkdir(parents=True, exist_ok=True)
        paths["pdf_dir"].mkdir(parents=True, exist_ok=True)
        for stage, output, kind in (
            ("layout", paths["layout_report"], "layoutcheck"),
            ("pdf", paths["pdf_report"], "pdf_export"),
            ("ats", paths["ats_report"], "ats_pdf"),
        ):
            stage_runs.append(_cached_stage(
                ctx, work=work, state_path=paths["check_state"], stage=stage,
                inputs=[paths["order_path"]], outputs=[output], parameters={"notRequired": True},
                runtime=base_runtime, force=force,
                action=lambda output=output, kind=kind: _not_required(output, kind),
            ))

    groups = _candidate_groups(candidate, paths["layout"], work)
    expected_screenshots = sum(len(html_pages(read_text(path))) for path in _regular_files(candidate, "*.html"))
    if len(groups["html"]) != expected_html or len(groups["screenshots"]) != expected_screenshots:
        raise ContractError(
            f"Vorbereitung erzeugte nicht den erwarteten Layoutumfang: HTML {len(groups['html'])} statt {expected_html}, "
            f"Screenshots {len(groups['screenshots'])} statt {expected_screenshots}."
        )
    layout_data = read_json(paths["layout_report"])
    warnings = [] if not isinstance(layout_data, dict) else [
        f"{value.get('htmlFile')}, Seite {value.get('pageNumber')} von {value.get('pageCount')}: {value.get('densityWarning')}"
        for value in layout_data.get("results", []) if isinstance(value, dict) and value.get("densityWarning")
    ]
    density_gate = _density_gate(layout_data, density_exception)
    runtime = layout_data.get("runtime") if isinstance(layout_data, dict) else runtime_fingerprint()
    source_inputs: Dict[str, Any] = {
        "stammdaten": _source_record(paths["stammdaten"]),
        "profil": _source_record(paths["profil"]),
        "bewerbungsauftrag": _source_record(paths["order_path"], work),
        "anforderungsmatrix": _source_record(paths["matrix_path"], work),
    }
    if evidence.is_file():
        source_inputs["evidenzindex"] = _source_record(evidence, work)
    if density_gate["status"] == "ueberarbeitung_erforderlich":
        # Older PDFs must not be attached to a newly blocked preparation report.
        blocked_groups = dict(groups)
        blocked_groups["pdf"] = []
        report = {
            "schemaVersion": 8, "status": "layout_ueberarbeitung_erforderlich", "preparedAtUtc": utc_now(),
            "runtime": runtime, "workFolder": str(work), "candidateFolder": str(candidate), "targetFolder": str(paths["target"]),
            "layoutReport": str(paths["layout_report"]), "layoutReportArtifact": _record(paths["layout_report"], work),
            "pdfReport": None, "atsReport": None, "expectedScreenshots": expected_screenshots, "documentScope": scope,
            "personalReview": "png_sichtpruefung" if expected_screenshots else "textpruefung", "layoutWarnings": warnings,
            "layoutGate": density_gate,
            "tokenUsageReport": {"available": False, "reason": "Agentenlaufzeit stellte keine maschinenlesbaren Nutzungsdaten bereit."},
            "stageOrder": list(STAGE_ORDER), "stageRuns": stage_runs, "sourceInputs": source_inputs, "artifacts": blocked_groups,
        }
        write_atomic_json(paths["final_report"], report)
        _emit(ctx, "[FEHLER] Technische Vorbereitung gesperrt: Der zweiseitige Lebenslauf enthält ungewöhnlich viel freie Fläche.")
        for finding in density_gate["findings"]:
            _emit(ctx, "- %s, Seite %s: %s mm freie Fläche (Grenze %s mm)" % (
                finding["htmlFile"], finding["pageNumber"], finding["bottomWhitespaceMm"], finding["thresholdMm"]
            ))
        _emit(ctx, "PDF-Export und ATS-Prüfung wurden nicht gestartet. Überarbeite die Seitenverteilung oder verwende eine konkrete --dichteausnahme-begruendung.")
        return 1

    if expected_html:
        layout_outputs = _regular_files(paths["layout"], "*.png")
        stage_runs.append(_cached_stage(
            ctx, work=work, state_path=paths["check_state"], stage="pdf",
            inputs=[paths["order_path"], *html_inputs, paths["layout_report"], *layout_outputs],
            outputs=lambda: [paths["pdf_report"], *_regular_files(candidate, "*.pdf")],
            parameters={"browser": browser_info.name, "browserVersion": browser_info.version, "timeoutSeconds": timeout},
            runtime=browser_runtime, force=force,
            action=lambda: pdf(ctx, {"ordner": candidate, "auftrag_path": paths["order_path"], "output_root": paths["pdf_dir"], "bericht_path": paths["pdf_report"], **browser_args}),
        ))
        pdf_outputs = _regular_files(candidate, "*.pdf")
        stage_runs.append(_cached_stage(
            ctx, work=work, state_path=paths["check_state"], stage="ats",
            inputs=[paths["order_path"], paths["stammdaten"], paths["pdf_report"], *pdf_outputs],
            outputs=[paths["ats_report"]], parameters={}, runtime=browser_runtime, force=force,
            action=lambda: ats(ctx, {
                "ordner": candidate, "stammdaten_path": paths["stammdaten"], "auftrag_path": paths["order_path"],
                "bericht_path": paths["ats_report"], "pdf_export_bericht_path": paths["pdf_report"],
            }),
        ))
        groups = _candidate_groups(candidate, paths["layout"], work)
        if len(groups["pdf"]) != expected_html:
            raise ContractError(f"Vorbereitung erzeugte nicht den erwarteten PDF-Umfang: {len(groups['pdf'])} statt {expected_html}.")
    report: Dict[str, Any] = {
        "schemaVersion": 8,
        "status": "layout_ueberarbeitung_erforderlich" if density_gate["status"] == "ueberarbeitung_erforderlich" else "bereit_zur_sichtpruefung",
        "preparedAtUtc": utc_now(),
        "runtime": runtime, "workFolder": str(work), "candidateFolder": str(candidate), "targetFolder": str(paths["target"]),
        "layoutReport": str(paths["layout_report"]), "layoutReportArtifact": _record(paths["layout_report"], work),
        "pdfReport": str(paths["pdf_report"]), "pdfReportArtifact": _record(paths["pdf_report"], work),
        "atsReport": str(paths["ats_report"]), "atsReportArtifact": _record(paths["ats_report"], work),
        "expectedScreenshots": expected_screenshots, "documentScope": scope,
        "personalReview": "png_sichtpruefung" if expected_screenshots else "textpruefung",
        "layoutWarnings": warnings,
        "layoutGate": density_gate,
        "tokenUsageReport": {"available": False, "reason": "Agentenlaufzeit stellte keine maschinenlesbaren Nutzungsdaten bereit."},
        "stageOrder": list(STAGE_ORDER),
        "stageRuns": stage_runs, "sourceInputs": source_inputs, "artifacts": groups,
    }
    if report["status"] == "bereit_zur_sichtpruefung":
        records = approval_records(report)
        report["approvalRequest"] = {
            "approvalId": new_approval_id(), "reviewKind": report["personalReview"],
            "artifactSetSha256": artifact_set_hash(records, work), "artifactCount": len(records), "createdAtUtc": utc_now(),
        }
    write_atomic_json(paths["final_report"], report)
    try:
        _run_core(ctx, "checkpoint", {"arbeitsordner": work, "schritt": "technische_vorbereitung_abgeschlossen"})
    except WorkflowError as exc:
        _emit(ctx, f"[WARNUNG] Checkpoint konnte nicht aktualisiert werden: {exc}")
    if density_gate["status"] == "ausnahme_bestaetigt":
        _emit(ctx, "[WARNUNG] Dichteausnahme ist für die persönliche Sichtprüfung dokumentiert.")
    _emit(ctx, "[OK] Technische Vorbereitung erfolgreich.")
    if expected_screenshots:
        for screenshot in _regular_files(paths["layout"], "*.png"):
            _emit(ctx, f"- {screenshot}")
    else:
        _emit(ctx, f"Prüfe die ausgewählten Textdateien persönlich: {candidate}")
    _emit(ctx, "Nach bestätigter persönlicher Prüfung die Freigabe speichern:")
    _emit(ctx, f"python3 Tools/bewerbung.py freigabe --arbeitsordner \"{work}\" --freigabe-id {report['approvalRequest']['approvalId']} --bestaetigt")
    return 0


def _read_approval(work: Path, report_path: Path, report: Mapping[str, Any]) -> Mapping[str, Any]:
    approval_path = safe_path(work / "Sichtfreigabe.json", work, must_exist=True, kind="file")
    approval = read_json(approval_path)
    if not isinstance(approval, dict) or approval.get("schemaVersion") != 1 or approval.get("kind") != "sichtfreigabe" or approval.get("humanConfirmation") is not True:
        raise ContractError("Sichtfreigabe besitzt kein gültiges bestätigtes Schema.")
    request = report.get("approvalRequest")
    if not isinstance(request, dict) or approval.get("approvalId") != request.get("approvalId") or approval.get("artifactSetSha256") != request.get("artifactSetSha256"):
        raise ContractError("Sichtfreigabe ist nicht an die aktuelle Freigabe-ID oder den aktuellen Artefaktsatz gebunden.")
    prepared = approval.get("preparedReport")
    if not isinstance(prepared, dict) or str(prepared.get("sha256", "")).upper() != sha256_file(report_path):
        raise ContractError("Sichtfreigabe gehört nicht zum aktuellen Finalisierungsbericht.")
    records = approval_records(report)
    assert_artifacts_current(records, work)
    if artifact_set_hash(records, work) != str(approval.get("artifactSetSha256", "")):
        raise ContractError("Artefaktsatz wurde seit der Sichtfreigabe verändert.")
    bound = approval.get("artifacts")
    if not isinstance(bound, list) or len(bound) != len(records):
        raise ContractError("Sichtfreigabe enthält nicht genau den vorbereiteten Artefaktsatz.")
    assert_artifacts_current(bound, work)
    if artifact_set_hash(bound, work) != str(approval.get("artifactSetSha256", "")):
        raise ContractError("Sichtfreigabe-Artefakthashes stimmen nicht mit dem gebundenen Satz überein.")
    return approval


def _manifest(stage: Path, order: Mapping[str, Any], source_inputs: Mapping[str, Any], approval: Mapping[str, Any]) -> Path:
    files = [_record(path, stage) for path in sorted(stage.rglob("*"), key=lambda item: item.as_posix()) if path.is_file()]
    manifest = {
        "schemaVersion": 1, "createdAtUtc": utc_now(), "firma": order.get("firma"), "rolle": order.get("rolle"),
        "dokumentumfang": _document_scope(order),
        "struktur": {"versand": "nur laut Dokumentumfang ausgewählte PDF-Anlagen und E-Mail-Nachricht", "intern": "HTML-Quellen, Analyse und Prüfdokumente"},
        "sourceInputs": {name: {"name": value.get("name") or Path(str(value.get("path", ""))).name, "sha256": value.get("sha256")} for name, value in source_inputs.items()},
        "personalReview": {"kind": approval.get("reviewKind"), "confirmed": True, "approvalId": approval.get("approvalId"), "note": approval.get("note", "")},
        "files": files,
    }
    target = stage / "Manifest.json"
    write_atomic_json(target, manifest)
    return target


def _install_directory(stage: Path, target: Path, replace: bool) -> None:
    backup = target.parent / (".backup-" + uuid.uuid4().hex)
    moved = False
    installed = False
    try:
        if target.exists():
            if not target.is_dir() or target.is_symlink():
                raise ContractError(f"Finaler Zielpfad ist kein sicherer Ordner: {target}")
            entries = list(target.iterdir())
            if entries and not replace:
                raise ContractError("Finaler Zielordner ist nicht leer. Verwende --ersetzen nur für eine bewusst neu geprüfte Veröffentlichung.")
            if entries:
                os.replace(target, backup)
                moved = True
            else:
                target.rmdir()
        os.replace(stage, target)
        installed = True
        if moved:
            shutil.rmtree(backup)
    except Exception:
        if installed and target.exists():
            shutil.rmtree(target, ignore_errors=True)
        if moved and backup.exists() and not target.exists():
            os.replace(backup, target)
        raise


def _normal_publish(ctx: Any, paths: Mapping[str, Any], args: Mapping[str, Any]) -> int:
    work: Path = paths["work"]
    report = read_json(paths["final_report"])
    if not isinstance(report, dict) or report.get("schemaVersion") not in (7, 8) or report.get("status") != "bereit_zur_sichtpruefung":
        raise ContractError("Finalisierungsbericht besitzt keinen aktuellen veröffentlichbaren Freigabestatus.")
    if report.get("workFolder") != str(work) or report.get("candidateFolder") != str(paths["candidate"]) or report.get("targetFolder") != str(paths["target"]):
        raise ContractError("Finalisierungsbericht gehört nicht zum aktuellen Arbeits- oder Zielordner.")
    expected_html = int(report.get("expectedScreenshots", 0)) > 0
    _assert_runtime_current(report.get("runtime"), args, expected_html)
    approval = _read_approval(work, paths["final_report"], report)
    note = re.sub(r"\s+", " ", str(approval.get("note", "")).strip())
    if report.get("layoutWarnings") and not note:
        raise ContractError("Layoutwarnungen erfordern eine konkrete Notiz in der Chat-bestätigten Sichtfreigabe.")
    source_inputs = report.get("sourceInputs")
    if not isinstance(source_inputs, dict):
        raise ContractError("Finalisierungsbericht enthält keine gebundenen Quellen.")
    for value in source_inputs.values():
        if not isinstance(value, dict):
            raise ContractError("Finalisierungsbericht enthält einen ungültigen Quellrecord.")
        _assert_source_current(value, work)
    _run_core(ctx, "dialog-pruefen", {
        "auftrag_path": paths["order_path"], "stammdaten_path": paths["stammdaten"],
        "profil_path": paths["profil"], "fuer_dokumenterstellung": True,
    })
    _run_core(ctx, "stammdaten", {
        "stammdaten_path": paths["stammdaten"], "bewerbungsauftrag_path": paths["order_path"],
        "ungeklaerte_logistik_als_fehler": True, "bericht_path": work / "Stammdaten-Pruefbericht.json",
    })
    order = read_json(paths["order_path"])
    if not isinstance(order, dict):
        raise ContractError("Bewerbungsauftrag ist kein JSON-Objekt.")
    company = paths["target"].parent
    stage = safe_path(company / (".publish-" + uuid.uuid4().hex), paths["root"], kind="dir")
    report_temp = safe_path(work / (".Finalisierungsbericht.publish-" + uuid.uuid4().hex + ".json"), paths["root"], kind="file")
    backup = safe_path(company / (".backup-" + uuid.uuid4().hex), paths["root"], kind="dir")
    target_backed_up = False
    target_was_empty = False
    target_installed = False
    report_installed = False
    try:
        shipping = stage / "Versand"
        internal = stage / "Intern"
        shipping.mkdir(parents=True)
        internal.mkdir()
        for source in _regular_files(paths["candidate"]):
            destination = shipping if source.suffix.lower() == ".pdf" or re.match(r"^Email-Nachricht--.+\.md$", source.name) else internal
            shutil.copy2(source, destination / source.name)
        manifest_path = _manifest(stage, order, source_inputs, approval)
        published = dict(report)
        published["status"] = "veroeffentlicht"
        published["publishedAtUtc"] = utc_now()
        published["publishedFolder"] = str(paths["target"])
        published["publishedManifest"] = {"path": str(paths["target"] / "Manifest.json"), "sha256": sha256_file(manifest_path)}
        published["visualApprovalNote"] = note
        write_atomic_json(report_temp, published)

        if paths["target"].exists():
            if not paths["target"].is_dir() or paths["target"].is_symlink():
                raise ContractError(f"Finaler Zielpfad ist kein sicherer Ordner: {paths['target']}")
            target_entries = list(paths["target"].iterdir())
            if target_entries and not bool(_arg(args, "ersetzen", False)):
                raise ContractError("Finaler Zielordner ist nicht leer. Verwende --ersetzen nur für eine bewusst neu geprüfte Veröffentlichung.")
            if target_entries:
                os.replace(paths["target"], backup)
                target_backed_up = True
            else:
                paths["target"].rmdir()
                target_was_empty = True
        os.replace(stage, paths["target"])
        target_installed = True
        os.replace(report_temp, paths["final_report"])
        report_installed = True
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        try:
            report_temp.unlink()
        except FileNotFoundError:
            pass
        if target_installed and paths["target"].exists():
            shutil.rmtree(paths["target"], ignore_errors=True)
        if target_backed_up and backup.exists() and not paths["target"].exists():
            os.replace(backup, paths["target"])
        elif target_was_empty and not paths["target"].exists():
            paths["target"].mkdir()
        raise
    if target_backed_up and backup.exists():
        try:
            shutil.rmtree(backup)
        except OSError as exc:
            _emit(ctx, f"[WARNUNG] Veröffentlichung war erfolgreich; alter Sicherungsordner blieb erhalten: {backup} ({exc})")
    try:
        _run_core(ctx, "checkpoint", {"arbeitsordner": work, "schritt": "veroeffentlicht"})
    except WorkflowError as exc:
        _emit(ctx, f"[WARNUNG] Checkpoint konnte nicht aktualisiert werden: {exc}")
    _emit(ctx, f"[OK] Bewerbung lokal veröffentlicht: {paths['target']}")
    return 0


def finalisieren(ctx: Any, args: Mapping[str, Any]) -> int:
    work = Path(str(args["arbeitsordner"]))
    paths = _normal_final_paths(safe_path(work, _applications_root_from(work), must_exist=True, kind="dir"), args)
    if bool(_arg(args, "visuell_geprueft", False)) or _arg(args, "visuelle_freigabe_notiz", None):
        raise CliUsageError("Legacy-Sichtschalter ersetzen keine gebundene Chat-Freigabe. Verwende den Befehl 'freigabe'.")
    if bool(_arg(args, "veroeffentlichen", False)) and _arg(args, "dichteausnahme_begruendung", None):
        raise CliUsageError("--dichteausnahme-begruendung ist nur bei der technischen Vorbereitung ohne --veroeffentlichen zulässig.")
    return _normal_publish(ctx, paths, args) if bool(_arg(args, "veroeffentlichen", False)) else _normal_prepare(ctx, paths, args)


def _universal_paths(work: Path, args: Mapping[str, Any]) -> Dict[str, Any]:
    context = infer_work_context(work, universal=True)
    root = context.applications_root
    private = root.parent
    candidate = safe_path(work / "Kandidat", root, must_exist=True, kind="dir")
    order = safe_path(work / "Universalauftrag.json", root, must_exist=True, kind="file")
    stammdaten = _path(args, "stammdaten_path", private / "Daten" / "01_PERSOENLICHE_DATEN.md")
    profil = _path(args, "profil_path", private / "Daten" / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md")
    assert stammdaten is not None and profil is not None
    return {
        "context": context, "root": root, "private": private, "work": work, "candidate": candidate,
        "order_path": order, "stammdaten": safe_path(stammdaten, private, must_exist=True, kind="file"),
        "profil": safe_path(profil, private, must_exist=True, kind="file"), "active": safe_path(context.target, root, kind="dir"),
        "layout": safe_path(work / "Layoutcheck", root, kind="dir"), "pdf_dir": safe_path(work / "PDF-Export", root, kind="dir"),
        "layout_report": safe_path(work / "Layoutcheck" / "Layoutcheck-Bericht.json", root, kind="file"),
        "pdf_report": safe_path(work / "PDF-Export" / "PDF-Export-Bericht.json", root, kind="file"),
        "ats_report": safe_path(work / "ATS-Pruefbericht.json", root, kind="file"),
        "final_report": safe_path(work / "Universal-Finalisierungsbericht.json", root, kind="file"),
    }


def _universal_prepare(ctx: Any, paths: Mapping[str, Any], args: Mapping[str, Any]) -> int:
    work: Path = paths["work"]
    order = read_json(paths["order_path"])
    if not isinstance(order, dict) or order.get("schemaVersion") != 5 or order.get("auftragsart") != "universal_lebenslauf" or order.get("fachrichtung") != "softwareentwicklung":
        raise ContractError("Universalauftrag besitzt nicht den unterstützten Softwareentwicklungsvertrag.")
    source_inputs = order.get("sourceInputs")
    if not isinstance(source_inputs, dict):
        raise ContractError("Universalauftrag enthält keine gebundenen Quellen.")
    for key, path in (("stammdaten", paths["stammdaten"]), ("profil", paths["profil"])):
        record = source_inputs.get(key)
        if not isinstance(record, dict) or str(record.get("sha256", "")).upper() != sha256_file(path):
            raise ContractError(f"Private Quelle '{key}' wurde seit Anlage verändert. Universalauftrag neu anlegen oder bewusst neu vorbereiten.")
    _quality_evidence(paths["candidate"])
    expected_name = f"Lebenslauf - {order.get('bewerberDateiname')}.html"
    documents = _regular_files(paths["candidate"], "Lebenslauf - *.html")
    if len(documents) != 1 or documents[0].name != expected_name:
        raise ContractError(f"Kandidat muss genau die Datei '{expected_name}' enthalten.")
    source = read_text(documents[0])
    pages = html_pages(source)
    if len(pages) != 2:
        raise ContractError("Universeller Lebenslauf muss genau zwei explizite A4-Seiten enthalten.")
    _run_core(ctx, "pruefen", {"ordner": paths["candidate"], "auftrag_path": paths["order_path"]})
    browser_args = {
        "browser": _arg(args, "browser", "auto"), "browser_executable_path": _arg(args, "browser_executable_path", None),
        "timeout_seconds": int(_arg(args, "timeout_seconds", 60)),
    }
    pdf(ctx, {"ordner": paths["candidate"], "auftrag_path": paths["order_path"], "output_root": paths["pdf_dir"], "bericht_path": paths["pdf_report"], **browser_args})
    layout(ctx, {"ordner": paths["candidate"], "output_root": paths["layout"], "bericht_path": paths["layout_report"], **browser_args})
    ats(ctx, {
        "ordner": paths["candidate"], "stammdaten_path": paths["stammdaten"], "auftrag_path": paths["order_path"],
        "bericht_path": paths["ats_report"], "pdf_export_bericht_path": paths["pdf_report"],
    })
    screenshots = _regular_files(paths["layout"], "*.png")
    if len(screenshots) != 2:
        raise ContractError(f"Erwartet werden genau zwei aktuelle Seitenscreenshots; gefunden: {len(screenshots)}.")
    layout_data = read_json(paths["layout_report"])
    warnings = [str(value.get("densityWarning")) for value in layout_data.get("results", []) if isinstance(value, dict) and value.get("densityWarning")]
    candidate_records = [_record(path, work) for path in _regular_files(paths["candidate"])]
    report: Dict[str, Any] = {
        "schemaVersion": 2, "status": "bereit_zur_sichtpruefung", "preparedAtUtc": utc_now(),
        "workId": work.name, "order": _record(paths["order_path"], work),
        "sources": {
            "stammdaten": {"name": paths["stammdaten"].name, "sha256": sha256_file(paths["stammdaten"])},
            "profil": {"name": paths["profil"].name, "sha256": sha256_file(paths["profil"])},
        },
        "candidate": candidate_records, "screenshots": [_record(path, work) for path in screenshots],
        "reports": [_record(paths["layout_report"], work), _record(paths["pdf_report"], work), _record(paths["ats_report"], work)],
        "layoutWarnings": warnings, "personalReview": "png_sichtpruefung",
    }
    records = approval_records(report)
    report["approvalRequest"] = {
        "approvalId": new_approval_id(), "reviewKind": "png_sichtpruefung",
        "artifactSetSha256": artifact_set_hash(records, work), "artifactCount": len(records), "createdAtUtc": utc_now(),
    }
    write_atomic_json(paths["final_report"], report)
    _emit(ctx, "[OK] Universeller Lebenslauf ist technisch bereit zur persönlichen Sichtprüfung.")
    for screenshot in screenshots:
        _emit(ctx, f"- {screenshot}")
    _emit(ctx, f"python3 Tools/bewerbung.py freigabe --arbeitsordner \"{work}\" --freigabe-id {report['approvalRequest']['approvalId']} --bestaetigt")
    return 0


def _universal_publish(ctx: Any, paths: Mapping[str, Any], args: Mapping[str, Any]) -> int:
    work: Path = paths["work"]
    prepared = read_json(paths["final_report"])
    if not isinstance(prepared, dict) or prepared.get("schemaVersion") != 2 or prepared.get("status") != "bereit_zur_sichtpruefung":
        raise ContractError("Universal-Vorbereitungsbericht besitzt keinen aktuellen Freigabestatus.")
    layout_report = read_json(paths["layout_report"])
    if not isinstance(layout_report, dict):
        raise ContractError("Universal-Layoutbericht ist nicht lesbar.")
    _assert_runtime_current(layout_report.get("runtime"), args, True)
    approval = _read_approval(work, paths["final_report"], prepared)
    warnings = prepared.get("layoutWarnings") or []
    note = re.sub(r"\s+", " ", str(approval.get("note", "")).strip())
    if warnings and not note:
        raise ContractError("Layoutwarnungen erfordern eine konkrete Notiz in der Chat-bestätigten Sichtfreigabe.")
    for key, path in (("stammdaten", paths["stammdaten"]), ("profil", paths["profil"])):
        record = prepared.get("sources", {}).get(key) if isinstance(prepared.get("sources"), dict) else None
        if not isinstance(record, dict) or str(record.get("sha256", "")).upper() != sha256_file(path):
            raise ContractError("Private Quelle wurde nach der Vorbereitung verändert.")
    order = read_json(paths["order_path"])
    if not isinstance(order, dict):
        raise ContractError("Universalauftrag ist kein JSON-Objekt.")
    html_files = _regular_files(paths["candidate"], "Lebenslauf - *.html")
    if len(html_files) != 1:
        raise ContractError("Universeller Kandidat enthält nicht genau eine HTML-Datei.")
    pdf_file = html_files[0].with_suffix(".pdf")
    safe_path(pdf_file, paths["candidate"], must_exist=True, kind="file")
    namespace = paths["active"].parent
    stage = safe_path(namespace / (".publish-" + uuid.uuid4().hex), paths["root"], kind="dir")
    try:
        shipping = stage / "Versand"
        internal = stage / "Intern"
        shipping.mkdir(parents=True)
        internal.mkdir()
        shutil.copy2(pdf_file, shipping / pdf_file.name)
        shutil.copy2(html_files[0], internal / html_files[0].name)
        files = [_record(path, stage) for path in sorted(stage.rglob("*"), key=lambda item: item.as_posix()) if path.is_file()]
        write_atomic_json(stage / "Manifest.json", {
            "schemaVersion": 1, "auftragsart": "universal_lebenslauf", "fachrichtung": "softwareentwicklung",
            "zielrollen": ["Frontend-Entwickler", "Backend-Entwickler", "Fullstack-Entwickler"],
            "activatedAtUtc": utc_now(), "workId": prepared.get("workId"),
            "personalReview": {"kind": "png_sichtpruefung", "confirmed": True, "approvalId": approval.get("approvalId"), "note": note},
            "layoutWarnings": warnings, "sourceInputs": prepared.get("sources"), "files": files,
        })
        _install_directory(stage, paths["active"], bool(_arg(args, "ersetzen", False)))
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        raise
    shutil.rmtree(work)
    if work.parent.is_dir() and not any(work.parent.iterdir()):
        work.parent.rmdir()
    _emit(ctx, f"[OK] Universeller Lebenslauf aktiviert: {paths['active']}")
    return 0


def universal_finalisieren(ctx: Any, args: Mapping[str, Any]) -> int:
    work = Path(str(args["arbeitsordner"]))
    root = _applications_root_from(work)
    work = safe_path(work, root, must_exist=True, kind="dir")
    paths = _universal_paths(work, args)
    if bool(_arg(args, "visuell_geprueft", False)) or _arg(args, "visuelle_freigabe_notiz", None):
        raise CliUsageError("Legacy-Sichtschalter ersetzen keine gebundene Chat-Freigabe. Verwende den Befehl 'freigabe'.")
    return _universal_publish(ctx, paths, args) if bool(_arg(args, "veroeffentlichen", False)) else _universal_prepare(ctx, paths, args)


BROWSER_HANDLERS = {
    "layout": layout,
    "pdf": pdf,
    "ats": ats,
    "finalisieren": finalisieren,
    "universal-finalisieren": universal_finalisieren,
}


__all__ = ["BROWSER_HANDLERS", "ats", "finalisieren", "layout", "pdf", "universal_finalisieren"]
