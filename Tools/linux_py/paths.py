"""Portable and symlink-safe workflow path contracts."""

import os
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any, Optional

from .errors import ContractError, UnsafePathError


_CONTROL = re.compile(r"[\x00-\x1f\x7f]")
_RESERVED = re.compile(r"^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", re.IGNORECASE)


def validate_portable_relative(value: str, field: str = "Relativpfad") -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ContractError("%s darf nicht leer sein oder äußere Leerzeichen enthalten." % field)
    if "\\" in value or value.startswith("/") or re.match(r"^[A-Za-z]:", value) or _CONTROL.search(value):
        raise ContractError("%s muss ein portabler relativer '/'-Pfad sein." % field)
    parts = value.split("/")
    for part in parts:
        if not part or part in (".", ".."):
            raise ContractError("%s enthält ein unzulässiges Pfadsegment." % field)
        if re.search(r"[<>:\"\\|?*]", part) or part.endswith((".", " ")):
            raise ContractError("%s enthält ein nicht portables Pfadsegment: %s" % (field, part))
        if _RESERVED.match(part.split(".")[0]):
            raise ContractError("%s enthält einen reservierten Dateinamen: %s" % (field, part))
    return value


def slug(value: str) -> str:
    replacements = {"ä": "ae", "ö": "oe", "ü": "ue", "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ß": "ss", "&": "und"}
    text = value.strip()
    for source, target in replacements.items():
        text = text.replace(source, target)
    text = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-") or "Unbekannt"
    validate_portable_relative(text, "Slug")
    return text


def parse_date(value: str) -> str:
    try:
        parsed = datetime.strptime(value, "%Y-%m-%d")
    except (TypeError, ValueError) as exc:
        raise ContractError("Auftragsdatum muss ein echtes Kalenderdatum im Format YYYY-MM-DD sein.") from exc
    return parsed.strftime("%Y-%m-%d")


def _absolute(path: Path) -> Path:
    return Path(os.path.abspath(str(path)))


def safe_path(
    candidate: Path,
    root: Path,
    *,
    allow_root: bool = False,
    must_exist: bool = False,
    kind: Optional[str] = None,
) -> Path:
    """Validate containment without ever traversing a symbolic-link alias."""

    root_abs = _absolute(root)
    candidate_abs = _absolute(candidate)
    try:
        relative = candidate_abs.relative_to(root_abs)
    except ValueError as exc:
        raise UnsafePathError("Pfad liegt außerhalb seines vorgesehenen Roots: %s" % candidate_abs) from exc
    if relative == Path(".") and not allow_root:
        raise UnsafePathError("Der Root selbst ist für diesen Pfad nicht zulässig: %s" % candidate_abs)

    current = root_abs
    chain = [root_abs] + [root_abs.joinpath(*relative.parts[: index + 1]) for index in range(len(relative.parts))]
    for index, item in enumerate(chain):
        if not item.exists() and not item.is_symlink():
            continue
        if item.is_symlink():
            raise UnsafePathError("Symbolische Links sind im Vertragspfad nicht zulässig: %s" % item)
        if index < len(chain) - 1 and not item.is_dir():
            raise UnsafePathError("Eine Datei maskiert einen benötigten Ordner: %s" % item)
        current = item
    if must_exist and not candidate_abs.exists():
        raise UnsafePathError("Erforderlicher Pfad fehlt: %s" % candidate_abs)
    if candidate_abs.exists():
        if kind == "file" and not candidate_abs.is_file():
            raise UnsafePathError("Pfad ist keine reguläre Datei: %s" % candidate_abs)
        if kind == "dir" and not candidate_abs.is_dir():
            raise UnsafePathError("Pfad ist kein Verzeichnis: %s" % candidate_abs)
    return candidate_abs


def require_private_applications_root(path: Path, *, must_exist: bool = False) -> Path:
    root = _absolute(path)
    if root.name != "Bewerbungen" or root.parent.name != "Private":
        raise UnsafePathError("BewerbungenRoot muss auf einen Private/Bewerbungen-Ordner zeigen: %s" % root)
    private = root.parent
    if private.exists() and private.is_symlink():
        raise UnsafePathError("Private darf kein symbolischer Link sein: %s" % private)
    if root.exists() and root.is_symlink():
        raise UnsafePathError("BewerbungenRoot darf kein symbolischer Link sein: %s" % root)
    if must_exist:
        return safe_path(root, private, must_exist=True, kind="dir")
    return safe_path(root, private)


@dataclass(frozen=True)
class OrderPaths:
    applications_root: Path
    target: Path
    work: Path
    candidate: Path
    target_relative: str
    work_relative: str
    candidate_relative: str


