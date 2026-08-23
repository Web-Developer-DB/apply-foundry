"""PowerShell-independent workflow handlers for Linux.

This module owns all browser-free commands.  Browser/PDF/ATS/finalization
handlers are intentionally registered from ``commands_browser.py``.
"""

import base64
import copy
import html
import json
import math
import os
import platform
import re
import shutil
import statistics
import struct
import subprocess
import sys
import time
import unittest
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, MutableMapping, Optional, Sequence, Tuple

from .cli import CommandContext, Handler
from .contracts import (
    approval_records,
    artifact_set_hash,
    assert_artifacts_current,
    document_scope,
    new_evidence_draft,
    new_matrix_draft,
    scope_from_cli,
)
from .errors import CliUsageError, ContractError, UnsafePathError, WorkflowError
from .io import (
    artifact_record,
    canonical_json,
    file_lock,
    read_json,
    read_text,
    sha256_bytes,
    sha256_file,
    utc_now,
    write_atomic_bytes,
    write_atomic_json,
    write_atomic_text,
)
from .paths import (
    OrderPaths,
    infer_work_context,
    new_order_paths,
    parse_date,
    require_private_applications_root,
    resolve_order_paths,
    safe_path,
    slug,
)
from .runtime import diagnose as runtime_diagnose
from .runtime import runtime_fingerprint


CHECKPOINT_STEPS = (
    "auftrag_angelegt", "profilabgleich_abgeschlossen", "analyse_abgeschlossen",
    "dokumente_abgeschlossen", "fachpruefung_abgeschlossen",
    "technische_vorbereitung_abgeschlossen", "sichtpruefung_bestaetigt", "veroeffentlicht",
)
PLACEHOLDER = re.compile(r"(?i)\[ergänzen\]|\[Zeitraum ergänzen\]|\{\{[^}]+\}\}|\bTODO\b|DOKUMENT NOCH NICHT FINAL")
TECHNICAL_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$")
SHA256 = re.compile(r"^[A-Fa-f0-9]{64}$")


def _default(ctx: CommandContext, relative: str) -> Path:
    return ctx.project_root / Path(relative)


def _json_out(ctx: CommandContext, value: Any) -> None:
    ctx.out(json.dumps(value, ensure_ascii=False, indent=2))


