"""Hash-bound, atomic stage cache for the Linux finalization workflow.

The on-disk contract intentionally mirrors ``Common/FinalizationCache.psm1``:
``Pruefstand.json`` remains schema 2 and can therefore be inspected by either
platform implementation.  Runtime-specific fingerprints make technical
artifacts stale after a platform or core-runtime switch.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence

from .io import canonical_json, file_lock, read_json, sha256_bytes, sha256_file, utc_now, write_atomic_json


STAGE_ORDER = ("dialog", "stammdaten", "statisch", "inhalt", "layout", "pdf", "ats")


def _relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return "<extern>/" + path.name


def file_record(path: Path, root: Path) -> Optional[Dict[str, Any]]:
    if not path.is_file() or path.is_symlink():
        return None
    stat = path.stat()
    return {"path": _relative(path, root), "bytes": stat.st_size, "sha256": sha256_file(path)}


def _records(paths: Iterable[Path], root: Path) -> List[Dict[str, Any]]:
    values: List[Dict[str, Any]] = []
    seen = set()
    for path in sorted((Path(value) for value in paths), key=lambda item: str(item)):
        key = str(path.resolve()) if path.exists() else str(path.absolute())
        if key in seen:
            continue
        seen.add(key)
        record = file_record(path, root)
        if record is not None:
            values.append(record)
    return values


def stage_fingerprint(
    stage: str,
    root: Path,
    *,
    implementation_files: Sequence[Path] = (),
    input_files: Sequence[Path] = (),
    parameters: Optional[Mapping[str, Any]] = None,
    runtime: Any = None,
    dependency_keys: Sequence[str] = (),
) -> Dict[str, Any]:
    if stage not in STAGE_ORDER:
        raise ValueError("Unbekannte Finalisierungsstufe: %s" % stage)
    normalized_parameters = {
        str(key): str(value).lower() if isinstance(value, bool) else str(value)
        for key, value in sorted((parameters or {}).items(), key=lambda item: str(item[0]))
    }
    fingerprint = {
        "contractVersion": 1,
        "stage": stage,
        "implementation": _records(implementation_files, root),
        "inputs": _records(input_files, root),
        "parameters": normalized_parameters,
        "runtime": runtime,
        "dependencies": list(dependency_keys),
    }
    return {"fingerprint": fingerprint, "cacheKey": sha256_bytes(canonical_json(fingerprint))}


def read_state(path: Path) -> Optional[Dict[str, Any]]:
    if not path.is_file() or path.is_symlink():
        return None
    try:
        value = read_json(path)
    except Exception:
        return None
    if not isinstance(value, dict) or value.get("schemaVersion") != 2 or value.get("kind") != "finalisierungs_pruefstand" or not isinstance(value.get("stages"), list):
        return None
    return value


def cache_decision(state: Optional[Mapping[str, Any]], stage: str, fingerprint: Mapping[str, Any], root: Path, *, force: bool = False) -> Dict[str, Any]:
    if force:
        return {"reusable": False, "reason": "forced", "entry": None}
    if not isinstance(state, Mapping):
        return {"reusable": False, "reason": "missing", "entry": None}
    entry = next((value for value in state.get("stages", []) if isinstance(value, dict) and value.get("id") == stage), None)
    if entry is None:
        return {"reusable": False, "reason": "missing", "entry": None}
    if entry.get("status") != "passed":
        reason = "previous_failed" if entry.get("status") == "failed" else "interrupted" if entry.get("status") == "running" else "input_changed"
        return {"reusable": False, "reason": reason, "entry": entry}
    if entry.get("cacheKey") != fingerprint.get("cacheKey"):
        old = entry.get("fingerprint") if isinstance(entry.get("fingerprint"), dict) else {}
        new = fingerprint.get("fingerprint") if isinstance(fingerprint.get("fingerprint"), dict) else {}
        if old.get("implementation") != new.get("implementation"):
            reason = "implementation_changed"
        elif old.get("runtime") != new.get("runtime"):
            reason = "runtime_changed"
        elif old.get("dependencies") != new.get("dependencies"):
            reason = "dependency_changed"
        else:
            reason = "input_changed"
        return {"reusable": False, "reason": reason, "entry": entry}
    for output in entry.get("outputs", []):
        if not isinstance(output, dict):
            return {"reusable": False, "reason": "output_missing", "entry": entry}
        relative = str(output.get("path", ""))
        if not relative or relative.startswith("<extern>/"):
            return {"reusable": False, "reason": "output_missing", "entry": entry}
        actual = file_record(root / relative, root)
        if actual is None:
            return {"reusable": False, "reason": "output_missing", "entry": entry}
        if actual.get("bytes") != output.get("bytes") or actual.get("sha256") != output.get("sha256"):
            return {"reusable": False, "reason": "output_changed", "entry": entry}
    return {"reusable": True, "reason": "hit", "entry": entry}


def save_result(
    path: Path,
    root: Path,
    stage: str,
    fingerprint: Mapping[str, Any],
    *,
    output_files: Sequence[Path] = (),
    duration_ms: int = 0,
    status: str = "passed",
    failure: Any = None,
) -> Dict[str, Any]:
    if stage not in STAGE_ORDER or status not in ("running", "passed", "failed"):
        raise ValueError("Ungültiger Finalisierungsstatus.")
    with file_lock(path):
        current = read_state(path)
        stages = current.get("stages", []) if current else []
        stage_index = STAGE_ORDER.index(stage)
        kept = [
            value for value in stages
            if isinstance(value, dict) and value.get("id") in STAGE_ORDER and STAGE_ORDER.index(value["id"]) < stage_index
        ]
        previous = next((value for value in stages if isinstance(value, dict) and value.get("id") == stage), None)
        started = previous.get("startedAtUtc") if status != "running" and isinstance(previous, dict) else None
        entry = {
            "id": stage,
            "status": status,
            "cacheKey": fingerprint.get("cacheKey"),
            "fingerprint": fingerprint.get("fingerprint"),
            "outputs": _records(output_files, root) if status == "passed" else [],
            "durationMs": max(0, int(duration_ms)),
            "startedAtUtc": started or utc_now(),
            "completedAtUtc": None if status == "running" else utc_now(),
            "failure": failure if status == "failed" else None,
        }
        value = {"schemaVersion": 2, "kind": "finalisierungs_pruefstand", "stages": kept + [entry]}
        write_atomic_json(path, value)
        return value


__all__ = ["STAGE_ORDER", "cache_decision", "file_record", "read_state", "save_result", "stage_fingerprint"]