def new_order_paths(applications_root: Path, company_slug: str, role_slug: str, date: str) -> OrderPaths:
    validate_portable_relative(company_slug, "firmaSlug")
    validate_portable_relative(role_slug, "rolleSlug")
    if "/" in company_slug or "/" in role_slug:
        raise ContractError("Firma- und Rolle-Slug müssen jeweils genau ein Segment sein.")
    parse_date(date)
    root = require_private_applications_root(applications_root)
    job = "%s--%s" % (date, role_slug)
    target_rel = "%s/%s" % (company_slug, job)
    work_rel = "%s/_Arbeitsdateien/%s" % (company_slug, job)
    candidate_rel = "%s/Kandidat" % work_rel
    return OrderPaths(
        root,
        safe_path(root / PurePosixPath(target_rel), root),
        safe_path(root / PurePosixPath(work_rel), root),
        safe_path(root / PurePosixPath(candidate_rel), root),
        target_rel,
        work_rel,
        candidate_rel,
    )


def infer_work_context(work: Path, *, universal: Optional[bool] = None) -> OrderPaths:
    work_abs = _absolute(work)
    if len(work_abs.parents) < 3 or work_abs.parent.name != "_Arbeitsdateien":
        raise UnsafePathError("Arbeitsordner besitzt nicht die erwartete _Arbeitsdateien-Struktur: %s" % work_abs)
    company = work_abs.parent.parent
    applications = company.parent
    require_private_applications_root(applications, must_exist=True)
    is_universal = company.name == "_Universal-Lebenslauf"
    if universal is True and not is_universal:
        raise UnsafePathError("Arbeitsordner gehört nicht zum Universal-Lebenslauf.")
    if universal is False and is_universal:
        raise UnsafePathError("Universal-Arbeitsordner ist für diesen Befehl nicht zulässig.")
    safe_work = safe_path(work_abs, applications, must_exist=True, kind="dir")
    if is_universal:
        return OrderPaths(applications, applications / company.name / "Aktiv", safe_work, safe_work / "Kandidat", "_Universal-Lebenslauf/Aktiv", safe_work.relative_to(applications).as_posix(), (safe_work / "Kandidat").relative_to(applications).as_posix())
    order_path = safe_path(safe_work / "Bewerbungsauftrag.json", safe_work, must_exist=True, kind="file")
    from .io import read_json

    order = read_json(order_path)
    return resolve_order_paths(order, applications, safe_work)


def resolve_order_paths(order: Any, applications_root: Path, work: Optional[Path] = None) -> OrderPaths:
    if (
        not isinstance(order, dict)
        or not isinstance(order.get("schemaVersion"), int)
        or isinstance(order.get("schemaVersion"), bool)
    ):
        raise ContractError("Bewerbungsauftrag enthält keine ganzzahlige schemaVersion.")
    schema = order["schemaVersion"]
    root = require_private_applications_root(applications_root, must_exist=True)
    if schema < 1 or schema > 5:
        raise ContractError("Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 5.")
    if schema <= 4:
        raw_paths = [Path(str(order.get(name, ""))) for name in ("zielOrdner", "arbeitsOrdner", "kandidatOrdner")]
        if any(not value.is_absolute() for value in raw_paths):
            raise ContractError("Legacy-Auftrag erfordert absolute Ziel-, Arbeits- und Kandidatenpfade.")
        target = safe_path(raw_paths[0], root)
        order_work = safe_path(raw_paths[1], root)
        candidate = safe_path(raw_paths[2], root)
        if work is not None and _absolute(work) != order_work:
            raise ContractError("Übergebener Arbeitsordner stimmt nicht mit dem Legacy-Auftrag überein.")
        return OrderPaths(root, target, order_work, candidate, "", "", "")
    if order.get("pfadModus") != "relativ_zu_bewerbungen_root":
        raise ContractError("Schema-5-Auftrag verwendet keinen unterstützten pfadModus.")
    company = str(order.get("firma", ""))
    role = str(order.get("rolle", ""))
    company_slug = str(order.get("firmaSlug", ""))
    role_slug = str(order.get("rolleSlug", ""))
    if not company or not role or slug(company) != company_slug or slug(role) != role_slug:
        raise ContractError("Schema-5-Auftrag enthält inkonsistente Firma-, Rolle- oder Slugwerte.")
    expected = new_order_paths(root, company_slug, role_slug, str(order.get("datum", "")))
    values = (order.get("zielOrdner"), order.get("arbeitsOrdner"), order.get("kandidatOrdner"))
    expected_values = (expected.target_relative, expected.work_relative, expected.candidate_relative)
    for actual, wanted, field in zip(values, expected_values, ("zielOrdner", "arbeitsOrdner", "kandidatOrdner")):
        validate_portable_relative(str(actual), field)
        if actual != wanted:
            raise ContractError("Schema-5-Auftragspfad %s stimmt nicht mit Firma, Rolle und Datum überein." % field)
    if work is not None and _absolute(work) != expected.work:
        raise ContractError("Übergebener Arbeitsordner stimmt nicht mit dem Schema-5-Auftrag überein.")
    return expected