def _markdown_fields(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for line in read_text(path).splitlines():
        match = re.match(r"^\s*-\s*([^:]+):\s*(.*)$", line)
        if match and match.group(1).strip() not in result:
            result[match.group(1).strip()] = match.group(2).strip()
    return result


def _placeholder(value: Optional[str]) -> bool:
    if value is None or not value.strip():
        return True
    return bool(re.search(r"(?i)\{\{|\}\}|\[[^]]*(?:optional|z\.\s*B\.|ergänzen|Vollzeit|Teilzeit|vor Ort|hybrid|remote|ja\s*/\s*nein|manuelle Angabe)[^]]*\]|TODO|DOKUMENT NOCH NICHT FINAL", value))


def _unresolved(value: Optional[str]) -> bool:
    return _placeholder(value) or bool(re.fullmatch(r"(?i)nicht festgelegt|offen|noch offen|unbekannt", (value or "").strip()))


def _normalize_note(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def _scope_summary(scope: Mapping[str, Any]) -> str:
    return "Lebenslauf=%s; Anschreiben=%s; E-Mail=%s" % (
        scope["lebenslauf"], str(bool(scope["anschreiben"])).lower(), str(bool(scope["emailNachricht"])).lower()
    )


def _source_paths(ctx: CommandContext, args: Mapping[str, Any], applications: Path) -> Tuple[Path, Path]:
    private = applications.parent
    data = safe_path(private / "Daten", private, must_exist=True, kind="dir")
    master = args.get("stammdaten_path") or _default(ctx, "Private/Daten/01_PERSOENLICHE_DATEN.md")
    profile = args.get("profil_path") or _default(ctx, "Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md")
    return (
        safe_path(Path(master), data, must_exist=True, kind="file"),
        safe_path(Path(profile), data, must_exist=True, kind="file"),
    )


def _write_if_missing(path: Path, text: str) -> None:
    if not path.exists():
        write_atomic_text(path, text)


def _copy_if_identical_or_missing(source: Path, target: Path, label: str) -> None:
    source_bytes = source.read_bytes()
    if target.exists():
        if not target.is_file() or target.read_bytes() != source_bytes:
            raise ContractError("Eine andere %s liegt bereits am Ziel; Überschreiben wurde verweigert." % label)
        return
    write_atomic_bytes(target, source_bytes)


def _checkpoint_artifacts(work: Path) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    for path in sorted(work.rglob("*"), key=lambda item: item.as_posix()):
        if path == work / "Workflow-Checkpoint.json" or not path.is_file():
            continue
        safe = safe_path(path, work, must_exist=True, kind="file")
        records.append(artifact_record(safe, work))
    return records


def _checkpoint_status(work: Path) -> Dict[str, Any]:
    path = work / "Workflow-Checkpoint.json"
    empty = {"available": False, "valid": False, "reason": "fehlend", "updatedAtUtc": None, "lastCompletedStep": None, "artifactCount": 0, "historyCount": 0}
    if not path.is_file():
        return empty
    try:
        value = read_json(safe_path(path, work, must_exist=True, kind="file"))
        if value.get("schemaVersion") != 1 or value.get("kind") != "workflow_checkpoint":
            raise ContractError("schema_ungueltig")
        records = _checkpoint_artifacts(work)
        expected = value.get("artifacts")
        valid = isinstance(expected, list) and expected == records and value.get("artifactSetSha256") == artifact_set_hash(records)
        return {
            "available": True, "valid": valid, "reason": None if valid else "artefakte_veraltet",
            "updatedAtUtc": value.get("updatedAtUtc"), "lastCompletedStep": value.get("lastCompletedStep"),
            "artifactCount": len(expected or []), "historyCount": len(value.get("history") or []),
        }
    except (WorkflowError, OSError, AttributeError, TypeError, ValueError):
        return {**empty, "available": True, "reason": "nicht_lesbar"}


def write_checkpoint(work: Path, step: str) -> Dict[str, Any]:
    if step not in CHECKPOINT_STEPS:
        raise ContractError("Unzulässiger Workflow-Schritt: %s" % step)
    paths = infer_work_context(work, universal=False)
    order_path = safe_path(work / "Bewerbungsauftrag.json", work, must_exist=True, kind="file")
    order = read_json(order_path)
    scope = order.get("dokumentumfang") or {}
    dialog = order.get("dialog") or {}
    blocking = sum(1 for question in dialog.get("rueckfragen", []) if isinstance(question, dict) and question.get("status") == "offen" and question.get("blockiertDokumenterstellung") is True)
    pending = sum(1 for fact in dialog.get("angaben", []) if isinstance(fact, dict) and fact.get("speicherentscheidung") == "ausstehend")
    records = _checkpoint_artifacts(work)
    set_hash = artifact_set_hash(records)
    previous: List[Dict[str, Any]] = []
    checkpoint_path = work / "Workflow-Checkpoint.json"
    if checkpoint_path.is_file():
        try:
            old = read_json(checkpoint_path)
            if old.get("schemaVersion") == 1 and old.get("workFolder") == paths.work_relative:
                previous = [entry for entry in old.get("history", []) if isinstance(entry, dict)][-24:]
        except WorkflowError:
            previous = []
    now = utc_now()
    sequence = int(previous[-1].get("sequence", 0)) + 1 if previous else 1
    previous.append({"sequence": sequence, "step": step, "updatedAtUtc": now, "artifactSetSha256": set_hash})
    checkpoint = {
        "schemaVersion": 1, "kind": "workflow_checkpoint", "updatedAtUtc": now,
        "workFolder": paths.work_relative, "lastCompletedStep": step,
        "order": {
            "orderSchemaVersion": order.get("schemaVersion"), "firmaSlug": order.get("firmaSlug"),
            "rolleSlug": order.get("rolleSlug"), "datum": order.get("datum"),
            "documentScope": {key: scope.get(key) for key in ("auswahl", "lebenslauf", "anschreiben", "emailNachricht")},
            "dialog": {"status": dialog.get("status"), "blockierendeRueckfragen": blocking, "ausstehendeSpeicherentscheidungen": pending},
        },
        "artifacts": records, "artifactSetSha256": set_hash, "history": previous[-24:],
        "dataPolicy": {"copiesSourceContents": False, "containsRawChat": False, "sourceOfTruth": "referenzierte_arbeitsartefakte"},
    }
    with file_lock(checkpoint_path):
        write_atomic_json(checkpoint_path, checkpoint)
    return {"path": str(checkpoint_path), "workFolder": paths.work_relative, "step": step, "artifactCount": len(records), "artifactSetSha256": set_hash, "updatedAtUtc": now}


def handle_diagnose(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    report = runtime_diagnose(
        str(args.get("browser", "auto")),
        args.get("browser_executable_path"),
        bool(args.get("browser_erforderlich")),
    )
    if args.get("als_json"):
        _json_out(ctx, report)
    else:
        for check in report["checks"]:
            prefix = {"ok": "[OK]", "warning": "[WARNUNG]", "error": "[FEHLER]"}[check["status"]]
            ctx.out("%s %s: %s" % (prefix, check["name"], check["detail"]))
        ctx.out("Diagnosestatus: %s (Exitcode %s)" % (report["status"], report["exitCode"]))
    return int(report["exitCode"])


def _validate_creation_fields(company: str, role: str) -> Tuple[str, str]:
    company, role = company.strip(), role.strip()
    if not company or not role:
        raise CliUsageError("Firma und Rolle dürfen nicht leer sein.")
    if len(company) > 120 or len(role) > 120 or re.search(r"[\x00-\x1f\x7f]", company + role):
        raise CliUsageError("Firma und Rolle dürfen höchstens 120 Zeichen und keine Steuerzeichen enthalten.")
    return company, role


def _assert_no_portable_case_collision(parent: Path, expected_name: str) -> None:
    """Reject a Linux-only spelling that would alias on Windows."""

    if not parent.is_dir():
        return
    expected_folded = expected_name.casefold()
    for child in parent.iterdir():
        if child.name.casefold() == expected_folded and child.name != expected_name:
            raise CliUsageError(
                "Portabilitätskonflikt durch abweichende Groß-/Kleinschreibung: "
                "erwartet '%s', gefunden '%s'." % (expected_name, child.name)
            )


def _regular_external_file(path: Path, label: str) -> Path:
    absolute = Path(os.path.abspath(str(path)))
    try:
        return safe_path(absolute, Path(absolute.anchor or os.sep), must_exist=True, kind="file")
    except UnsafePathError as exc:
        raise CliUsageError("%s muss auf eine sichere reguläre Datei zeigen: %s" % (label, exc)) from exc


def _resolve_new_order_inputs(
    ctx: CommandContext,
    args: Mapping[str, Any],
    applications: Path,
    applicant: str,
    scope: Mapping[str, Any],
) -> Tuple[Optional[Path], Optional[Path], Optional[str], Optional[Dict[str, Any]]]:
    source_job = args.get("stellenbeschreibung_path")
    if source_job is not None:
        source_job = _regular_external_file(Path(source_job), "--stellenbeschreibung-path")
    universal_source: Optional[Path] = None
    universal_hash: Optional[str] = None
    universal_binding: Optional[Dict[str, Any]] = None
    if scope["lebenslauf"] == "universal_unveraendert":
        explicit = args.get("universal_lebenslauf_path")
        if explicit is None:
            active = applications / "_Universal-Lebenslauf" / "Aktiv"
            preferred = active / "Intern" / ("Lebenslauf - %s.html" % applicant)
            legacy = ctx.project_root / "Private/LebenslaufUniversal/Aktiv" / ("Lebenslauf - %s.html" % applicant)
            if preferred.is_file():
                valid, _ = _active_manifest_valid(active)
                if not valid:
                    raise ContractError("Die lokale Universalquelle besitzt keinen gültigen persönlichen Freigabe- und Hashnachweis.")
                explicit = preferred
            elif legacy.is_file():
                explicit = legacy
                ctx.warning("Legacy-Universalquelle wird weiterhin gelesen; neue Freigaben gehören unter Private/Bewerbungen/_Universal-Lebenslauf/Aktiv.")
            else:
                raise ContractError("Keine aktive Universalquelle gefunden. Zuerst universal-neu und universal-finalisieren ausführen oder --universal-lebenslauf-path angeben.")
        universal_source = _regular_external_file(Path(explicit), "--universal-lebenslauf-path")
        expected_name = "Lebenslauf - %s.html" % applicant
        if universal_source.suffix != ".html" or universal_source.name != expected_name:
            raise ContractError("Der universelle Lebenslauf muss exakt '%s' heißen." % expected_name)
        if PLACEHOLDER.search(read_text(universal_source)):
            raise ContractError("Der universelle Lebenslauf enthält sichtbare Platzhalter.")
        universal_hash = sha256_file(universal_source)
        project = applications.parent.parent
        if universal_source.is_relative_to(project):
            relative = universal_source.relative_to(project).as_posix()
            universal_binding = {
                "sourceHtmlPfadModus": "relativ_zu_projekt_root",
                "sourceHtmlDateiname": universal_source.name,
                "sourceHtmlSha256BeiAnlage": universal_hash,
                "kandidatDatei": expected_name,
                "sourceHtmlPath": relative,
            }
        else:
            universal_binding = {
                "sourceHtmlPfadModus": "extern_nicht_gespeichert",
                "sourceHtmlDateiname": universal_source.name,
                "sourceHtmlSha256BeiAnlage": universal_hash,
                "kandidatDatei": expected_name,
            }
    elif args.get("universal_lebenslauf_path") is not None:
        raise CliUsageError("--universal-lebenslauf-path ist nur bei ausgewähltem universellem Lebenslauf zulässig.")
    return source_job, universal_source, universal_hash, universal_binding


def _universal_binding_matches(
    existing_order: Mapping[str, Any],
    schema: int,
    source: Path,
    source_hash: str,
    binding: Mapping[str, Any],
    applicant: str,
    project_root: Path,
) -> bool:
    existing = existing_order.get("universalLebenslauf")
    if not isinstance(existing, dict):
        return False
    expected_candidate = "Lebenslauf - %s.html" % applicant
    if str(existing.get("sourceHtmlSha256BeiAnlage", "")).upper() != source_hash.upper():
        return False
    if existing.get("kandidatDatei") != expected_candidate:
        return False
    if existing_order.get("bewerberDateiname") != applicant:
        return False
    if schema <= 4:
        legacy_path = existing.get("sourceHtmlPath")
        return isinstance(legacy_path, str) and bool(legacy_path.strip()) and Path(
            os.path.abspath(legacy_path)
        ) == source

    if existing.get("sourceHtmlDateiname") != binding.get("sourceHtmlDateiname"):
        return False
    existing_mode = existing.get("sourceHtmlPfadModus")
    requested_mode = binding.get("sourceHtmlPfadModus")
    if existing_mode != requested_mode:
        return False
    if existing_mode == "extern_nicht_gespeichert":
        return existing.get("sourceHtmlPath") in (None, "") and binding.get("sourceHtmlPath") is None
    if existing_mode != "relativ_zu_projekt_root":
        return False
    existing_relative = existing.get("sourceHtmlPath")
    if existing_relative != binding.get("sourceHtmlPath") or not isinstance(existing_relative, str):
        return False
    try:
        stored = safe_path(
            project_root / existing_relative,
            project_root,
            must_exist=True,
            kind="file",
        )
    except UnsafePathError:
        return False
    return stored.name == existing.get("sourceHtmlDateiname") and stored == source


def handle_neu(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    company, role = _validate_creation_fields(str(args["firma"]), str(args.get("rolle", "Bewerbung")))
    scope = scope_from_cli(args)
    date_value = parse_date(str(args.get("datum", date.today().isoformat())))
    applications = require_private_applications_root(Path(args.get("bewerbungen_root") or _default(ctx, "Private/Bewerbungen")))
    master, profile = _source_paths(ctx, args, applications)
    # Identity errors block before any folder is created.
    fields = _markdown_fields(master)
    applicant = fields.get("Dateiname-Name", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*", applicant):
        raise ContractError("Dateiname-Name fehlt oder entspricht nicht dem Schema Nachname.Vorname.")
    paths = new_order_paths(applications, slug(company), slug(role), date_value)
    _assert_no_portable_case_collision(applications, paths.target.parent.name)
    _assert_no_portable_case_collision(paths.target.parent, paths.target.name)
    _assert_no_portable_case_collision(paths.target.parent, "_Arbeitsdateien")
    _assert_no_portable_case_collision(paths.work.parent, paths.work.name)
    source_job, universal_source, universal_hash, universal_binding = _resolve_new_order_inputs(
        ctx, args, applications, applicant, scope
    )
    target_exists = paths.target.exists() or paths.target.is_symlink()
    work_exists = paths.work.exists() or paths.work.is_symlink()
    if target_exists or work_exists:
        if not args.get("fortsetzen"):
            raise CliUsageError("Die Bewerbung existiert bereits; für exakt diesen Auftrag --fortsetzen verwenden: %s" % paths.work)
        if target_exists != work_exists:
            raise CliUsageError("Die vorhandene Bewerbung ist unvollständig: Ziel- und Arbeitsordner müssen beide existieren.")
        safe_path(paths.target, applications, must_exist=True, kind="dir")
        safe_path(paths.work, applications, must_exist=True, kind="dir")
        order_path = safe_path(paths.work / "Bewerbungsauftrag.json", paths.work, must_exist=True, kind="file")
        notes = safe_path(paths.work / "Arbeitsnotizen.md", paths.work, must_exist=True, kind="file")
        existing = read_json(order_path)
        resolve_order_paths(existing, applications, paths.work)
        existing_scope = existing.get("dokumentumfang") or {}
        schema = existing.get("schemaVersion")
        for key, wanted in (("firma", company), ("rolle", role), ("datum", date_value)):
            if existing.get(key) not in (None, "") and existing.get(key) != wanted:
                raise CliUsageError("Bewerbungsauftrag und gewünschtes Feld %s stimmen beim Fortsetzen nicht überein." % key)
        if isinstance(schema, int) and schema >= 4:
            for key in ("auswahl", "kennung", "lebenslauf", "anschreiben", "emailNachricht", "emailAlleinBestaetigt"):
                if existing_scope.get(key) != scope.get(key):
                    raise CliUsageError("Bewerbungsauftrag und gewünschter Dokumentumfang stimmen beim Fortsetzen nicht überein.")
            if existing.get("dokumentmodus") != scope["dokumentmodus"]:
                raise CliUsageError("Bewerbungsauftrag und gewünschter Dokumentumfang stimmen beim Fortsetzen nicht überein.")
        else:
            legacy_mode = str(existing.get("dokumentmodus") or "vollbewerbung")
            legacy_selection = "B" if legacy_mode == "anschreiben_mit_universalem_lebenslauf" else "A" if legacy_mode == "vollbewerbung" else None
            if legacy_selection != scope["auswahl"] or legacy_mode != scope["dokumentmodus"]:
                raise CliUsageError("Legacy-Bewerbungsauftrag repräsentiert einen anderen Dokumentumfang.")
        if isinstance(schema, int) and schema >= 5 and existing.get("bewerberDateiname") != applicant:
            raise CliUsageError("Bewerbungsauftrag und Dateiname-Name stimmen beim Fortsetzen nicht überein.")
        if scope["lebenslauf"] == "universal_unveraendert":
            if not _universal_binding_matches(
                existing,
                int(schema),
                universal_source,  # type: ignore[arg-type]
                str(universal_hash),
                universal_binding or {},
                applicant,
                ctx.project_root,
            ):
                raise CliUsageError("Beim Fortsetzen wurde eine andere Universal-Lebenslauf-Quelle übergeben.")
            candidate_source = safe_path(paths.candidate / ("Lebenslauf - %s.html" % applicant), paths.candidate, must_exist=True, kind="file")
            if sha256_file(candidate_source) != universal_hash:
                raise ContractError("Der Kandidaten-Lebenslauf weicht von der gebundenen Universalquelle ab.")
        if source_job is not None:
            _copy_if_identical_or_missing(source_job, paths.candidate / "Stellenbeschreibung.md", "Stellenbeschreibung")
        ctx.ok("Bestehender Bewerbungsauftrag wird fortgesetzt: %s" % paths.work)
        return 0

    created: List[Path] = []
    try:
        for folder in (applications, paths.target.parent, paths.target, paths.work.parent, paths.work, paths.candidate):
            if not folder.exists():
                folder.mkdir()
                created.append(folder)
            safe_path(folder, applications, allow_root=folder == applications, must_exist=True, kind="dir")
        now = utc_now()
        logistics_map = {
            "verfuegbarkeit": "Verfügbarkeit", "fruehesterEintrittstermin": "Frühester Eintrittstermin",
            "stellenart": "Gewünschte Stellenart", "stundenumfang": "Gewünschter Stundenumfang",
            "arbeitsmodell": "Gewünschtes Arbeitsmodell", "region": "Gewünschte Region",
            "maximalePendeldistanz": "Maximale Pendeldistanz", "reisebereitschaft": "Reisebereitschaft",
            "schichtOderWochenendbereitschaft": "Schicht- oder Wochenendbereitschaft", "befristung": "Befristung",
            "umzugsbereitschaft": "Umzugsbereitschaft", "wunschgehaltVerwenden": "Wunschgehalt verwenden",
            "wunschgehaltManuell": "Wunschgehalt manuell", "gehaltsmodell": "Gehaltsmodell",
            "gehaltsregion": "Gehaltsregion", "gehaltslogik": "Gehaltslogik",
        }
        order = {
            "schemaVersion": 5, "pfadModus": "relativ_zu_bewerbungen_root", "firma": company,
            "firmaSlug": slug(company), "rolle": role, "rolleSlug": slug(role), "datum": date_value,
            "bewerberDateiname": applicant, "zielOrdner": paths.target_relative,
            "arbeitsOrdner": paths.work_relative, "kandidatOrdner": paths.candidate_relative,
            "dokumentmodus": scope["dokumentmodus"],
            "dokumentumfang": {
                "auswahl": scope["auswahl"], "kennung": scope["kennung"], "lebenslauf": scope["lebenslauf"],
                "anschreiben": scope["anschreiben"], "emailNachricht": scope["emailNachricht"],
                "quelle": str(args.get("umfang_quelle", "auswahl")), "bestaetigt": True,
                "emailAlleinBestaetigt": scope["emailAlleinBestaetigt"], "bestaetigtAtUtc": now,
            },
            "universalLebenslauf": universal_binding,
            "seitenstrategie": "noch_festzulegen" if scope["lebenslauf"] != "nicht_enthalten" else "nicht_erforderlich",
            "bewerbungslogistik": {target: fields.get(source, "") for target, source in logistics_map.items()},
            "bewerbungsentscheidung": "noch_festzulegen",
            "darstellungsoptionen": {
                "schulbildungsmodus": "noch_festzulegen" if scope["lebenslauf"] != "nicht_enthalten" else "nicht_erforderlich",
                "profillinksModus": "noch_festzulegen" if scope["lebenslauf"] != "nicht_enthalten" else "nicht_erforderlich",
                "profillinksAuswahl": [],
            },
            "dialog": {"schemaVersion": 1, "status": "profilabgleich_ausstehend", "rueckfragen": [], "angaben": [], "updatedAtUtc": now},
            "quellnachweise": {"stammdatenSha256BeiAnlage": sha256_file(master), "profilSha256BeiAnlage": sha256_file(profile)},
            "createdAtUtc": now,
        }
        write_atomic_json(paths.work / "Bewerbungsauftrag.json", order)
        write_atomic_json(paths.work / "Anforderungsmatrix--ENTWURF.json", new_matrix_draft(bool(scope["anschreiben"])))
        write_atomic_json(paths.work / "Evidenzindex--ENTWURF.json", new_evidence_draft())
        if source_job is not None:
            _copy_if_identical_or_missing(source_job, paths.candidate / "Stellenbeschreibung.md", "Stellenbeschreibung")
        else:
            _write_if_missing(paths.work / "Stellenbeschreibung--ENTWURF.md", "# Stellenbeschreibung\n\n[Stellenbeschreibung hier einfügen]\n")
        if universal_source is not None:
            _copy_if_identical_or_missing(universal_source, paths.candidate / universal_source.name, "Universal-Lebenslauf")
        _write_application_drafts(paths, company, role, applicant, scope)
        checkpoint = write_checkpoint(paths.work, "auftrag_angelegt")
    except Exception:
        for folder in reversed(created):
            try:
                if folder.exists() and not folder.is_symlink():
                    folder.rmdir() if not any(folder.iterdir()) else shutil.rmtree(str(folder))
            except OSError:
                pass
        raise
    ctx.out("Bewerbungsordner: %s" % paths.target)
    ctx.out("Arbeitsdateien: %s" % paths.work)
    ctx.out("Kandidatendateien: %s" % paths.candidate)
    ctx.out("Dokumentmodus: %s" % scope["dokumentmodus"])
    ctx.out("Dokumentumfang: %s" % _scope_summary(scope))
    ctx.out("Workflow-Checkpoint: %s" % checkpoint["path"])
    return 0


def _write_application_drafts(paths: OrderPaths, company: str, role: str, applicant: str, scope: Mapping[str, Any]) -> None:
    _write_if_missing(paths.work / "Analyse--ENTWURF.md", "# Analyse\n\n- Firma: %s\n- Zielrolle: %s\n- Profilstrategie: [nach Analyse ergänzen]\n" % (company, role))
    if scope["lebenslauf"] == "individuell":
        _write_if_missing(paths.work / ("Lebenslauf--%s--ENTWURF.html" % slug(company)), "<!doctype html>\n<html lang=\"de\"><head><meta charset=\"utf-8\"><style>@page { size: A4; margin: 0; } .page { width: 210mm; height: 297mm; }</style></head><body><main class=\"page\"><h1>Lebenslauf - Arbeitsentwurf</h1><p>DOKUMENT NOCH NICHT FINAL</p></main></body></html>\n")
    if scope["anschreiben"]:
        _write_if_missing(paths.work / ("Anschreiben--%s--ENTWURF.html" % slug(company)), "<!doctype html>\n<html lang=\"de\"><head><meta charset=\"utf-8\"><style>@page { size: A4; margin: 0; } .page { width: 210mm; height: 297mm; }</style></head><body><main class=\"page\"><h1>Anschreiben - Arbeitsentwurf</h1><p>DOKUMENT NOCH NICHT FINAL</p></main></body></html>\n")
    _write_if_missing(paths.work / "Arbeitsnotizen.md", "# Arbeitsnotizen\n\n- Firma: %s\n- Zielrolle: %s\n- Dokumentmodus: %s\n- Dokumentumfang: %s\n- Finaler Bewerbungsordner: %s\n- Entwurfs-/Arbeitsdateien: %s\n- Kandidatendateien vor Freigabe: %s\n\nDer finale Bewerbungsordner bleibt bis zur erfolgreichen atomaren Veröffentlichung leer.\n" % (company, role, scope["dokumentmodus"], _scope_summary(scope), paths.target, paths.work, paths.candidate))
    if scope["emailNachricht"]:
        _write_if_missing(paths.work / ("Email-Nachricht--%s--ENTWURF.md" % slug(company)), "Betreff: Bewerbung als %s - [Name aus den Stammdaten]\n\nSehr geehrte Damen und Herren,\n\nhiermit bewerbe ich mich für die Position als %s bei %s.\n" % (role, role, company))
    _write_if_missing(paths.work / "Qualitaetscheck--ENTWURF.md", "# Qualitätscheck\n\n- [ ] Stellenbeschreibung analysiert\n- [ ] Keine erfundenen Kenntnisse\n- [ ] Keine sichtbaren Platzhalter\n")
    _write_if_missing(paths.work / "Offene_Fragen--ENTWURF.md", "# Offene Fragen\n\n- [ ] Fehlen Ansprechpartner oder Adresse?\n")
    _write_if_missing(paths.candidate / "Druck-Hinweis.md", "# Druck-Hinweis\n\nDer verbindliche PDF-Export erfolgt automatisiert mit einem unterstützten Chromium-Browser. Jeder frisch erzeugte Seitenscreenshot muss persönlich geprüft werden.\n")


def handle_universal_neu(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    date_value = parse_date(str(args.get("datum", date.today().isoformat())))
    applications = require_private_applications_root(Path(args.get("bewerbungen_root") or _default(ctx, "Private/Bewerbungen")))
    master, profile = _source_paths(ctx, args, applications)
    fields = _markdown_fields(master)
    applicant = fields.get("Dateiname-Name", "")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*", applicant):
        raise ContractError("Dateiname-Name fehlt oder ist für den Lebenslauf-Dateinamen ungültig.")
    namespace = safe_path(applications / "_Universal-Lebenslauf", applications)
    collection = safe_path(namespace / "_Arbeitsdateien", applications)
    work = safe_path(collection / (date_value + "--Softwareentwicklung"), applications)
    candidate = safe_path(work / "Kandidat", applications)
    _assert_no_portable_case_collision(applications, "_Universal-Lebenslauf")
    _assert_no_portable_case_collision(namespace, "_Arbeitsdateien")
    _assert_no_portable_case_collision(collection, work.name)
    if work.exists() or work.is_symlink():
        if not args.get("fortsetzen"):
            raise CliUsageError("Universal-Arbeitsordner existiert bereits; --fortsetzen verwenden: %s" % work)
        safe_path(work / "Universalauftrag.json", work, must_exist=True, kind="file")
        safe_path(candidate, work, must_exist=True, kind="dir")
        ctx.ok("Bestehender Universal-Lebenslauf-Arbeitsstand wird fortgesetzt: %s" % work)
        return 0
    candidate.mkdir(parents=True)
    now = utc_now()
    work_rel = "_Universal-Lebenslauf/_Arbeitsdateien/%s--Softwareentwicklung" % date_value
    order = {
        "schemaVersion": 5, "auftragsart": "universal_lebenslauf", "fachrichtung": "softwareentwicklung",
        "zielrollen": ["Frontend-Entwickler", "Backend-Entwickler", "Fullstack-Entwickler"],
        "datum": date_value, "bewerberDateiname": applicant, "pfadModus": "relativ_zu_bewerbungen_root",
        "zielOrdner": "_Universal-Lebenslauf/Aktiv", "arbeitsOrdner": work_rel, "kandidatOrdner": work_rel + "/Kandidat",
        "dokumentmodus": "individuelle_auswahl",
        "dokumentumfang": {"kennung": "universal_lebenslauf", "bestaetigt": True, "lebenslauf": "individuell", "anschreiben": False, "emailNachricht": False},
        "seitenstrategie": {"typ": "zwei_seiten_semantisch", "abschnitteAtomar": True, "seite1": ["kurzprofil", "technologien", "projekte"], "seite2": ["berufserfahrung", "weiterbildung", "ausbildung", "schulbildung"]},
        "sourceInputs": {
            "stammdaten": {"name": master.name, "sha256": sha256_file(master)},
            "profil": {"name": profile.name, "sha256": sha256_file(profile)},
        },
        "status": "dokumenterstellung", "createdAtUtc": now,
    }
    write_atomic_json(work / "Universalauftrag.json", order)
    write_atomic_text(candidate / "Stellenbeschreibung.md", "# Positionierungsgrundlage für den universellen Lebenslauf\n\nDieser Auftrag bezieht sich auf keine konkrete Stellenanzeige und keinen Arbeitgeber. Schwerpunkt ist ausschließlich Softwareentwicklung; IT-Administration ist keine Zielrichtung.\n")
    write_atomic_text(candidate / "Analyse.md", "# Analyse\n\n## Recruiter-Strategie\n\n[ergänzen: Belegstrategie und Priorisierung]\n\n## Seitenplan\n\n- Seite 1: Kurzprofil, Technologien und Projekte\n- Seite 2: Berufserfahrung, Weiterbildung, Ausbildung und Schulbildung\n")
    write_atomic_text(candidate / "Qualitaetscheck.md", "# Qualitätscheck\n\n- Wahrheits- und Profilabgleich: [ergänzen]\n- Softwareentwicklung klar positioniert: [ergänzen]\n")
    write_atomic_text(candidate / "Druck-Hinweis.md", "# Druck-Hinweis\n\nBeide expliziten A4-Seiten müssen im Chromium-Export erzeugt und anhand aktueller PNG-Dateien persönlich geprüft werden.\n")
    ctx.ok("Universal-Lebenslauf-Arbeitsordner angelegt: %s" % work)
    ctx.out("Kandidat: %s" % candidate)
    ctx.out("Erwartete HTML-Datei: %s" % (candidate / ("Lebenslauf - %s.html" % applicant)))
    return 0


def _active_manifest_valid(active: Path) -> Tuple[bool, Optional[Dict[str, Any]]]:
    manifest_path = active / "Manifest.json"
    if not manifest_path.is_file():
        return False, None
    try:
        manifest = read_json(manifest_path)
        if manifest.get("schemaVersion") != 1 or manifest.get("auftragsart") != "universal_lebenslauf" or (manifest.get("personalReview") or {}).get("confirmed") is not True:
            return False, manifest
        records = manifest.get("files") or []
        if len(records) != 2:
            return False, manifest
        assert_artifacts_current(records, active)
        expected = sorted(str(item.get("path")) for item in records)
        actual = sorted(path.relative_to(active).as_posix() for path in active.rglob("*") if path.is_file() and path.name != "Manifest.json")
        return expected == actual, manifest
    except (WorkflowError, OSError, TypeError, ValueError):
        return False, None


def handle_universal_status(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    applications = require_private_applications_root(Path(args.get("bewerbungen_root") or _default(ctx, "Private/Bewerbungen")), must_exist=True)
    namespace = safe_path(applications / "_Universal-Lebenslauf", applications)
    active = safe_path(namespace / "Aktiv", applications)
    collection = safe_path(namespace / "_Arbeitsdateien", applications)
    work = args.get("arbeitsordner")
    if work is not None:
        work = infer_work_context(Path(work), universal=True).work
    elif collection.is_dir():
        candidates = [item for item in collection.iterdir() if item.is_dir() and not item.is_symlink()]
        if candidates:
            work = max(candidates, key=lambda item: item.stat().st_mtime_ns)
    valid, manifest = _active_manifest_valid(active) if active.is_dir() else (False, None)
    active_work_id = str((manifest or {}).get("workId", ""))
    if work is not None:
        if valid and work.name == active_work_id:
            phase = "aktiv_bereinigung_ausstehend"
        else:
            report = work / "Universal-Finalisierungsbericht.json"
            prepared = False
            if report.is_file():
                try:
                    prepared = read_json(report).get("status") == "bereit_zur_sichtpruefung"
                except WorkflowError:
                    pass
            phase = "persoenliche_pruefung" if prepared else "dokumenterstellung"
    elif valid:
        phase = "aktiv"
    elif active.is_dir():
        phase = "aktiv_ungueltig"
    else:
        phase = "nicht_angelegt"
    actions = {
        "persoenliche_pruefung": "Beide aktuellen PNG-Seiten persönlich prüfen und danach eindeutig aktivieren.",
        "dokumenterstellung": "Kandidat und interne Nachweise fertigstellen, danach universal-finalisieren vorbereiten.",
        "aktiv": "Keine Aktion erforderlich; aktive Quelle kann unverändert verwendet werden.",
        "aktiv_bereinigung_ausstehend": "Aktivierung ist gültig; universal-finalisieren erneut aufrufen, um den Arbeitsordner zu bereinigen.",
        "aktiv_ungueltig": "Aktiver Manifest-Satz ist unvollständig oder verändert und muss neu erzeugt werden.",
        "nicht_angelegt": "Mit universal-neu einen neuen Universal-Lebenslauf-Arbeitsstand anlegen.",
    }
    result = {"phase": phase, "workFolder": str(work) if work else None, "activeFolder": str(active) if active.is_dir() else None, "activeManifestValid": valid, "nextAction": actions[phase]}
    if args.get("als_json"):
        _json_out(ctx, result)
    else:
        ctx.ok("Phase: %s" % phase)
        if work:
            ctx.out("Arbeitsordner: %s" % work)
        ctx.out("Nächster Schritt: %s" % actions[phase])
    return 0


def _latest_work(ctx: CommandContext) -> Path:
    applications = require_private_applications_root(_default(ctx, "Private/Bewerbungen"), must_exist=True)
    candidates: List[Path] = []
    for path in applications.glob("*/_Arbeitsdateien/*"):
        if path.parent.parent.name == "_Universal-Lebenslauf" or path.is_symlink() or not path.is_dir():
            continue
        if (path / "Bewerbungsauftrag.json").is_file() and (path / "Arbeitsnotizen.md").is_file():
            try:
                infer_work_context(path, universal=False)
                candidates.append(path)
            except WorkflowError:
                pass
    if not candidates:
        raise ContractError("Kein gültiger Bewerbungsarbeitsordner gefunden.")
    activity = sorted(((max((item.stat().st_mtime_ns for item in path.rglob("*") if item.is_file()), default=path.stat().st_mtime_ns), path) for path in candidates), reverse=True)
    if len(activity) > 1 and activity[0][0] == activity[1][0]:
        raise CliUsageError("Mehrere Bewerbungen besitzen denselben letzten Aktivitätszeitpunkt.")
    return activity[0][1]


def _expected_candidate_patterns(scope: Mapping[str, Any]) -> List[str]:
    patterns = []
    if scope["lebenslauf"] != "nicht_enthalten":
        patterns.append("Lebenslauf - *.html")
    if scope["anschreiben"]:
        patterns.append("Anschreiben - *.html")
    if scope["emailNachricht"]:
        patterns.append("Email-Nachricht--*.md")
    patterns.extend(("Stellenbeschreibung.md", "Analyse.md", "Qualitaetscheck.md", "Druck-Hinweis.md"))
    return patterns


def handle_status(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    work = infer_work_context(Path(args["arbeitsordner"]), universal=False).work if args.get("arbeitsordner") else _latest_work(ctx)
    paths = infer_work_context(work, universal=False)
    order = read_json(safe_path(work / "Bewerbungsauftrag.json", work, must_exist=True, kind="file"))
    safe_path(work / "Arbeitsnotizen.md", work, must_exist=True, kind="file")
    scope = document_scope(order)
    dialog = order.get("dialog") or {}
    blockers = [str(item.get("id")) for item in dialog.get("rueckfragen", []) if isinstance(item, dict) and item.get("status") == "offen" and item.get("blockiertDokumenterstellung") is True]
    blockers.extend(str(item.get("id")) for item in dialog.get("angaben", []) if isinstance(item, dict) and item.get("speicherentscheidung") == "ausstehend")
    missing = []
    for pattern in _expected_candidate_patterns(scope):
        matches = [item for item in paths.candidate.glob(pattern) if item.is_file() and not item.is_symlink()] if paths.candidate.is_dir() else []
        if len(matches) != 1:
            missing.append(pattern)
    matrix_path = work / "Anforderungsmatrix.json"
    matrix_incomplete = False
    if matrix_path.is_file():
        try:
            matrix = read_json(matrix_path)
            if matrix.get("schemaVersion") == 5:
                strategy = matrix.get("anschreibenStrategie") or {}
                matrix_incomplete = bool(scope["anschreiben"] and strategy.get("status") != "final") or not (work / "Evidenzindex.json").is_file()
        except WorkflowError:
            matrix_incomplete = True
    final_report_path = work / "Finalisierungsbericht.json"
    final_status = None
    final_valid = False
    if final_report_path.is_file():
        try:
            report = read_json(final_report_path)
            final_status = report.get("status")
            records = approval_records(report)
            assert_artifacts_current(records, work)
            # A copied order remains portable, but browser/PDF/ATS evidence is
            # deliberately bound to the originating OS, runtime and browser.
            # Do not offer an old foreign report for personal approval after a
            # platform switch.
            from .commands_browser import _assert_runtime_current

            _assert_runtime_current(
                report.get("runtime"), {},
                scope["lebenslauf"] != "nicht_enthalten" or bool(scope["anschreiben"]),
            )
            final_valid = report.get("schemaVersion") in (6, 7) and bool(records)
        except WorkflowError:
            final_valid = False
    dialog_status = str(dialog.get("status", ""))
    scope_confirmed = bool((order.get("dokumentumfang") or {}).get("bestaetigt", order.get("schemaVersion", 0) < 4))
    if not scope_confirmed:
        phase, action, prompts = "umfangsklaerung", "Dokumentumfang nach Prompt 01 eindeutig bestätigen.", ["Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md"]
    elif blockers or dialog_status in ("profilabgleich_ausstehend", "rueckfragen_offen", "speicherentscheidung_offen"):
        phase, action, prompts = "profilabgleich", "Nur gespeicherte offene Blocker bearbeiten.", ["Prompts/01_DOKUMENTMODI_UND_UNIVERSALER_LEBENSLAUF.md", "Prompts/07_WAHRHEIT_UND_GRENZEN.md"]
    elif not matrix_path.is_file() or matrix_incomplete:
        phase, action, prompts = "strategie_und_matrix", "Profilstrategie und Anforderungsmatrix vervollständigen.", ["Prompts/02_VORPRUEFUNG_UND_ANFORDERUNGSMATRIX.md", "Prompts/07_WAHRHEIT_UND_GRENZEN.md"]
    elif missing:
        phase, action, prompts = "dokumenterstellung", "Nur die laut Dokumentumfang fehlenden Kandidatendateien erstellen.", []
    elif final_valid and final_status == "bereit_zur_sichtpruefung":
        phase, action, prompts = "persoenliche_pruefung", "Gebundene Seiten beziehungsweise Textdateien persönlich prüfen.", ["Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md"]
    elif final_valid and final_status == "veroeffentlicht" and (paths.target / "Manifest.json").is_file():
        phase, action, prompts = "veroeffentlicht", "Keine weitere Aktion erforderlich.", []
    else:
        phase, action, prompts = "technische_vorbereitung", "Fachlichen Kandidatenstand prüfen und Finalisierung vorbereiten.", ["Prompts/09_QUALITAETSCHECK.md", "Prompts/11_TECHNISCHER_CHECK_WORKFLOW.md"]
    result = {
        "schemaVersion": 2, "workFolder": str(work), "candidateFolder": str(paths.candidate), "phase": phase,
        "dialogStatus": dialog_status, "blockers": blockers, "missingCandidateFiles": missing,
        "finalReportValid": final_valid, "finalStatus": final_status, "technicalAttempt": None,
        "workflowCheckpoint": _checkpoint_status(work), "requiredPrompts": prompts, "nextAction": action,
    }
    if args.get("als_json"):
        _json_out(ctx, result)
    else:
        ctx.ok("Arbeitsordner: %s" % work)
        ctx.out("Phase: %s" % phase)
        if blockers:
            ctx.out("Blocker: %s" % ", ".join(blockers))
        if missing:
            ctx.out("Fehlende Kandidatendateien: %s" % ", ".join(missing))
        ctx.out("Nächster Schritt: %s" % action)
    return 0


def handle_checkpoint(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    result = write_checkpoint(Path(args["arbeitsordner"]), str(args["schritt"]))
    if args.get("als_json"):
        _json_out(ctx, result)
    else:
        ctx.ok("Workflow-Checkpoint aktualisiert: %s" % result["path"])
        ctx.out("Schritt: %s; Artefakte: %s; SHA-256: %s" % (result["step"], result["artifactCount"], result["artifactSetSha256"]))
    return 0


def _migration_scaffold(matrix: Dict[str, Any], source_schema: int, job_path: Optional[Path], letter: bool, unresolved: List[str]) -> Tuple[Dict[str, Any], List[Dict[str, Any]]]:
    target = copy.deepcopy(matrix)
    steps = []
    current = source_schema
    while current < 5:
        following = current + 1
        if current == 1:
            for requirement in target.get("requirements") or []:
                if not requirement.get("gewichtung"):
                    requirement["gewichtung"] = "hoch" if requirement.get("typ") == "muss" else "niedrig"
                if not requirement.get("kategorie"):
                    requirement["kategorie"] = "noch_zu_pruefen"
                    unresolved.append("requirements[%s].kategorie" % requirement.get("id", "?"))
        elif current == 2 and not isinstance(target.get("recruiterStrategie"), dict):
            target["recruiterStrategie"] = {"kernbotschaft": "vor der Dokumenterstellung abzuleiten", "profilSubstanz": "noch_zu_pruefen", "profilSubstanzBegruendung": "fachlich zu ergänzen", "prioritaetsAnforderungen": [], "profilHighlights": [], "transferbruecken": [], "auslassungen": []}
            unresolved.append("recruiterStrategie")
        elif current == 3:
            if not isinstance(target.get("stellenanzeigeAbdeckung"), dict):
                target["stellenanzeigeAbdeckung"] = {"sourceSha256": sha256_file(job_path) if job_path else "", "fundstellen": []}
                unresolved.append("stellenanzeigeAbdeckung.fundstellen")
                if not job_path:
                    unresolved.append("stellenanzeigeAbdeckung.sourceSha256")
            for requirement in target.get("requirements") or []:
                requirement.setdefault("stellenFundstellen", [])
                requirement.setdefault("belegRefIds", [])
        elif current == 4:
            target.setdefault("externeQuellen", [])
            target.setdefault("anschreibenStrategie", {"status": "ausstehend" if letter else "nicht_erforderlich", "argumente": [], "abweichungBegruendung": ""})
            if letter and not (target.get("anschreibenStrategie") or {}).get("argumente"):
                unresolved.append("anschreibenStrategie.argumente")
            target.setdefault("recruiterStrategie", {"kernbotschaft": "vor der Dokumenterstellung abzuleiten", "profilSubstanz": "noch_zu_pruefen", "profilSubstanzBegruendung": "fachlich zu ergänzen", "prioritaetsAnforderungen": [], "profilHighlights": [], "transferbruecken": [], "auslassungen": []})
            target["recruiterStrategie"].setdefault("auslassungen", [])
        target["schemaVersion"] = following
        steps.append({"id": "matrix/%s-zu-%s" % (current, following), "from": current, "to": following, "status": "ausgeführt"})
        current = following
    return target, steps


def _migration_completeness(matrix: Dict[str, Any], evidence: Dict[str, Any], letter: bool, unresolved: List[str]) -> None:
    for key in ("requirements", "recruiterStrategie", "anschreibenStrategie", "externeQuellen", "stellenanzeigeAbdeckung"):
        if key not in matrix:
            unresolved.append("matrix." + key)
    if not matrix.get("requirements"):
        unresolved.append("matrix.requirements")
    coverage = matrix.get("stellenanzeigeAbdeckung") or {}
    if not SHA256.fullmatch(str(coverage.get("sourceSha256", ""))):
        unresolved.append("stellenanzeigeAbdeckung.sourceSha256")
    if not isinstance(coverage.get("fundstellen"), list) or not coverage.get("fundstellen"):
        unresolved.append("stellenanzeigeAbdeckung.fundstellen")
    strategy = matrix.get("anschreibenStrategie") or {}
    if letter and (strategy.get("status") != "final" or not strategy.get("argumente")):
        unresolved.append("anschreibenStrategie.argumente")
    if not SHA256.fullmatch(str(evidence.get("profilSha256", ""))):
        unresolved.append("Evidenzindex.profilSha256")
    if not isinstance(evidence.get("belege"), list) or not evidence.get("belege"):
        unresolved.append("Evidenzindex.belege")


def handle_migrieren(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    work = infer_work_context(Path(args["arbeitsordner"]), universal=False).work
    matrix_path = safe_path(work / "Anforderungsmatrix.json", work, must_exist=True, kind="file")
    order_path = safe_path(work / "Bewerbungsauftrag.json", work, must_exist=True, kind="file")
    evidence_path = safe_path(work / "Evidenzindex.json", work)
    matrix = read_json(matrix_path)
    order = read_json(order_path)
    schema = matrix.get("schemaVersion")
    if not isinstance(schema, int) or isinstance(schema, bool) or schema < 1 or schema > 5:
        raise CliUsageError("Anforderungsmatrix verwendet keine unterstützte schemaVersion 1 bis 5.")
    existing_evidence = read_json(evidence_path) if evidence_path.is_file() else None
    if existing_evidence is not None and existing_evidence.get("schemaVersion") != 1:
        raise CliUsageError("Evidenzindex verwendet keine unterstützte schemaVersion 1.")
    paths = infer_work_context(work, universal=False)
    job_path = paths.candidate / "Stellenbeschreibung.md"
    job_path = job_path if job_path.is_file() else None
    private = paths.applications_root.parent
    profile = private / "Daten" / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
    unresolved: List[str] = []
    target_matrix, steps = _migration_scaffold(matrix, schema, job_path, bool(document_scope(order)["anschreiben"]), unresolved)
    if existing_evidence is None:
        target_evidence = new_evidence_draft(sha256_file(profile) if profile.is_file() and not profile.is_symlink() else None, sha256_file(order_path))
        steps.append({"id": "evidenzindex/0-zu-1", "from": 0, "to": 1, "status": "ausgeführt"})
    else:
        target_evidence = copy.deepcopy(existing_evidence)
    _migration_completeness(target_matrix, target_evidence, bool(document_scope(order)["anschreiben"]), unresolved)
    unresolved = list(dict.fromkeys(unresolved))
    matrix_hash = sha256_bytes(canonical_json(target_matrix))
    evidence_hash = sha256_bytes(canonical_json(target_evidence))
    incomplete = bool(unresolved)
    status = "unvollstaendig" if incomplete else "aktuell" if schema == 5 and existing_evidence is not None else "bereit_zur_uebernahme"
    changed: List[str] = []
    report = {
        "schemaVersion": 1, "kind": "matrix_evidenz_migration", "status": status, "preview": not bool(args.get("anwenden")),
        "preparedAtUtc": utc_now(), "workFolder": str(work),
        "matrix": {"sourceSchemaVersion": schema, "targetSchemaVersion": 5, "sourceSha256": sha256_file(matrix_path), "targetSha256": matrix_hash, "draftPath": "Anforderungsmatrix--MIGRATION-ENTWURF.json" if incomplete else None},
        "evidenzindex": {"sourceSchemaVersion": 1 if existing_evidence is not None else 0, "targetSchemaVersion": 1, "sourceSha256": sha256_file(evidence_path) if evidence_path.is_file() else None, "targetSha256": evidence_hash, "draftPath": "Evidenzindex--MIGRATION-ENTWURF.json" if incomplete else None},
        "steps": steps, "unresolvedFields": unresolved, "changedFiles": changed, "errors": [], "warnings": [], "errorClass": None,
    }
    if args.get("anwenden"):
        if incomplete:
            for name, value in (("Anforderungsmatrix--MIGRATION-ENTWURF.json", target_matrix), ("Evidenzindex--MIGRATION-ENTWURF.json", target_evidence)):
                path = work / name
                if path.is_file() and sha256_bytes(canonical_json(read_json(path))) != sha256_bytes(canonical_json(value)):
                    raise CliUsageError("Vorhandener Migrationsentwurf würde überschrieben: %s" % name)
                write_atomic_json(path, value)
                changed.append(name)
            report.update(status="entwurf_erzeugt", preview=False)
        elif schema == 5 and existing_evidence is not None:
            report.update(status="aktuell", preview=False)
        else:
            # Hash recheck immediately before the two-file commit.
            matrix_source_hash = report["matrix"]["sourceSha256"]
            evidence_source_hash = report["evidenzindex"]["sourceSha256"]
            with file_lock(work / "Migration.lock"):
                if sha256_file(matrix_path) != matrix_source_hash or (evidence_path.is_file() and sha256_file(evidence_path) != evidence_source_hash):
                    raise ContractError("Nachweise wurden während der Migration verändert; Hash-Recheck fehlgeschlagen.")
                write_atomic_json(matrix_path, target_matrix)
                write_atomic_json(evidence_path, target_evidence)
            changed.extend(("Anforderungsmatrix.json", "Evidenzindex.json"))
            report.update(status="migriert", preview=False)
    report["changedFiles"] = changed
    report_path = args.get("bericht_path")
    if report_path is None and args.get("anwenden"):
        report_path = work / "Migrationsbericht.json"
    if report_path is not None:
        write_atomic_json(safe_path(Path(report_path), work), report)
    if args.get("als_json"):
        _json_out(ctx, report)
    else:
        ctx.out("[INFO] Migrationsstatus: %s" % report["status"])
        if unresolved:
            ctx.warning("Offene Ergänzungen: %s" % ", ".join(unresolved))
        if changed:
            ctx.ok("Geänderte Dateien: %s" % ", ".join(changed))
    return 1 if report["status"] in ("unvollstaendig", "entwurf_erzeugt") else 0


def _stammdaten_paths(ctx: CommandContext, args: Mapping[str, Any]) -> Tuple[Path, Optional[Path], Optional[Path], Optional[Path]]:
    master = Path(args.get("stammdaten_path") or _default(ctx, "Private/Daten/01_PERSOENLICHE_DATEN.md"))
    data = master.parent
    private = data.parent
    if data.name != "Daten" or private.name != "Private":
        raise UnsafePathError("Stammdatenpfad muss unter <Projektwurzel>/Private/Daten liegen.")
    master = safe_path(master, data, must_exist=True, kind="file")
    order = args.get("bewerbungsauftrag_path")
    report = args.get("bericht_path")
    work = None
    if order is not None:
        order = Path(order)
        work = infer_work_context(order.parent, universal=False).work
        order = safe_path(order, work, must_exist=True, kind="file")
    if report is not None:
        report = Path(report)
        if work is None:
            work = report.parent
            infer_work_context(work, universal=False)
        report = safe_path(report, work)
        if report == master or report == order:
            raise UnsafePathError("Berichtspfad darf keine Eingabedatei aliasieren.")
    return master, order, report, work


def handle_stammdaten(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    master, order_path, report_path, _ = _stammdaten_paths(ctx, args)
    fields = _markdown_fields(master)
    errors: List[str] = []
    warnings: List[str] = []
    oks: List[str] = []
    required = ("Vollständiger Name", "Vorname", "Nachname", "Dateiname-Name", "Adresse", "Telefon", "E-Mail", "Verfügbarkeit")
    for name in required:
        if name not in fields or _placeholder(fields.get(name)):
            errors.append("Pflichtfeld fehlt, ist leer oder enthält einen Beispielplatzhalter: %s" % name)
        else:
            oks.append("Pflichtfeld ist gepflegt: %s" % name)
    if fields.get("E-Mail") and not _placeholder(fields.get("E-Mail")) and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", fields["E-Mail"]):
        errors.append("E-Mail hat kein plausibles Format.")
    if fields.get("Dateiname-Name") and not _placeholder(fields.get("Dateiname-Name")) and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9][A-Za-z0-9.-]*", fields["Dateiname-Name"]):
        errors.append("Dateiname-Name entspricht nicht dem Schema Nachname.Vorname.")
    order = read_json(order_path) if order_path else None
    logistics = (order or {}).get("bewerbungslogistik") or {}
    choices = (("Gewünschte Stellenart", "stellenart"), ("Gewünschtes Arbeitsmodell", "arbeitsmodell"), ("Wunschgehalt verwenden", "wunschgehaltVerwenden"), ("Gehaltslogik", "gehaltslogik"))
    resolved = {}
    used_order = False
    for field, key in choices:
        order_value = str(logistics.get(key, ""))
        value = order_value if not _unresolved(order_value) else fields.get(field, "")
        used_order = used_order or (value == order_value and bool(value))
        resolved[key] = value
        if _unresolved(value):
            destination = errors if args.get("ungeklaerte_logistik_als_fehler") else warnings
            destination.append("Zentrale Bewerbungslogistik ist nicht eindeutig festgelegt: %s" % field)
        else:
            oks.append("Bewerbungslogistik ist gepflegt: %s" % field)
    optional = ("Frühester Eintrittstermin", "Gewünschter Stundenumfang", "Gewünschte Region", "Maximale Pendeldistanz", "Reisebereitschaft", "Schicht- oder Wochenendbereitschaft", "Befristung", "Umzugsbereitschaft", "Wunschgehalt manuell", "Gehaltsmodell", "Gehaltsregion")
    for name in optional:
        if name in fields and _placeholder(fields[name]):
            warnings.append("Optionales Feld enthält Beispieltext: %s" % name)
    for value in errors:
        ctx.error(value)
    for value in warnings:
        ctx.warning(value)
    for value in oks:
        ctx.ok(value)
    if report_path is not None:
        states = {name: "platzhalter_oder_leer" if _placeholder(value) else "nicht_festgelegt" if _unresolved(value) else "gepflegt" for name, value in fields.items()}
        report = {
            "schemaVersion": 2, "checkedAtUtc": utc_now(), "source": str(master), "applicationOrder": str(order_path) if order_path else None,
            "logisticsSource": "bewerbungsauftrag_mit_stammdaten_fallback" if used_order else "stammdaten",
            "resolvedCoreLogistics": resolved, "status": "fehler" if errors else "warnung" if warnings else "ok",
            "errors": errors, "warnings": warnings, "oks": oks, "fieldStates": states,
        }
        write_atomic_json(report_path, report)
    ctx.out("Zusammenfassung: OK=%d, Warnungen=%d, Fehler=%d" % (len(oks), len(warnings), len(errors)))
    if errors or (warnings and args.get("warnungen_als_fehler")):
        return 1
    ctx.out("ERGEBNIS: OK")
    return 0


def _valid_iso(value: Any) -> bool:
    if not isinstance(value, str) or not value:
        return False
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


def _forbidden_chat_fields(value: Any, path: str = "$") -> List[str]:
    found = []
    if isinstance(value, dict):
        for key, item in value.items():
            current = path + "." + str(key)
            if str(key).lower() in ("chat", "chatverlauf", "rawchat", "rohchat", "conversation", "messages", "prompt"):
                found.append(current)
            found.extend(_forbidden_chat_fields(item, current))
    elif isinstance(value, list):
        for index, item in enumerate(value):
            found.extend(_forbidden_chat_fields(item, "%s[%d]" % (path, index)))
    return found


def validate_dialog_order(order: Mapping[str, Any], for_creation: bool = False) -> List[str]:
    errors: List[str] = []
    schema = order.get("schemaVersion")
    if not isinstance(schema, int) or isinstance(schema, bool) or schema < 1:
        return ["Bewerbungsauftrag enthält keine gültige positive schemaVersion."]
    if schema <= 3:
        return []
    if schema not in (4, 5):
        return ["Nicht unterstützte Bewerbungsauftrag-Schemaversion: %s" % schema]
    for path in _forbidden_chat_fields(order):
        errors.append("Verbotenes Rohchatfeld im Bewerbungsauftrag: %s" % path)
    scope = order.get("dokumentumfang")
    if not isinstance(scope, dict):
        errors.append("Schema %s erfordert dokumentumfang." % schema)
    else:
        selection = scope.get("auswahl")
        if selection not in ("A", "B", "C", "D", "E"):
            errors.append("dokumentumfang.auswahl muss A, B, C, D oder E sein.")
        if scope.get("lebenslauf") not in ("individuell", "universal_unveraendert", "nicht_enthalten"):
            errors.append("dokumentumfang.lebenslauf ist ungültig.")
        for field in ("anschreiben", "emailNachricht", "bestaetigt", "emailAlleinBestaetigt"):
            if type(scope.get(field)) is not bool:
                errors.append("dokumentumfang.%s muss ein JSON-Boolean sein." % field)
        if scope.get("bestaetigt") is not True:
            errors.append("dokumentumfang.bestaetigt muss true sein.")
        if not _valid_iso(scope.get("bestaetigtAtUtc")):
            errors.append("dokumentumfang.bestaetigtAtUtc muss ein gültiger ISO-Zeitstempel sein.")
        if scope.get("lebenslauf") == "nicht_enthalten" and not scope.get("anschreiben") and not scope.get("emailNachricht"):
            errors.append("dokumentumfang darf nicht alle Dokumente ausschließen.")
        if scope.get("lebenslauf") == "nicht_enthalten" and not scope.get("anschreiben") and scope.get("emailNachricht") and scope.get("emailAlleinBestaetigt") is not True:
            errors.append("Ein reiner E-Mail-Umfang erfordert emailAlleinBestaetigt=true.")
        fixed = {
            "A": ("komplette_bewerbung", "individuell", True, True, "vollbewerbung"),
            "B": ("anschreiben_mit_universalem_lebenslauf", "universal_unveraendert", True, True, "anschreiben_mit_universalem_lebenslauf"),
            "C": ("individueller_lebenslauf", "individuell", False, False, "individuelle_auswahl"),
            "D": ("nur_anschreiben", "nicht_enthalten", True, False, "individuelle_auswahl"),
        }
        if selection in fixed:
            code, cv, letter, email, mode = fixed[selection]
            if (scope.get("kennung"), scope.get("lebenslauf"), scope.get("anschreiben"), scope.get("emailNachricht"), order.get("dokumentmodus")) != (code, cv, letter, email, mode):
                errors.append("dokumentumfang entspricht nicht der verbindlichen Abbildung für Auswahl %s." % selection)
        elif selection == "E" and scope.get("kennung") != "eigene_zusammenstellung":
            errors.append("dokumentumfang.kennung muss für Auswahl E eigene_zusammenstellung sein.")
    dialog = order.get("dialog")
    if not isinstance(dialog, dict):
        return errors + ["Schema %s erfordert dialog." % schema]
    if dialog.get("schemaVersion") != 1:
        errors.append("dialog.schemaVersion muss 1 sein.")
    status = dialog.get("status")
    allowed_statuses = ("profilabgleich_ausstehend", "rueckfragen_offen", "speicherentscheidung_offen", "bereit_zur_dokumenterstellung", "dokumenterstellung", "abgeschlossen")
    if status not in allowed_statuses:
        errors.append("dialog.status ist ungültig: %s" % status)
    if not isinstance(dialog.get("rueckfragen"), list):
        errors.append("dialog.rueckfragen fehlt oder ist keine Liste.")
    if not isinstance(dialog.get("angaben"), list):
        errors.append("dialog.angaben fehlt oder ist keine Liste.")
    if not _valid_iso(dialog.get("updatedAtUtc")):
        errors.append("dialog.updatedAtUtc muss ein gültiger ISO-Zeitstempel sein.")
    ids = set()
    blocking = []
    pending = []
    contradictions = []
    round_counts: Dict[int, int] = {}
    facts_by_id: Dict[str, Mapping[str, Any]] = {}
    for question in dialog.get("rueckfragen") or []:
        if not isinstance(question, dict):
            errors.append("dialog.rueckfragen enthält einen leeren Eintrag.")
            continue
        identifier = question.get("id")
        if not isinstance(identifier, str) or not TECHNICAL_ID.fullmatch(identifier):
            errors.append("Rückfrage besitzt keine gültige technische ID: %s" % identifier)
            continue
        if identifier in ids:
            errors.append("Dialog-ID ist nicht eindeutig: %s" % identifier)
        ids.add(identifier)
        question_status = question.get("status")
        question_type = question.get("art")
        if question_status not in ("offen", "beantwortet", "entfallen"):
            errors.append("Rückfrage '%s' hat einen ungültigen Status." % identifier)
        if question_type not in ("informationsluecke", "praezisierung", "speicherentscheidung", "widerspruch", "email_only_gate"):
            errors.append("Rückfrage '%s' hat eine ungültige art." % identifier)
        if not isinstance(question.get("frage"), str) or not question.get("frage", "").strip():
            errors.append("Rückfrage '%s' enthält keinen Fragetext." % identifier)
        round_value = question.get("runde")
        if not isinstance(round_value, int) or isinstance(round_value, bool) or round_value < 1:
            errors.append("Rückfrage '%s' benötigt runde als positive Ganzzahl." % identifier)
        else:
            round_counts[round_value] = round_counts.get(round_value, 0) + 1
        blocks = question.get("blockiertDokumenterstellung")
        if type(blocks) is not bool:
            errors.append("Rückfrage '%s': blockiertDokumenterstellung muss ein JSON-Boolean sein." % identifier)
        elif question_status == "offen" and blocks:
            blocking.append(identifier)
        elif question_status != "offen" and blocks:
            errors.append("Rückfrage '%s' darf nach Abschluss nicht blockieren." % identifier)
        if question.get("widerspruch") is True and question.get("widerspruchGeklaert") is not True and question_status != "entfallen":
            contradictions.append(identifier)
    for round_value, count in round_counts.items():
        if count > 3:
            errors.append("Dialogrunde %s enthält %s Rückfragen; erlaubt sind höchstens 3." % (round_value, count))
    for fact in dialog.get("angaben") or []:
        if not isinstance(fact, dict):
            errors.append("dialog.angaben enthält einen leeren Eintrag.")
            continue
        identifier = fact.get("id")
        if not isinstance(identifier, str) or not TECHNICAL_ID.fullmatch(identifier):
            errors.append("Dialogangabe besitzt keine gültige technische ID: %s" % identifier)
            continue
        if identifier in ids:
            errors.append("Dialog-ID ist nicht eindeutig: %s" % identifier)
        ids.add(identifier)
        facts_by_id[identifier] = fact
        decision = fact.get("speicherentscheidung")
        if decision not in ("ausstehend", "nur_auftrag", "dauerhaft"):
            errors.append("Dialogangabe '%s' hat eine ungültige speicherentscheidung." % identifier)
        if decision == "ausstehend":
            pending.append(identifier)
        truth = fact.get("wahrheitsstatus")
        if truth not in ("unbestaetigt", "bestaetigt", "widerspruechlich", "nicht_verwendbar"):
            errors.append("Dialogangabe '%s' hat einen ungültigen wahrheitsstatus." % identifier)
        if fact.get("widerspruch") is True and fact.get("widerspruchGeklaert") is not True:
            contradictions.append(identifier)
        update = fact.get("profilaktualisierung")
        if not isinstance(update, dict) or update.get("status") not in ("ausstehend", "nicht_geaendert", "aktualisiert", "bereits_vorhanden"):
            errors.append("Dialogangabe '%s' enthält keine gültige profilaktualisierung." % identifier)
        elif decision == "nur_auftrag" and update.get("status") != "nicht_geaendert":
            errors.append("Dialogangabe '%s' mit nur_auftrag muss profilaktualisierung.status nicht_geaendert verwenden." % identifier)
        elif decision == "dauerhaft" and (truth != "bestaetigt" or update.get("status") not in ("aktualisiert", "bereits_vorhanden")):
            errors.append("Dialogangabe '%s' besitzt keinen gültigen dauerhaften Profilnachweis." % identifier)
    if pending and status != "speicherentscheidung_offen":
        errors.append("Ausstehende Speicherentscheidungen erfordern dialog.status speicherentscheidung_offen.")
    if not pending and status == "speicherentscheidung_offen":
        errors.append("dialog.status speicherentscheidung_offen erfordert eine ausstehende Speicherentscheidung.")
    if (blocking or contradictions) and status != "rueckfragen_offen" and not pending:
        errors.append("Blockierende Rückfragen oder Widersprüche erfordern dialog.status rueckfragen_offen.")
    if status in ("bereit_zur_dokumenterstellung", "dokumenterstellung", "abgeschlossen") and (blocking or contradictions or pending):
        errors.append("dialog.status %s ist mit offenen Blockern nicht konsistent." % status)
    if for_creation and status not in ("bereit_zur_dokumenterstellung", "dokumenterstellung", "abgeschlossen"):
        errors.append("Dokumenterstellung ist mit dialog.status '%s' nicht zulässig." % status)
    return errors


def handle_dialog_pruefen(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    order_path = Path(args["auftrag_path"])
    work = infer_work_context(order_path.parent, universal=False).work
    order = read_json(safe_path(order_path, work, must_exist=True, kind="file"))
    errors = validate_dialog_order(order, bool(args.get("fuer_dokumenterstellung")))
    for message in errors:
        ctx.error(message)
    if errors:
        return 1
    if order.get("schemaVersion", 0) <= 3:
        ctx.ok("Legacy-Bewerbungsauftrag akzeptiert; Dialogstatus ist nicht verpflichtend.")
    else:
        ctx.ok("Dialogstatus und Dokumentumfang sind konsistent.")
    return 0


def _complete_storage(dialog: MutableMapping[str, Any], fact_id: str) -> None:
    facts = dialog.get("angaben") or []
    questions = dialog.get("rueckfragen") or []
    linked = []
    for question in questions:
        if question.get("art") == "speicherentscheidung" and question.get("status") == "offen" and fact_id in (question.get("angabeIds") or []):
            linked.append(question)
            all_done = True
            for linked_id in question.get("angabeIds") or []:
                matches = [fact for fact in facts if fact.get("id") == linked_id]
                if len(matches) != 1 or matches[0].get("speicherentscheidung") == "ausstehend":
                    all_done = False
            if all_done:
                question.update(status="beantwortet", antwortZusammenfassung="Speicherentscheidung abgeschlossen", blockiertDokumenterstellung=False, widerspruch=False, widerspruchGeklaert=True)
    if len(linked) != 1:
        raise ContractError("Dialogangabe '%s' muss mit genau einer offenen Speicherfrage verknüpft sein; gefunden: %d." % (fact_id, len(linked)))
    pending = any(fact.get("speicherentscheidung") == "ausstehend" for fact in facts)
    blocking = any(question.get("status") == "offen" and question.get("blockiertDokumenterstellung") is True for question in questions)
    contradiction = any(question.get("status") != "entfallen" and question.get("widerspruch") is True and question.get("widerspruchGeklaert") is not True for question in questions)
    dialog["status"] = "speicherentscheidung_offen" if pending else "rueckfragen_offen" if blocking or contradiction else "bereit_zur_dokumenterstellung"


def _update_markdown_section(text: str, section: str, formulation: str) -> Tuple[str, bool]:
    section = section.strip().lstrip("#").strip()
    if not section or "\n" in section or "\r" in section:
        raise ContractError("Abschnitt muss eine einzelne Markdown-Überschrift bezeichnen.")
    if formulation in text.splitlines():
        return text, True
    pattern = re.compile(r"(?m)^(#{1,6})\s+" + re.escape(section) + r"\s*$")
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise ContractError("Zielabschnitt muss genau einmal als Markdown-Überschrift vorhanden sein: %s" % section)
    start = matches[0].end()
    next_heading = re.search(r"(?m)^#{1,%d}\s+" % len(matches[0].group(1)), text[start:])
    end = start + next_heading.start() if next_heading else len(text)
    insertion = "\n\n" + formulation.strip() + "\n"
    return text[:end].rstrip() + insertion + text[end:].lstrip("\r\n"), False


def handle_dialog_uebernehmen(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    order_path = Path(args["auftrag_path"])
    work = infer_work_context(order_path.parent, universal=False).work
    order_path = safe_path(order_path, work, must_exist=True, kind="file")
    order = read_json(order_path)
    validation = validate_dialog_order(order)
    if validation:
        raise ContractError("Bewerbungsauftrag ist vor der Übernahme ungültig: %s" % validation[0])
    if order.get("schemaVersion") not in (4, 5):
        raise ContractError("Dialogangaben können nur in Schema 4 oder 5 übernommen werden.")
    identifier = str(args["angabe_id"])
    if not TECHNICAL_ID.fullmatch(identifier):
        raise ContractError("Angabe-ID besitzt kein gültiges technisches Format.")
    dialog = order["dialog"]
    matches = [fact for fact in dialog["angaben"] if fact.get("id") == identifier]
    if len(matches) != 1:
        raise ContractError("Dialogangabe wurde nicht eindeutig gefunden: %s" % identifier)
    fact = matches[0]
    decision = str(args["speicherentscheidung"])
    existing = fact.get("speicherentscheidung")
    update = fact.get("profilaktualisierung") or {}
    if decision == "nur_auftrag":
        forbidden = ("profil_path", "abschnitt", "formulierung", "erwarteter_datei_hash", "zustimmung_bestaetigt")
        if any(args.get(key) for key in forbidden):
            raise ContractError("nur_auftrag darf keine Profil-, Formulierungs-, Hash- oder Zustimmungsparameter erhalten.")
        if existing == "dauerhaft":
            raise ContractError("Eine dauerhaft verarbeitete Angabe kann nicht zurückgestuft werden.")
        if existing == "nur_auftrag" and update.get("status") == "nicht_geaendert":
            ctx.ok("Dialogangabe ist bereits ausschließlich für diesen Auftrag markiert: %s" % identifier)
            return 0
        if existing != "ausstehend" or update.get("status") != "ausstehend" or dialog.get("status") != "speicherentscheidung_offen":
            raise ContractError("Eine neue auftragsbezogene Speicherentscheidung erfordert ausstehend/ausstehend und den passenden Dialogstatus.")
        fact["speicherentscheidung"] = "nur_auftrag"
        fact["profilaktualisierung"] = {"status": "nicht_geaendert"}
        _complete_storage(dialog, identifier)
        dialog["updatedAtUtc"] = utc_now()
        with file_lock(order_path):
            write_atomic_json(order_path, order)
        ctx.ok("Dialogangabe wird nur für diesen Auftrag verwendet; keine Profildatei wurde verändert: %s" % identifier)
        return 0

    if fact.get("wahrheitsstatus") != "bestaetigt" or (fact.get("widerspruch") is True and fact.get("widerspruchGeklaert") is not True):
        raise ContractError("Dauerhafte Profilübernahme erfordert eine bestätigte, widerspruchsfreie Wahrheitsebene.")
    for key in ("profil_path", "abschnitt", "formulierung", "erwarteter_datei_hash"):
        if not args.get(key):
            raise ContractError("Dauerhafte Profilübernahme erfordert --%s." % key.replace("_", "-"))
    if not args.get("zustimmung_bestaetigt"):
        raise ContractError("Dauerhafte Profilübernahme erfordert --zustimmung-bestaetigt.")
    expected_hash = str(args["erwarteter_datei_hash"]).upper()
    if not SHA256.fullmatch(expected_hash):
        raise ContractError("Erwarteter Datei-Hash muss 64 Hexadezimalzeichen besitzen.")
    project = infer_work_context(work, universal=False).applications_root.parent.parent
    allowed = {
        project / "Private/Daten/01_PERSOENLICHE_DATEN.md": "Private/Daten/01_PERSOENLICHE_DATEN.md",
        project / "Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md": "Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md",
    }
    profile_input = Path(args["profil_path"])
    profile_path = Path(os.path.abspath(str(profile_input)))
    if profile_path not in allowed:
        raise UnsafePathError("Profilpfad muss exakt eine der beiden privaten Profildateien bezeichnen.")
    profile_path = safe_path(profile_path, project / "Private/Daten", must_exist=True, kind="file")
    stored_path = str(update.get("datei", "")).replace("\\", "/")
    section = str(args["abschnitt"]).strip().lstrip("#").strip()
    formulation = str(args["formulierung"]).strip()
    if "\n" in formulation or "\r" in formulation or not formulation:
        raise ContractError("Formulierung muss eine einzelne nichtleere Zeile sein.")
    if stored_path != allowed[profile_path] or update.get("abschnitt") != section or update.get("vorgeschlageneFormulierung") != formulation:
        raise ContractError("Profilziel, Abschnitt oder Formulierung weicht vom offengelegten Ziel ab.")
    if str(update.get("vorherSha256", "")).upper() != expected_hash:
        raise ContractError("Erwarteter Datei-Hash weicht vom gespeicherten Vorher-Hash ab.")
    if sha256_file(profile_path) != expected_hash:
        raise ContractError("Profildatei wurde seit der Bestätigung verändert.")
    original_profile = profile_path.read_bytes()
    original_order_hash = sha256_file(order_path)
    new_text, already = _update_markdown_section(read_text(profile_path), section, formulation)
    new_bytes = (new_text if new_text.endswith("\n") else new_text + "\n").encode("utf-8")
    after_hash = sha256_bytes(new_bytes)
    now = utc_now()
    fact["speicherentscheidung"] = "dauerhaft"
    fact["profilaktualisierung"] = {
        "status": "bereits_vorhanden" if already else "aktualisiert", "datei": stored_path, "abschnitt": section,
        "vorgeschlageneFormulierung": formulation, "fachlicherZieltyp": update.get("fachlicherZieltyp"),
        "bestaetigteFormulierung": formulation, "zugestimmtAtUtc": now, "vorherSha256": expected_hash,
        "nachherSha256": after_hash, "aktualisiertAtUtc": now,
    }
    _complete_storage(dialog, identifier)
    dialog["updatedAtUtc"] = now
    with file_lock(order_path):
        if sha256_file(order_path) != original_order_hash or sha256_file(profile_path) != expected_hash:
            raise ContractError("Dateien wurden zwischen Prüfung und Commit verändert.")
        try:
            write_atomic_bytes(profile_path, new_bytes)
            write_atomic_json(order_path, order)
        except Exception:
            write_atomic_bytes(profile_path, original_profile)
            raise
    ctx.ok("Bestätigte Dialogangabe wurde dauerhaft übernommen: %s" % identifier)
    return 0


# Kept at module level so optional browser handlers can override individual
# names without importing private implementation details.
CORE_HANDLERS: Dict[str, Handler] = {
    "diagnose": handle_diagnose,
    "neu": handle_neu,
    "universal-neu": handle_universal_neu,
    "universal-status": handle_universal_status,
    "status": handle_status,
    "checkpoint": handle_checkpoint,
    "migrieren": handle_migrieren,
    "stammdaten": handle_stammdaten,
    "dialog-pruefen": handle_dialog_pruefen,
    "dialog-uebernehmen": handle_dialog_uebernehmen,
}


def _png_dimensions(data: bytes) -> Tuple[int, int]:
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR" or struct.unpack(">I", data[8:12])[0] != 13:
        raise ContractError("Passfoto.png ist keine gültige PNG-Datei.")
    width, height = struct.unpack(">II", data[16:24])
    if width < 1 or height < 1:
        raise ContractError("Passfoto.png enthält keine gültigen Bildmaße.")
    return width, height


def _photo_tags(value: str) -> List[str]:
    return [tag for tag in re.findall(r"(?is)<img\b[^>]*>", value) if re.search(r"(?is)\bclass\s*=\s*(['\"])[^'\"]*\bbewerbungsfoto\b[^'\"]*\1", tag)]


def _update_photo_html(value: str, photo: Optional[bytes]) -> str:
    start, end = "<!-- passfoto:start -->", "<!-- passfoto:end -->"
    pattern = re.compile(re.escape(start) + r"(?s:.*?)" + re.escape(end))
    matches = list(pattern.finditer(value))
    if len(matches) > 1:
        raise ContractError("Der Lebenslauf enthält mehr als einen markierten Passfoto-Block.")
    if not matches:
        tags = _photo_tags(value)
        if photo is None and not tags:
            return value
        if photo is not None and len(tags) == 1:
            source = re.search(r"(?is)\bsrc\s*=\s*['\"]data:image/png;base64,([^'\"]+)['\"]", tags[0])
            if source:
                try:
                    if base64.b64decode(source.group(1), validate=True) == photo:
                        return value
                except ValueError:
                    pass
        raise ContractError("Der markierte Passfoto-Block fehlt oder die vorhandene Einbettung ist nicht bytegleich.")
    newline = "\r\n" if "\r\n" in value else "\n"
    content = newline
    if photo is not None:
        uri = base64.b64encode(photo).decode("ascii")
        content += "  <figure class=\"bewerbungsfoto-rahmen\" aria-hidden=\"true\">" + newline
        content += "    <img class=\"bewerbungsfoto\" src=\"data:image/png;base64,%s\" alt=\"\">" % uri + newline
        content += "  </figure>" + newline
    updated = pattern.sub(start + content + end, value, count=1)
    tags = _photo_tags(updated)
    if photo is None and tags:
        raise ContractError("Lebenslauf enthält trotz fehlender Quelle ein Bewerbungsfoto.")
    if photo is not None:
        if len(tags) != 1:
            raise ContractError("Lebenslauf muss genau ein eingebettetes Bewerbungsfoto enthalten.")
        match = re.search(r"(?is)data:image/png;base64,([^'\"]+)", tags[0])
        if not match or base64.b64decode(match.group(1), validate=True) != photo:
            raise ContractError("Eingebettetes Bewerbungsfoto ist nicht bytegleich.")
    return updated


def handle_passfoto(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    paths = infer_work_context(Path(args["arbeitsordner"]), universal=False)
    order = read_json(paths.work / "Bewerbungsauftrag.json")
    scope = document_scope(order)
    if scope["lebenslauf"] == "universal_unveraendert":
        raise ContractError("Ein universeller Lebenslauf ist ein unveränderter SHA-256-Snapshot.")
    if scope["lebenslauf"] != "individuell":
        raise ContractError("Bewerbungsauftrag enthält keinen individuellen Lebenslauf.")
    files = [item for item in paths.candidate.glob("Lebenslauf - *.html") if item.is_file() and not item.is_symlink()]
    if len(files) != 1:
        raise ContractError("Für die Passfoto-Integration wird genau ein Kandidaten-Lebenslauf erwartet; gefunden: %d." % len(files))
    data_root = safe_path(paths.applications_root.parent / "Daten", paths.applications_root.parent, must_exist=True, kind="dir")
    variants = [item.name for item in data_root.iterdir() if item.is_file() and item.name.lower() == "passfoto.png" and item.name != "Passfoto.png"]
    if variants:
        raise ContractError("Das optionale Foto muss exakt Passfoto.png heißen; gefunden: %s" % ", ".join(variants))
    photo_path = data_root / "Passfoto.png"
    photo = None
    dimensions = None
    if photo_path.exists():
        photo_path = safe_path(photo_path, data_root, must_exist=True, kind="file")
        photo = photo_path.read_bytes()
        dimensions = _png_dimensions(photo)
    cv = safe_path(files[0], paths.candidate, must_exist=True, kind="file")
    original = read_text(cv)
    updated = _update_photo_html(original, photo)
    if updated != original:
        write_atomic_text(cv, updated)
    if photo is None:
        ctx.ok("Passfoto-Status: nicht_vorhanden; der Lebenslauf bleibt ohne Foto.")
    else:
        ctx.ok("Passfoto-Status: eingebettet (%dx%d Pixel, SHA-256 gebunden)." % dimensions)
    return 0


def _merge_ranges(records: Iterable[Mapping[str, Any]], padding: int = 2) -> List[Dict[str, int]]:
    ranges = []
    for record in records:
        try:
            start, end = int(record.get("zeileVon", 0)), int(record.get("zeileBis", 0))
        except (TypeError, ValueError):
            continue
        if start >= 1 and end >= start:
            ranges.append({"zeileVon": max(1, start - padding), "zeileBis": end + padding})
    ranges.sort(key=lambda item: (item["zeileVon"], item["zeileBis"]))
    merged: List[Dict[str, int]] = []
    for item in ranges:
        if not merged or item["zeileVon"] > merged[-1]["zeileBis"] + 1:
            merged.append(dict(item))
        else:
            merged[-1]["zeileBis"] = max(merged[-1]["zeileBis"], item["zeileBis"])
    return merged


def handle_kontext(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    paths = infer_work_context(Path(args["arbeitsordner"]), universal=False)
    matrix_path = safe_path(paths.work / "Anforderungsmatrix.json", paths.work, must_exist=True, kind="file")
    index_path = safe_path(paths.work / "Evidenzindex.json", paths.work, must_exist=True, kind="file")
    order_path = safe_path(paths.work / "Bewerbungsauftrag.json", paths.work, must_exist=True, kind="file")
    job_path = safe_path(paths.candidate / "Stellenbeschreibung.md", paths.candidate, must_exist=True, kind="file")
    profile_path = Path(args.get("profil_path") or paths.applications_root.parent / "Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md")
    profile_path = safe_path(profile_path, paths.applications_root.parent / "Daten", must_exist=True, kind="file")
    matrix, index, order = read_json(matrix_path), read_json(index_path), read_json(order_path)
    reasons = []
    if matrix.get("schemaVersion") != 5:
        reasons.append("legacy_matrix")
    if index.get("schemaVersion") != 1:
        reasons.append("unsupported_evidence_index")
    reasons.append("rollout_deaktiviert")  # canonical mode remains full context
    requirements = [item for item in matrix.get("requirements", []) if isinstance(item, dict)]
    recruiter = matrix.get("recruiterStrategie") or {}
    letter = matrix.get("anschreibenStrategie") or {}
    highlights = [item for item in recruiter.get("profilHighlights", []) if isinstance(item, dict)]
    arguments = [item for item in letter.get("argumente", []) if isinstance(item, dict)]
    omissions = [item for item in recruiter.get("auslassungen", []) if isinstance(item, dict)]
    requirement_ids = [str(item.get("id")) for item in requirements if item.get("id")]
    evidence_ids = sorted(set(str(value) for item in requirements + highlights + arguments + omissions for value in item.get("belegRefIds", []) if value))
    job_ids = sorted(set(str(value) for item in requirements + arguments for value in item.get("stellenFundstellen", []) if value))
    source_ids = sorted(set(str(value) for item in arguments for value in item.get("externeQuellenIds", []) if value))
    evidence_by_id = {str(item.get("id")): item for item in index.get("belege", []) if isinstance(item, dict) and item.get("id")}
    anchors_by_id = {str(item.get("id")): item for item in (matrix.get("stellenanzeigeAbdeckung") or {}).get("fundstellen", []) if isinstance(item, dict) and item.get("id")}
    for identifier in evidence_ids:
        if identifier not in evidence_by_id:
            reasons.append("unbekannte_evidenz:" + identifier)
    for identifier in job_ids:
        if identifier not in anchors_by_id:
            reasons.append("unbekannte_fundstelle:" + identifier)
    profile_ranges = _merge_ranges(evidence_by_id[item] for item in evidence_ids if item in evidence_by_id and evidence_by_id[item].get("quelle") == "profil")
    job_ranges = _merge_ranges(anchors_by_id[item] for item in job_ids if item in anchors_by_id)
    scope = document_scope(order)
    contexts = []
    for purpose in ("lebenslauf", "anschreiben", "email_nachricht", "qualitaetspruefung"):
        selected = purpose == "qualitaetspruefung" or purpose == "lebenslauf" and scope["lebenslauf"] != "nicht_enthalten" or purpose == "anschreiben" and scope["anschreiben"] or purpose == "email_nachricht" and scope["emailNachricht"]
        if selected:
            contexts.append({"zweck": purpose, "anforderungIds": requirement_ids, "belegIds": evidence_ids, "stellenFundstellenIds": job_ids, "externeQuellenIds": source_ids, "profilBereiche": profile_ranges, "stellenBereiche": job_ranges, "dialogAngabeIds": [item for item in evidence_ids if item in evidence_by_id and evidence_by_id[item].get("quelle") == "auftrag_angabe"]})
    sources = {name: artifact_record(path, paths.work) if path.is_relative_to(paths.work) else {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256_file(path)} for name, path in (("anforderungsmatrix", matrix_path), ("evidenzindex", index_path), ("auftrag", order_path), ("stellenbeschreibung", job_path), ("profil", profile_path))}
    manifest = {
        "schemaVersion": 1, "kind": "kontextmanifest", "mode": "vollkontext",
        "status": "evidenzbasiert_bereit" if not reasons else "vollkontext_erforderlich", "generatedAtUtc": utc_now(),
        "sources": sources, "documentContexts": contexts,
        "exclusions": [{"belegRefIds": item.get("belegRefIds", []), "begruendung": str(item.get("begruendung", ""))} for item in omissions],
        "fallbackReasons": reasons,
    }
    target = safe_path(Path(args.get("bericht_path") or paths.work / "Kontextmanifest.json"), paths.work)
    write_atomic_json(target, manifest)
    ctx.out("Kontextmanifest: %s (%s)" % (target, manifest["status"]))
    return 0


def _candidate_document_folders(folder: Path) -> Tuple[Path, Path, bool]:
    internal, shipping = folder / "Intern", folder / "Versand"
    structured = internal.is_dir() and shipping.is_dir()
    return (internal if structured else folder, shipping if structured else folder, structured)


def _selected_files(folder: Path, pattern: str) -> List[Path]:
    return sorted(item for item in folder.glob(pattern) if item.is_file() and not item.is_symlink())


def _html_page_count(value: str) -> int:
    return len(re.findall(r"(?is)<(?:main|section|div)\b[^>]*\bclass\s*=\s*(['\"])[^'\"]*\bpage\b[^'\"]*\1", value))


def _static_html_errors(path: Path, kind: str) -> List[str]:
    value = read_text(path)
    errors = []
    if PLACEHOLDER.search(value):
        errors.append("%s enthält sichtbare Platzhalter oder Entwurfsmarker." % path.name)
    if not re.search(r"(?is)<!doctype\s+html>", value) or not re.search(r"(?is)<html\b[^>]*\blang\s*=\s*['\"]de['\"]", value):
        errors.append("%s besitzt keine vollständige deutschsprachige HTML-Struktur." % path.name)
    if not re.search(r"(?is)@page\s*\{[^}]*\bsize\s*:\s*A4\s*;[^}]*\bmargin\s*:\s*0(?:mm|cm|px)?\s*;", value):
        errors.append("%s enthält nicht den verbindlichen @page-A4-Vertrag." % path.name)
    page_rule = re.search(r"(?is)\.page\s*\{(?P<body>[^}]*)}", value)
    if not page_rule or not re.search(r"(?i)\bwidth\s*:\s*210mm\s*;", page_rule.group("body")) or not re.search(r"(?i)\bheight\s*:\s*297mm\s*;", page_rule.group("body")):
        errors.append("%s benötigt .page mit width: 210mm und height: 297mm." % path.name)
    if re.search(r"(?is)<script\b|@import\b|<link\b|\b(?:src|href)\s*=\s*['\"](?:https?:|file:|//)", value):
        errors.append("%s lädt Skripte oder externe/lokale Ressourcen." % path.name)
    pages = _html_page_count(value)
    if kind == "anschreiben" and pages != 1:
        errors.append("Anschreiben muss genau eine explizite A4-Seite enthalten; gefunden: %d." % pages)
    if kind == "lebenslauf" and pages not in (1, 2):
        errors.append("Lebenslauf muss ein oder zwei explizite A4-Seiten enthalten; gefunden: %d." % pages)
    return errors


def handle_pruefen(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    folder = Path(args["ordner"])
    if not folder.is_dir() or folder.is_symlink():
        raise UnsafePathError("--ordner muss auf ein reguläres Verzeichnis zeigen.")
    order = None
    if args.get("auftrag_path"):
        order_path = Path(args["auftrag_path"])
        paths = infer_work_context(order_path.parent, universal=None)
        work = paths.work
        order = read_json(safe_path(order_path, work, must_exist=True, kind="file"))
        folder = safe_path(folder, paths.applications_root, must_exist=True, kind="dir")
    document_folder, email_folder, structured = _candidate_document_folders(folder)
    scope = document_scope(order) if order else {"lebenslauf": "individuell", "anschreiben": True, "emailNachricht": True}
    errors: List[str] = []
    warnings: List[str] = []
    applicant = str((order or {}).get("bewerberDateiname", "*"))
    company_slug = str((order or {}).get("firmaSlug", "*"))
    expected_sets = (
        (scope["lebenslauf"] != "nicht_enthalten", "Lebenslauf - %s.html" % applicant, "Lebenslauf"),
        (bool(scope["anschreiben"]), "Anschreiben - %s.html" % applicant, "Anschreiben"),
        (bool(scope["emailNachricht"]), "Email-Nachricht--%s.md" % company_slug, "E-Mail"),
    )
    for selected, exact, label in expected_sets:
        base = email_folder if label == "E-Mail" else document_folder
        matches = _selected_files(base, exact)
        if selected and len(matches) != 1:
            errors.append("%s ist ausgewählt und muss exakt einmal als %s vorliegen." % (label, exact))
        if not selected and matches:
            errors.append("%s ist nicht ausgewählt, aber vorhanden." % label)
    for required in ("Stellenbeschreibung.md", "Analyse.md", "Qualitaetscheck.md", "Druck-Hinweis.md"):
        path = document_folder / required
        if not path.is_file() or path.is_symlink() or len(read_text(path).strip()) < 40:
            errors.append("Pflichtnachweis fehlt oder ist inhaltlich zu kurz: %s" % required)
    for path in _selected_files(document_folder, "*.html"):
        errors.extend(_static_html_errors(path, "lebenslauf" if path.name.startswith("Lebenslauf - ") else "anschreiben"))
    for path in list(document_folder.glob("*.md")) + ([] if email_folder == document_folder else list(email_folder.glob("*.md"))):
        if path.is_file() and not path.is_symlink() and PLACEHOLDER.search(read_text(path)):
            errors.append("%s enthält sichtbare Platzhalter oder Entwurfsmarker." % path.name)
    if scope["emailNachricht"]:
        email_files = _selected_files(email_folder, "Email-Nachricht--*.md")
        if len(email_files) == 1:
            text = read_text(email_files[0]).strip()
            first = text.splitlines()[0] if text else ""
            if not first.startswith("Betreff:") or len(first) <= len("Betreff:") or len(text) > 2500:
                errors.append("E-Mail benötigt einen konkreten Betreff in Zeile 1 und muss kurz bleiben.")
    if structured:
        manifest = folder / "Manifest.json"
        if not manifest.is_file():
            errors.append("Strukturierte Veröffentlichung benötigt Manifest.json.")
    for message in errors:
        ctx.error(message)
    for message in warnings:
        ctx.warning(message)
    if errors or (warnings and args.get("warnungen_als_fehler")):
        return 1
    ctx.ok("Statische Kandidatenprüfung bestanden.")
    return 0


def _html_text(value: str) -> str:
    value = re.sub(r"(?is)<(?:style|script)\b[^>]*>.*?</(?:style|script)>", " ", value)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"(?is)<[^>]+>", " ", value))).strip()


def _normalized(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("\u00a0", " ").replace("–", "-").replace("—", "-")).strip().lower()


def _document_texts(document_folder: Path, email_folder: Path) -> Dict[str, str]:
    result = {"lebenslauf": "", "anschreiben": "", "email_nachricht": ""}
    for kind, pattern, folder in (("lebenslauf", "Lebenslauf - *.html", document_folder), ("anschreiben", "Anschreiben - *.html", document_folder), ("email_nachricht", "Email-Nachricht--*.md", email_folder)):
        files = _selected_files(folder, pattern)
        if len(files) == 1:
            raw = read_text(files[0])
            result[kind] = _html_text(raw) if files[0].suffix == ".html" else raw
    return result


def _append_check(collection: List[str], message: str, ctx: CommandContext, kind: str) -> None:
    collection.append(message)
    getattr(ctx, kind)(message)


def handle_inhalt(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    order_path = Path(args["auftrag_path"])
    paths = infer_work_context(order_path.parent, universal=False)
    folder = safe_path(Path(args["ordner"]), paths.applications_root, must_exist=True, kind="dir")
    order_path = safe_path(order_path, paths.work, must_exist=True, kind="file")
    matrix_path = safe_path(Path(args["anforderungsmatrix_path"]), paths.work, must_exist=True, kind="file")
    data_root = safe_path(paths.applications_root.parent / "Daten", paths.applications_root.parent, must_exist=True, kind="dir")
    master = safe_path(Path(args.get("stammdaten_path") or data_root / "01_PERSOENLICHE_DATEN.md"), data_root, must_exist=True, kind="file")
    profile = safe_path(Path(args.get("profil_path") or data_root / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"), data_root, must_exist=True, kind="file")
    report_path = args.get("bericht_path")
    if report_path is not None:
        report_path = safe_path(Path(report_path), paths.work)
        if report_path in (order_path, matrix_path, master, profile):
            raise UnsafePathError("Berichtspfad darf keine Eingabedatei aliasieren.")
    order, matrix = read_json(order_path), read_json(matrix_path)
    scope = document_scope(order)
    schema = matrix.get("schemaVersion")
    if not isinstance(schema, int) or isinstance(schema, bool) or schema not in (1, 2, 3, 4, 5):
        raise ContractError("Anforderungsmatrix verwendet keine unterstützte schemaVersion 1 bis 5.")
    document_folder, email_folder, _ = _candidate_document_folders(folder)
    texts = _document_texts(document_folder, email_folder)
    errors: List[str] = []
    warnings: List[str] = []
    oks: List[str] = []
    expected = {
        "lebenslauf": scope["lebenslauf"] != "nicht_enthalten",
        "anschreiben": bool(scope["anschreiben"]),
        "email_nachricht": bool(scope["emailNachricht"]),
    }
    for kind, selected in expected.items():
        if selected and not texts[kind]:
            _append_check(errors, "%s ist ausgewählt, fehlt aber im Kandidatensatz." % kind, ctx, "error")
        elif not selected and texts[kind]:
            _append_check(errors, "%s ist nicht ausgewählt, aber im Kandidatensatz vorhanden." % kind, ctx, "error")
        else:
            oks.append("Dokumentumfang für %s ist konsistent." % kind)
    fields = _markdown_fields(master)
    applicant = fields.get("Vollständiger Name", "")
    combined = " ".join(texts.values())
    if applicant and expected["lebenslauf"] and _normalized(applicant) not in _normalized(texts["lebenslauf"]):
        _append_check(errors, "Vollständiger Bewerbername fehlt im Lebenslauf.", ctx, "error")
    if expected["anschreiben"]:
        for label, value in (("Firma", order.get("firma")), ("Zielrolle", order.get("rolle"))):
            if value and _normalized(str(value)) not in _normalized(texts["anschreiben"]):
                _append_check(errors, "%s ist im Anschreiben nicht sichtbar." % label, ctx, "error")
    requirements = [item for item in matrix.get("requirements", []) if isinstance(item, dict)]
    if not requirements:
        _append_check(errors, "Anforderungsmatrix enthält keine Anforderungen.", ctx, "error")

    evidence_coverage: Dict[str, Any] = {
        "applicable": schema >= 4, "matrixSchemaVersion": schema,
        "status": "ausstehend" if schema >= 4 else "legacy_oder_nicht_erforderlich",
        "stellenbeschreibungSha256": None, "evidenzindexSha256": None,
        "explicitJobSignalLines": [], "uncoveredJobSignalLines": [], "sourceAnchors": [], "profileEvidence": [],
    }
    recruiter_coverage: Dict[str, Any] = {"applicable": schema >= 3 and (expected["lebenslauf"] or expected["anschreiben"]), "status": "ausstehend" if schema >= 3 else "legacy_oder_nicht_erforderlich", "highlights": [], "transferBridges": [], "omissions": []}
    letter_coverage: Dict[str, Any] = {"applicable": schema >= 5 and expected["anschreiben"], "status": "ausstehend" if schema >= 5 and expected["anschreiben"] else "nicht_erforderlich" if schema >= 5 else "legacy_oder_nicht_erforderlich", "argumente": []}
    source_coverage: Dict[str, Any] = {"applicable": schema >= 5, "status": "ausstehend" if schema >= 5 else "legacy_oder_nicht_erforderlich", "sources": []}
    disposition: Dict[str, Any] = {"applicable": schema >= 5, "status": "ausstehend" if schema >= 5 else "legacy_oder_nicht_erforderlich", "used": [], "omitted": [], "unclassified": [], "conflicts": []}
    language_quality: Dict[str, Any] = {"applicable": expected["anschreiben"], "status": "ok" if expected["anschreiben"] else "nicht_erforderlich", "findings": [], "metrics": {}}

    evidence_by_id: Dict[str, Dict[str, Any]] = {}
    anchor_by_id: Dict[str, Dict[str, Any]] = {}
    if schema >= 4:
        job_path = safe_path(document_folder / "Stellenbeschreibung.md", document_folder, must_exist=True, kind="file")
        job_text = read_text(job_path)
        job_lines = job_text.splitlines()
        job_hash = sha256_file(job_path)
        evidence_coverage["stellenbeschreibungSha256"] = job_hash
        coverage = matrix.get("stellenanzeigeAbdeckung")
        if not isinstance(coverage, dict) or str(coverage.get("sourceSha256", "")).upper() != job_hash:
            _append_check(errors, "stellenanzeigeAbdeckung.sourceSha256 stimmt nicht mit der Stellenbeschreibung überein.", ctx, "error")
        else:
            for anchor in coverage.get("fundstellen", []):
                valid = isinstance(anchor, dict)
                identifier = str(anchor.get("id", "")) if valid else ""
                start, end = anchor.get("zeileVon") if valid else None, anchor.get("zeileBis") if valid else None
                if not TECHNICAL_ID.fullmatch(identifier) or identifier in anchor_by_id or type(start) is not int or type(end) is not int or start < 1 or end < start or end > len(job_lines):
                    valid = False
                if valid:
                    actual = " ".join(job_lines[start - 1:end])
                    if _normalized(actual) != _normalized(str(anchor.get("text", ""))):
                        valid = False
                if valid:
                    anchor_by_id[identifier] = anchor
                else:
                    _append_check(errors, "Ungültige oder nicht hashgebundene Stellen-Fundstelle: %s" % identifier, ctx, "error")
                evidence_coverage["sourceAnchors"].append({"id": identifier, "zeileVon": start, "zeileBis": end, "klassifikation": anchor.get("klassifikation") if isinstance(anchor, dict) else None, "anforderungIds": anchor.get("anforderungIds", []) if isinstance(anchor, dict) else [], "valid": valid})
            if not anchor_by_id:
                _append_check(errors, "stellenanzeigeAbdeckung enthält keine prüfbaren Fundstellen.", ctx, "error")
        index_path = safe_path(paths.work / "Evidenzindex.json", paths.work, must_exist=True, kind="file")
        evidence_index = read_json(index_path)
        if evidence_index.get("schemaVersion") != 1:
            _append_check(errors, "Evidenzindex verwendet nicht Schema 1.", ctx, "error")
        evidence_coverage["evidenzindexSha256"] = sha256_file(index_path)
        profile_lines = read_text(profile).splitlines()
        dialog_facts = {str(item.get("id")): item for item in (order.get("dialog") or {}).get("angaben", []) if isinstance(item, dict) and item.get("id")}
        has_profile = False
        has_dialog = False
        for evidence in evidence_index.get("belege", []):
            valid = isinstance(evidence, dict)
            identifier = str(evidence.get("id", "")) if valid else ""
            source = evidence.get("quelle") if valid else None
            if not TECHNICAL_ID.fullmatch(identifier) or identifier in evidence_by_id or source not in ("profil", "auftrag_angabe"):
                valid = False
            if valid and source == "profil":
                has_profile = True
                start, end = evidence.get("zeileVon"), evidence.get("zeileBis")
                if type(start) is not int or type(end) is not int or start < 1 or end < start or end > len(profile_lines) or _normalized(" ".join(profile_lines[start - 1:end])) != _normalized(str(evidence.get("text", ""))):
                    valid = False
            elif valid:
                has_dialog = True
                fact = dialog_facts.get(str(evidence.get("angabeId", "")))
                if fact is None or fact.get("wahrheitsstatus") != "bestaetigt" or _normalized(str(fact.get("wert", ""))) != _normalized(str(evidence.get("text", ""))):
                    valid = False
            if valid:
                evidence_by_id[identifier] = evidence
            else:
                _append_check(errors, "Ungültige Evidenz: %s" % identifier, ctx, "error")
            evidence_coverage["profileEvidence"].append({"id": identifier, "quelle": source, "angabeId": evidence.get("angabeId") if isinstance(evidence, dict) else None, "zeileVon": evidence.get("zeileVon") if isinstance(evidence, dict) else None, "zeileBis": evidence.get("zeileBis") if isinstance(evidence, dict) else None, "belegart": evidence.get("belegart") if isinstance(evidence, dict) else None, "valid": valid})
        if has_profile and str(evidence_index.get("profilSha256", "")).upper() != sha256_file(profile):
            _append_check(errors, "Evidenzindex.profilSha256 stimmt nicht mit der Profildatei überein.", ctx, "error")
        if has_dialog and str(evidence_index.get("auftragSha256", "")).upper() != sha256_file(order_path):
            _append_check(errors, "Evidenzindex.auftragSha256 stimmt nicht mit dem Bewerbungsauftrag überein.", ctx, "error")
        for requirement in requirements:
            for identifier in requirement.get("stellenFundstellen", []):
                if str(identifier) not in anchor_by_id:
                    _append_check(errors, "Anforderung %s verweist auf unbekannte Stellen-Fundstelle %s." % (requirement.get("id"), identifier), ctx, "error")
            for identifier in requirement.get("belegRefIds", []):
                if str(identifier) not in evidence_by_id:
                    _append_check(errors, "Anforderung %s verweist auf unbekannte Evidenz %s." % (requirement.get("id"), identifier), ctx, "error")
        evidence_coverage["status"] = "fehler" if any("Evidenz" in item or "Fundstelle" in item or "stellenanzeigeAbdeckung" in item for item in errors) else "ok"

    strategy = matrix.get("recruiterStrategie") or {}
    if recruiter_coverage["applicable"]:
        required_fields = ("kernbotschaft", "profilSubstanz", "profilSubstanzBegruendung", "prioritaetsAnforderungen", "profilHighlights", "transferbruecken", "auslassungen")
        if any(field not in strategy for field in required_fields):
            _append_check(errors, "recruiterStrategie ist unvollständig.", ctx, "error")
        else:
            recruiter_coverage.update(kernbotschaft=strategy.get("kernbotschaft"), profilSubstanz=strategy.get("profilSubstanz"), configuredPriorityRequirementIds=strategy.get("prioritaetsAnforderungen", []))
            for category, report_key in (("profilHighlights", "highlights"), ("transferbruecken", "transferBridges"), ("auslassungen", "omissions")):
                for item in strategy.get(category, []):
                    valid = isinstance(item, dict)
                    anchors = [str(value) for value in item.get("sichtbareAnker", [])] if valid else []
                    target_kind = str(item.get("zielDokument", "lebenslauf")) if valid else ""
                    target_text = texts.get(target_kind, combined)
                    missing_anchors = [anchor for anchor in anchors if _normalized(anchor) not in _normalized(target_text)]
                    if category != "auslassungen" and (not valid or missing_anchors):
                        _append_check(errors, "Recruiter-Strategieeintrag ist nicht sichtbar oder ungültig: %s" % item.get("id", item.get("thema", "?")), ctx, "error")
                    recruiter_coverage[report_key].append({**(item if isinstance(item, dict) else {}), "missingAnchors": missing_anchors, "valid": valid and not missing_anchors})
            recruiter_coverage["status"] = "fehler" if any("Recruiter-Strategie" in item or "recruiterStrategie" in item for item in errors) else "ok"

    if schema >= 5:
        external = [item for item in matrix.get("externeQuellen", []) if isinstance(item, dict)]
        source_coverage["sources"] = external
        source_coverage["status"] = "ok"
        if expected["anschreiben"]:
            letter_strategy = matrix.get("anschreibenStrategie") or {}
            arguments = [item for item in letter_strategy.get("argumente", []) if isinstance(item, dict)]
            if letter_strategy.get("status") != "final" or not (2 <= len(arguments) <= 4 or arguments and letter_strategy.get("abweichungBegruendung")):
                _append_check(errors, "anschreibenStrategie benötigt finalen Status und zwei bis vier belegte Argumente.", ctx, "error")
            for argument in arguments:
                missing = [str(anchor) for anchor in argument.get("sichtbareAnker", []) if _normalized(str(anchor)) not in _normalized(texts["anschreiben"])]
                valid = bool(argument.get("anforderungIds") and argument.get("belegRefIds") and argument.get("stellenFundstellen") and argument.get("arbeitgeberbezug") and argument.get("nutzenargument") and not missing)
                if not valid:
                    _append_check(errors, "Anschreibenargument ist nicht vollständig belegt oder sichtbar: %s" % argument.get("id", "?"), ctx, "error")
                letter_coverage["argumente"].append({**argument, "fehlendeAnker": missing, "valid": valid})
            letter_coverage["status"] = "fehler" if any("Anschreiben" in item or "anschreibenStrategie" in item for item in errors) else "ok"
        used = set()
        for requirement in requirements:
            used.update(str(value) for value in requirement.get("belegRefIds", []))
        for item in strategy.get("profilHighlights", []):
            used.update(str(value) for value in item.get("belegRefIds", []))
        for item in (matrix.get("anschreibenStrategie") or {}).get("argumente", []):
            used.update(str(value) for value in item.get("belegRefIds", []))
        omitted = set(str(value) for item in strategy.get("auslassungen", []) for value in item.get("belegRefIds", []))
        unclassified = sorted(set(evidence_by_id) - used - omitted)
        conflicts = sorted(used & omitted)
        disposition.update(status="ok" if not unclassified and not conflicts else "fehler", used=sorted(used), omitted=sorted(omitted), unclassified=unclassified, conflicts=conflicts)
        if unclassified or conflicts:
            _append_check(errors, "Evidenzdisposition ist unvollständig oder widersprüchlich.", ctx, "error")
    if expected["anschreiben"]:
        findings = []
        for pattern in (r"(?i)\bnicht belegt\b", r"(?i)\bkeine Erfahrung\b", r"(?i)\bich erfülle .* nicht\b"):
            if re.search(pattern, texts["anschreiben"]):
                findings.append(re.search(pattern, texts["anschreiben"]).group(0))
        language_quality.update(status="warnung" if findings else "ok", findings=findings, metrics={"zeichen": len(texts["anschreiben"]), "woerter": len(texts["anschreiben"].split())})
        for finding in findings:
            _append_check(warnings, "Anschreiben enthält potenziell defensive Metaformulierung: %s" % finding, ctx, "warning")

    periods = sorted(set(re.findall(r"(?<!\d)(?:0[1-9]|1[0-2])/\d{4}\s*[-–]\s*(?:(?:0[1-9]|1[0-2])/\d{4}|heute|aktuell)|\b(?:19|20)\d{2}\s*[-–]\s*(?:(?:19|20)\d{2}|heute|aktuell)", read_text(profile), re.I)))
    missing_periods = [period for period in periods if expected["lebenslauf"] and _normalized(period) not in _normalized(texts["lebenslauf"])]
    for period in missing_periods:
        _append_check(errors, "Formaler Profilzeitraum fehlt im Lebenslauf: %s" % period, ctx, "error")
    fit = {"status": "ok" if not errors else "fehler", "documentCount": sum(1 for value in expected.values() if value), "missingFormalPeriods": missing_periods}
    passfoto = {"status": "nicht_erforderlich", "sourceSha256": None, "embeddedSha256": None}
    if expected["lebenslauf"] and scope["lebenslauf"] == "individuell":
        photo = data_root / "Passfoto.png"
        passfoto["status"] = "eingebettet" if photo.is_file() else "nicht_vorhanden"
        if photo.is_file():
            passfoto["sourceSha256"] = sha256_file(photo)
            cv_files = _selected_files(document_folder, "Lebenslauf - *.html")
            if cv_files:
                source = re.search(r"(?is)data:image/png;base64,([^'\"]+)", read_text(cv_files[0]))
                if source:
                    try:
                        passfoto["embeddedSha256"] = sha256_bytes(base64.b64decode(source.group(1), validate=True))
                    except ValueError:
                        pass
                if passfoto["embeddedSha256"] != passfoto["sourceSha256"]:
                    passfoto["status"] = "fehler"
                    _append_check(errors, "Passfoto ist nicht bytegleich eingebettet.", ctx, "error")
    report = {
        "schemaVersion": 6, "checkedAtUtc": utc_now(), "applicationFolder": str(folder),
        "status": "fehler" if errors else "warnung" if warnings else "ok", "errors": errors, "warnings": warnings, "oks": oks,
        "checkedFormalPeriods": periods, "requiredFormalPeriods": periods, "compactedSchoolPeriods": [],
        "schoolMode": (order.get("darstellungsoptionen") or {}).get("schulbildungsmodus"),
        "profileLinksMode": (order.get("darstellungsoptionen") or {}).get("profillinksModus"),
        "documentMode": order.get("dokumentmodus"), "documentScope": scope, "passfoto": passfoto, "fitAssessment": fit,
        "recruiterCoverage": recruiter_coverage, "evidenceCoverage": evidence_coverage,
        "anschreibenCoverage": letter_coverage, "externalSourceCoverage": source_coverage,
        "evidenzDisposition": disposition, "sprachqualitaet": language_quality,
    }
    if report_path is not None:
        write_atomic_json(report_path, report)
    ctx.out("Zusammenfassung: OK=%d, Warnungen=%d, Fehler=%d" % (len(oks), len(warnings), len(errors)))
    return 1 if errors or (warnings and args.get("warnungen_als_fehler")) else 0


def _safe_absolute_path(path: Path, *, must_exist: bool = False, kind: Optional[str] = None) -> Path:
    """Validate an absolute, possibly external CLI path without following links."""

    absolute = Path(os.path.abspath(str(path)))
    anchor = Path(absolute.anchor or os.sep)
    return safe_path(absolute, anchor, must_exist=must_exist, kind=kind)


def handle_freigabe(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    paths = infer_work_context(Path(args["arbeitsordner"]), universal=None)
    work = paths.work
    if not args.get("bestaetigt"):
        raise ContractError("Die Freigabe-ID darf erst nach ausdrücklicher Chat-Bestätigung mit --bestaetigt gespeichert werden.")
    approval_id = str(args["freigabe_id"])
    if not re.fullmatch(r"FR-[A-Z0-9]{12}", approval_id):
        raise ContractError("Freigabe-ID besitzt nicht das erwartete Format FR-XXXXXXXXXXXX.")
    regular_report = work / "Finalisierungsbericht.json"
    universal_report = work / "Universal-Finalisierungsbericht.json"
    report_path = regular_report if regular_report.is_file() else universal_report
    report_path = safe_path(report_path, work, must_exist=True, kind="file")
    report = read_json(report_path)
    if not isinstance(report, dict) or report.get("status") != "bereit_zur_sichtpruefung":
        raise ContractError("Der Finalisierungsbericht ist nicht zur Sichtprüfung freigegeben.")
    request = report.get("approvalRequest")
    if not isinstance(request, dict) or request.get("approvalId") != approval_id:
        raise ContractError("Freigabe-ID stimmt nicht mit der vorbereiteten Anforderung überein.")
    records = approval_records(report)
    if not records:
        raise ContractError("Finalisierungsbericht enthält keinen freizugebenden Artefaktsatz.")
    assert_artifacts_current(records, work)
    set_hash = artifact_set_hash(records, work)
    if set_hash != str(request.get("artifactSetSha256", "")):
        raise ContractError("Artefaktsatz hat sich seit der Vorbereitung verändert.")
    relative_records: List[Dict[str, Any]] = []
    for record in records:
        raw = str(record.get("path", ""))
        candidate = Path(raw)
        if not candidate.is_absolute():
            candidate = work / candidate
        candidate = safe_path(candidate, work, must_exist=True, kind="file")
        relative: Dict[str, Any] = {
            "path": candidate.relative_to(work).as_posix(),
            "bytes": record.get("bytes"),
            "sha256": str(record.get("sha256", "")).upper(),
        }
        if record.get("name") is not None:
            relative["name"] = record.get("name")
        relative_records.append(relative)
    approval_path = safe_path(work / "Sichtfreigabe.json", work)
    approval = {
        "schemaVersion": 1,
        "kind": "sichtfreigabe",
        "approvalId": approval_id,
        "confirmedAtUtc": utc_now(),
        "humanConfirmation": True,
        "preparedReport": {"path": report_path.relative_to(work).as_posix(), "sha256": sha256_file(report_path)},
        "artifactSetSha256": set_hash,
        "artifacts": relative_records,
        "reviewKind": str(report.get("personalReview", "")),
        "note": _normalize_note(str(args.get("notiz", ""))),
    }
    with file_lock(approval_path):
        write_atomic_json(approval_path, approval)
    if report_path.name == "Finalisierungsbericht.json":
        try:
            write_checkpoint(work, "sichtpruefung_bestaetigt")
        except (WorkflowError, OSError) as exc:
            ctx.warning("Workflow-Checkpoint konnte nach der Sichtfreigabe nicht aktualisiert werden: %s" % exc)
    ctx.ok("Sichtfreigabe gespeichert: %s" % approval_path)
    ctx.out("Freigabe-ID: %s" % approval_id)
    return 0


def _metadata(value: Any, name: str) -> Optional[str]:
    if value is None or not str(value).strip():
        return None
    normalized = re.sub(r"\s+", " ", str(value).strip())
    if len(normalized) > 200:
        raise ContractError("%s darf höchstens 200 Zeichen enthalten." % name)
    return normalized


def _utc_datetime(value: Optional[datetime]) -> Optional[str]:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.astimezone()
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def handle_tokenbericht(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    paths = infer_work_context(Path(args["arbeitsordner"]), universal=None)
    report_path = safe_path(paths.work / "Tokenverbrauch.json", paths.work)
    provider = _metadata(args.get("anbieter"), "Anbieter")
    model = _metadata(args.get("modell"), "Modell")
    session = _metadata(args.get("vorgangs_id"), "VorgangsId")
    measurement_source = _metadata(args.get("messquelle", "runtime"), "Messquelle")
    if measurement_source is None:
        raise ContractError("Messquelle darf nicht leer sein.")
    names = (
        ("inputTokens", "eingabe_tokens"), ("outputTokens", "ausgabe_tokens"),
        ("cachedInputTokens", "cache_lese_tokens"), ("cacheWriteTokens", "cache_schreib_tokens"),
        ("reasoningTokens", "reasoning_tokens"), ("totalTokens", "gesamt_tokens"),
    )
    tokens = {target: args.get(source) for target, source in names}
    available = bool(args.get("nutzungsdaten_verfuegbar"))
    supplied = [value for value in tokens.values() if value is not None]
    if any(type(value) is not int or value < 0 for value in supplied):
        raise ContractError("Tokenwerte müssen nichtnegative ganze Zahlen sein.")
    if available and (provider is None or model is None):
        raise ContractError("Bei verfügbaren Nutzungsdaten müssen Anbieter und Modell angegeben werden.")
    if available and not supplied:
        raise ContractError("Bei verfügbaren Nutzungsdaten muss mindestens ein maschinenlesbarer Tokenwert angegeben werden.")
    if not available and supplied:
        raise ContractError("Tokenwerte dürfen nur mit --nutzungsdaten-verfuegbar gespeichert werden.")
    started = args.get("beginn")
    finished = args.get("ende")
    if started is not None and finished is not None:
        left = started if started.tzinfo is not None else started.astimezone()
        right = finished if finished.tzinfo is not None else finished.astimezone()
        if right.astimezone(timezone.utc) < left.astimezone(timezone.utc):
            raise ContractError("Ende darf nicht vor Beginn liegen.")
    existing: Dict[str, Any] = {}
    sections: List[Dict[str, Any]] = []
    if report_path.is_file():
        loaded = read_json(report_path)
        if not isinstance(loaded, dict) or loaded.get("schemaVersion") != 1:
            raise ContractError("Nicht unterstützte Schema-Version in Tokenverbrauch.json.")
        existing = loaded
        raw_sections = loaded.get("sections") or []
        if not isinstance(raw_sections, list) or any(not isinstance(item, dict) for item in raw_sections):
            raise ContractError("Tokenverbrauch.json enthält keine gültige Abschnittsliste.")
        sections = list(raw_sections)
    area = str(args["messbereich"])
    previous = next((item for item in sections if item.get("name") == area), None)
    if not available and previous is not None and previous.get("availability") == "available":
        section = previous
    else:
        section = {
            "name": area,
            "availability": "available" if available else "unavailable",
            "reason": None if available else "Von dieser Agentenumgebung nicht bereitgestellt.",
            "measurementScope": str(args.get("messumfang", "abschnitt")),
            "startedAt": _utc_datetime(started),
            "finishedAt": _utc_datetime(finished),
            **{name: value if available else None for name, value in tokens.items()},
        }
    sections = [item for item in sections if item.get("name") != area] + [section]
    any_available = any(item.get("availability") == "available" for item in sections)
    report = {
        "schemaVersion": 1,
        "provider": provider if provider is not None else existing.get("provider"),
        "model": model if model is not None else existing.get("model"),
        "sessionId": session if session is not None else existing.get("sessionId"),
        "measurementSource": measurement_source,
        "availability": "available" if any_available else "unavailable",
        "reason": None if any_available else "Von dieser Agentenumgebung nicht bereitgestellt.",
        "sections": sections,
    }
    with file_lock(report_path):
        write_atomic_json(report_path, report)
    if section.get("availability") != "available":
        ctx.out("Tokenverbrauch: Von dieser Agentenumgebung nicht bereitgestellt.")
    headings = {"lebenslauf": "Lebenslauf", "gesamte_bewerbung": "Gesamte Bewerbung", "technische_vorbereitung": "Technische Vorbereitung"}
    display = lambda value: "nicht verfügbar" if value is None else str(value)
    ctx.out("Tokenverbrauch – %s" % headings[area])
    ctx.out("Anbieter: %s" % display(report.get("provider")))
    ctx.out("Modell: %s" % display(report.get("model")))
    ctx.out("Eingabe: %s" % display(section.get("inputTokens")))
    ctx.out("Ausgabe: %s" % display(section.get("outputTokens")))
    ctx.out("Gesamt: %s" % display(section.get("totalTokens")))
    ctx.out("Messquelle: %s" % report["measurementSource"])
    if section.get("measurementScope") == "gesamte_agentensitzung":
        detail = "eine isolierte Messung nur für den Lebenslauf" if area == "lebenslauf" else "eine isolierte Messung für den gewählten Abschnitt"
        ctx.out("Messbereich: gesamte Agentensitzung; %s ist nicht verfügbar." % detail)
    ctx.out("Bericht: %s" % report_path)
    return 0


def _runtime_family(runtime: Mapping[str, Any]) -> Tuple[str, str, str, str]:
    os_name = str(runtime.get("os", ""))
    architecture = str(runtime.get("architecture", ""))
    core = runtime.get("coreRuntime")
    if isinstance(core, dict):
        language = str(core.get("language") or core.get("kind") or "")
        version = str(core.get("version") or "")
    elif runtime.get("python") is not None or runtime.get("pythonVersion") is not None:
        language, version = "python", str(runtime.get("python") or runtime.get("pythonVersion"))
    else:
        language, version = "powershell", str(runtime.get("powershell", ""))
    if not os_name or not architecture or not language or not version:
        raise ContractError("Testbericht enthält keine vollständige Laufzeitfamilie.")
    return os_name, architecture, language, version


def _baseline_runtime(runtime: Mapping[str, Any]) -> Dict[str, Any]:
    os_name, architecture, language, version = _runtime_family(runtime)
    return {"os": os_name, "architecture": architecture, "coreRuntime": {"language": language, "version": version}}


def _strict_nonnegative_int(value: Any, field: str) -> int:
    if type(value) is not int or value < 0:
        raise ContractError("Testbericht enthält keinen gültigen Wert für %s." % field)
    return value


def handle_test_baseline(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    paths = list(args["bericht_path"])
    if len(paths) != 3:
        raise ContractError("Genau drei durch Komma getrennte Testberichtspfade sind erforderlich.")
    reports: List[Dict[str, Any]] = []
    for path in paths:
        path = _safe_absolute_path(Path(path), must_exist=True, kind="file")
        value = read_json(path)
        if not isinstance(value, dict):
            raise ContractError("Testbericht muss ein JSON-Objekt sein: %s" % path)
        if value.get("schemaVersion") != 1 or value.get("status") != "bestanden" or value.get("testNamePattern") not in (None, "") or not isinstance(value.get("timing"), dict):
            raise ContractError("Nur erfolgreiche, ungefilterte Schema-1-Berichte mit Laufzeitdaten dürfen eine Baseline bilden.")
        _strict_nonnegative_int(value.get("durationMs"), "durationMs")
        _strict_nonnegative_int(value["timing"].get("testDurationMs"), "timing.testDurationMs")
        _strict_nonnegative_int(value["timing"].get("p95TestDurationMs"), "timing.p95TestDurationMs")
        _runtime_family(value.get("runtime") if isinstance(value.get("runtime"), dict) else {})
        reports.append(value)
    suite = str(reports[0].get("suite", ""))
    family = _runtime_family(reports[0]["runtime"])
    if not suite or any(str(item.get("suite", "")) != suite or _runtime_family(item["runtime"]) != family for item in reports):
        raise ContractError("Die drei Berichte müssen dieselbe Suite und Laufzeitfamilie besitzen.")
    median = lambda values: int(statistics.median_low(sorted(values)))
    entry = {
        "suite": suite,
        "runtime": _baseline_runtime(reports[0]["runtime"]),
        "sampleCount": 3,
        "recordedAtUtc": utc_now(),
        "durationMsMedian": median([item["durationMs"] for item in reports]),
        "testDurationMsMedian": median([item["timing"]["testDurationMs"] for item in reports]),
        "p95TestDurationMsMedian": median([item["timing"]["p95TestDurationMs"] for item in reports]),
    }
    target = Path(args.get("baseline_path") or ctx.project_root / "Tests/Testlaufzeit-Baselines.json")
    target = _safe_absolute_path(target)
    entries: List[Dict[str, Any]] = []
    if target.is_file():
        current = read_json(target)
        if isinstance(current, dict) and current.get("schemaVersion") == 1 and isinstance(current.get("baselines"), list):
            for current_entry in current["baselines"]:
                if not isinstance(current_entry, dict):
                    continue
                current_runtime = current_entry.get("runtime")
                try:
                    same = current_entry.get("suite") == suite and isinstance(current_runtime, dict) and _runtime_family(current_runtime) == family
                except ContractError:
                    same = False
                if not same:
                    entries.append(current_entry)
    result = {"schemaVersion": 1, "kind": "testlaufzeit_baselines", "warningThresholdPercent": 25, "warningMinimumMs": 1000, "baselines": entries + [entry]}
    with file_lock(target):
        write_atomic_json(target, result)
    ctx.out("Laufzeitbaseline aktualisiert: %s" % target)
    return 0


def _iter_tests(value: unittest.TestSuite) -> Iterable[unittest.TestCase]:
    for item in value:
        if isinstance(item, unittest.TestSuite):
            yield from _iter_tests(item)
        else:
            yield item


class _TimingResult(unittest.TextTestResult):
    def __init__(self, *values: Any, **kwargs: Any) -> None:
        super().__init__(*values, **kwargs)
        self._started: Dict[str, float] = {}
        self._outcomes: Dict[str, Tuple[str, Optional[str]]] = {}
        self.records: List[Dict[str, Any]] = []

    def startTest(self, test: unittest.TestCase) -> None:
        self._started[test.id()] = time.monotonic()
        super().startTest(test)

    def addSuccess(self, test: unittest.TestCase) -> None:
        self._outcomes[test.id()] = ("passed", None)
        super().addSuccess(test)

    def addFailure(self, test: unittest.TestCase, err: Any) -> None:
        self._outcomes[test.id()] = ("failed", self._exc_info_to_string(err, test))
        super().addFailure(test, err)

    def addError(self, test: unittest.TestCase, err: Any) -> None:
        self._outcomes[test.id()] = ("failed", self._exc_info_to_string(err, test))
        super().addError(test, err)

    def addSkip(self, test: unittest.TestCase, reason: str) -> None:
        self._outcomes[test.id()] = ("skipped", reason)
        super().addSkip(test, reason)

    def addExpectedFailure(self, test: unittest.TestCase, err: Any) -> None:
        self._outcomes[test.id()] = ("expected_failure", self._exc_info_to_string(err, test))
        super().addExpectedFailure(test, err)

    def addUnexpectedSuccess(self, test: unittest.TestCase) -> None:
        self._outcomes[test.id()] = ("failed", "unerwarteter Erfolg")
        super().addUnexpectedSuccess(test)

    def stopTest(self, test: unittest.TestCase) -> None:
        ended = time.monotonic()
        started = self._started.pop(test.id(), ended)
        status, detail = self._outcomes.pop(test.id(), ("failed", "Test meldete kein Ergebnis."))
        record: Dict[str, Any] = {
            "name": test.id(), "category": "browser" if "browser" in test.id().lower() else "python",
            "status": status, "durationMs": max(0, int(round((ended - started) * 1000))),
        }
        if detail:
            record["error"] = detail
        self.records.append(record)
        super().stopTest(test)


def _timing_summary(records: Sequence[Mapping[str, Any]], duration_ms: int) -> Dict[str, Any]:
    durations = sorted(int(item["durationMs"]) for item in records)
    percentile = lambda value: durations[max(0, min(len(durations) - 1, int(math.ceil(len(durations) * value)) - 1))] if durations else 0
    categories: Dict[str, Dict[str, int]] = {}
    for item in records:
        category = str(item.get("category", "python"))
        bucket = categories.setdefault(category, {"testCount": 0, "durationMs": 0})
        bucket["testCount"] += 1
        bucket["durationMs"] += int(item["durationMs"])
    test_duration = sum(durations)
    return {
        "testDurationMs": test_duration,
        "setupAndCleanupDurationMs": max(0, duration_ms - test_duration),
        "medianTestDurationMs": percentile(0.5),
        "p95TestDurationMs": percentile(0.95),
        "categories": dict(sorted(categories.items())),
        "slowestTests": sorted(records, key=lambda item: (-int(item["durationMs"]), str(item["name"])))[:10],
    }


def _test_runtime() -> Dict[str, Any]:
    fingerprint = runtime_fingerprint()
    return {
        "os": str(fingerprint.get("os") or platform.platform()),
        "architecture": str(fingerprint.get("architecture") or platform.machine()),
        "python": platform.python_version(),
        "coreRuntime": {"language": "python", "version": platform.python_version()},
    }


def _write_test_report(path: Optional[Path], report: Mapping[str, Any], ctx: CommandContext) -> None:
    if path is None:
        return
    target = _safe_absolute_path(path)
    write_atomic_json(target, report)
    ctx.out("Testbericht: %s" % target)


def handle_tests(ctx: CommandContext, args: Mapping[str, Any]) -> int:
    suite_name = str(args.get("suite", "vollstaendig"))
    browser_requested = bool(args.get("mit_browser")) or suite_name == "browser"
    if args.get("mit_browser") and suite_name == "schnell":
        raise CliUsageError("--mit-browser ist mit der schnellen Suite widersprüchlich; verwende --suite browser.")
    if suite_name.startswith("prompt-") and args.get("mit_browser"):
        raise CliUsageError("--mit-browser ist mit einer Prompt-Suite nicht zulässig.")
    report_path = _safe_absolute_path(Path(args["bericht_path"])) if args.get("bericht_path") else None
    pattern_text = args.get("test_name_pattern")
    started_wall = datetime.now(timezone.utc)
    started = time.monotonic()
    if suite_name.startswith("prompt-"):
        from .prompt_regression import run_prompt_regression

        matrix = "pr" if suite_name == "prompt-pr" else "vollstaendig"
        return run_prompt_regression(ctx, matrix, report_path, str(pattern_text) if pattern_text else None)
    compiled = None
    if pattern_text:
        try:
            compiled = re.compile(str(pattern_text))
        except re.error as exc:
            raise CliUsageError("--test-name-pattern ist kein gültiger regulärer Ausdruck: %s" % exc) from exc
    old_browser_value = os.environ.get("APPLY_FOUNDRY_BROWSER_TEST")
    if browser_requested:
        os.environ["APPLY_FOUNDRY_BROWSER_TEST"] = "1"
    try:
        # skipUnless decorators are evaluated while the module is imported, so
        # the opt-in must be visible before discovery rather than only before run.
        start_dir = safe_path(ctx.project_root / "Tests/Python", ctx.project_root, must_exist=True, kind="dir")
        discovered = unittest.defaultTestLoader.discover(str(start_dir), pattern="test_*.py")
        all_tests = list(_iter_tests(discovered))
        fast_markers = (
            "CliAndPathTests.test_dispatcher_registers_every_browser_free_command",
            "CliAndPathTests.test_cli_uses_snake_case",
            "CliAndPathTests.test_atomic_json",
            "ScopeContractTests.test_all_scope_choices",
            "RuntimeDetectionTests.test_diagnose_schema_three",
            "BrowserPrimitiveTests.test_runtime_fingerprint",
            "SetupLinuxTests.test_manifest_is_versioned",
            "SetupLinuxTests.test_idempotent_run",
            "SetupLinuxTests.test_schema_two_exposes",
            "SetupLinuxTests.test_snap_executable",
        )
        tests = [
            item for item in all_tests
            if (suite_name != "schnell" or any(marker in item.id() for marker in fast_markers))
            and (browser_requested or "ChromiumWorkflowSmoke" not in item.id())
            and (compiled is None or compiled.search(item.id()))
        ]
        selected = unittest.TestSuite(tests)
        output = __import__("io").StringIO()
        runner = unittest.TextTestRunner(stream=output, verbosity=2, resultclass=_TimingResult)
        result: _TimingResult = runner.run(selected)  # type: ignore[assignment]
    finally:
        if old_browser_value is None:
            os.environ.pop("APPLY_FOUNDRY_BROWSER_TEST", None)
        else:
            os.environ["APPLY_FOUNDRY_BROWSER_TEST"] = old_browser_value
    rendered = output.getvalue().rstrip()
    if rendered:
        ctx.out(rendered)
    records = result.records
    failures = [str(item.get("error")) for item in records if item.get("status") == "failed"]
    if browser_requested:
        skipped_browser = [item for item in records if item.get("status") == "skipped" and "ChromiumWorkflowSmoke" in str(item.get("name"))]
        for item in skipped_browser:
            failures.append("Echter Chromium-Smoke wurde übersprungen: %s (%s)" % (item.get("name"), item.get("error", "kein Grund")))
    if compiled is not None and not tests:
        failures.append("Kein Test entspricht dem Muster: %s" % pattern_text)
    ended_wall = datetime.now(timezone.utc)
    duration = max(0, int(round((time.monotonic() - started) * 1000)))
    failed_count = len([item for item in records if item.get("status") == "failed"]) + len(skipped_browser if browser_requested else []) + (1 if compiled is not None and not tests else 0)
    passed_count = len([item for item in records if item.get("status") == "passed"])
    skipped_count = len([item for item in records if item.get("status") == "skipped"])
    report = {
        "schemaVersion": 1, "suite": suite_name, "testNamePattern": pattern_text,
        "browserRequested": browser_requested, "startedAtUtc": started_wall.isoformat().replace("+00:00", "Z"),
        "endedAtUtc": ended_wall.isoformat().replace("+00:00", "Z"), "durationMs": duration,
        "runtime": _test_runtime(), "selectedTestCount": len(tests), "passedCount": passed_count,
        "failedCount": failed_count, "skippedCount": skipped_count,
        "status": "bestanden" if failed_count == 0 else "fehlgeschlagen",
        "failures": failures, "tests": records, "timing": _timing_summary(records, duration), "runtimeWarnings": [],
    }
    _write_test_report(report_path, report, ctx)
    ctx.out("Testergebnis: %d bestanden, %d fehlgeschlagen." % (passed_count, failed_count))
    return 0 if failed_count == 0 else 1


CORE_HANDLERS.update({
    "passfoto": handle_passfoto,
    "kontext": handle_kontext,
    "inhalt": handle_inhalt,
    "pruefen": handle_pruefen,
    "freigabe": handle_freigabe,
    "tokenbericht": handle_tokenbericht,
    "test-baseline": handle_test_baseline,
    "tests": handle_tests,
})


__all__ = ["CORE_HANDLERS", "write_checkpoint"]
