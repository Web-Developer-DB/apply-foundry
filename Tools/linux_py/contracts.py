"""Shared JSON, document-scope, checkpoint, and approval contracts."""

import json
import re
import uuid
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence

from .errors import ContractError
from .io import artifact_record, canonical_json, read_json, sha256_bytes, sha256_file
from .paths import safe_path


DOCUMENTS = ("lebenslauf", "anschreiben", "email_nachricht")
CV_KINDS = ("individuell", "universal_unveraendert", "nicht_enthalten")


def document_scope(order: Mapping[str, Any]) -> Dict[str, Any]:
    schema = order.get("schemaVersion")
    if not isinstance(schema, int) or isinstance(schema, bool) or schema < 1 or schema > 5:
        raise ContractError("Bewerbungsauftrag verwendet keine unterstützte schemaVersion 1 bis 5.")
    result = {"lebenslauf": "individuell", "anschreiben": True, "emailNachricht": True}
    configured = order.get("dokumentumfang")
    if schema >= 4 and configured is not None:
        if not isinstance(configured, dict):
            raise ContractError("dokumentumfang muss ein JSON-Objekt sein.")
        cv = configured.get("lebenslauf")
        letter = configured.get("anschreiben")
        email = configured.get("emailNachricht")
        if cv not in CV_KINDS or type(letter) is not bool or type(email) is not bool:
            raise ContractError("Bewerbungsauftrag enthält einen ungültigen oder nicht typisierten dokumentumfang.")
        if cv == "nicht_enthalten" and not letter and not email:
            raise ContractError("Bewerbungsauftrag wählt kein Dokument aus.")
        result.update(lebenslauf=cv, anschreiben=letter, emailNachricht=email)
    elif order.get("dokumentmodus") == "anschreiben_mit_universalem_lebenslauf":
        result["lebenslauf"] = "universal_unveraendert"
    return result


def scope_from_cli(args: Mapping[str, Any]) -> Dict[str, Any]:
    selection = args.get("umfang")
    mode = args.get("dokumentmodus")
    documents = list(args.get("dokumente") or [])
    if selection is None and mode is None:
        raise ContractError("Der Bewerbungsumfang muss ausdrücklich mit --umfang A-E oder --dokumentmodus festgelegt werden.")
    mapping = {
        "A": ("vollbewerbung", "individuell", True, True, "komplette_bewerbung"),
        "B": ("anschreiben_mit_universalem_lebenslauf", "universal_unveraendert", True, True, "anschreiben_mit_universalem_lebenslauf"),
        "C": ("individuelle_auswahl", "individuell", False, False, "individueller_lebenslauf"),
        "D": ("individuelle_auswahl", "nicht_enthalten", True, False, "nur_anschreiben"),
    }
    if selection in mapping:
        resolved_mode, cv, letter, email, code = mapping[str(selection)]
        if documents:
            raise ContractError("--dokumente ist nur für Umfang E zulässig.")
    elif selection == "E" or (selection is None and mode == "individuelle_auswahl"):
        if not documents:
            raise ContractError("Umfang E erfordert --dokumente.")
        resolved_mode, code = "individuelle_auswahl", "eigene_zusammenstellung"
        letter, email = "anschreiben" in documents, "email_nachricht" in documents
        cv = "nicht_enthalten"
        if "lebenslauf" in documents:
            cv = "universal_unveraendert" if args.get("universal_lebenslauf_path") else "individuell"
        selection = "E"
    elif selection is None and mode in ("vollbewerbung", "anschreiben_mit_universalem_lebenslauf"):
        selection = "A" if mode == "vollbewerbung" else "B"
        resolved_mode, cv, letter, email, code = mapping[selection]
    else:
        raise ContractError("Dokumentmodus und Umfangsauswahl sind nicht konsistent.")
    if mode is not None and mode != resolved_mode:
        raise ContractError("Dokumentmodus und Umfangsauswahl widersprechen sich.")
    if cv == "nicht_enthalten" and not letter and not email:
        raise ContractError("Der Dokumentumfang muss mindestens ein Dokument enthalten.")
    email_only_confirmed = bool(args.get("email_allein_bestaetigt"))
    if cv == "nicht_enthalten" and not letter and email and not email_only_confirmed:
        raise ContractError("Ein reiner E-Mail-Auftrag erfordert --email-allein-bestaetigt.")
    return {
        "auswahl": selection,
        "kennung": code,
        "lebenslauf": cv,
        "anschreiben": letter,
        "emailNachricht": email,
        "dokumentmodus": resolved_mode,
        "emailAlleinBestaetigt": email_only_confirmed,
    }


def new_matrix_draft(include_letter: bool = True) -> Dict[str, Any]:
    return {
        "schemaVersion": 5,
        "requirements": [{
            "id": "muss-1",
            "anforderung": "durch den Agenten aus der Stellenbeschreibung zu extrahieren",
            "typ": "muss",
            "kategorie": "fachlich",
            "gewichtung": "hoch",
            "status": "unklar",
            "belegart": "",
            "beleg": "",
            "stellenFundstellen": [],
            "belegRefIds": [],
            "behandlung": "vor Erstellung der Kandidatendateien klären",
        }],
        "recruiterStrategie": {
            "kernbotschaft": "durch den Agenten aus Zielrolle, Stellenanforderungen und den stärksten belegten Profilargumenten abzuleiten",
            "profilSubstanz": "noch_zu_pruefen",
            "profilSubstanzBegruendung": "vor der Dokumenterstellung anhand der relevanten Profildaten zu prüfen",
            "prioritaetsAnforderungen": ["muss-1"],
            "profilHighlights": [], "transferbruecken": [], "auslassungen": [],
        },
        "anschreibenStrategie": {"status": "ausstehend" if include_letter else "nicht_erforderlich", "argumente": [], "abweichungBegruendung": ""},
        "externeQuellen": [],
        "stellenanzeigeAbdeckung": {"sourceSha256": "aus Stellenbeschreibung.md übernehmen", "fundstellen": []},
    }


def new_evidence_draft(profile_sha256: Optional[str] = None, order_sha256: Optional[str] = None) -> Dict[str, Any]:
    result: Dict[str, Any] = {"schemaVersion": 1, "profilSha256": profile_sha256 or "aus Profildatei übernehmen", "belege": []}
    if order_sha256:
        result["auftragSha256"] = order_sha256
    return result


def artifact_set_hash(records: Sequence[Mapping[str, Any]], root: Optional[Path] = None) -> str:
    normalized: List[Dict[str, Any]] = []
    for record in records:
        raw_path = str(record.get("path", ""))
        path = Path(raw_path)
        if root is not None:
            path = path if path.is_absolute() else root / path
            raw_path = str(path.absolute())
        normalized.append({
            "path": raw_path.replace("\\", "/"),
            "bytes": int(record.get("bytes", -1)),
            "sha256": str(record.get("sha256", "")).upper(),
        })
    normalized.sort(key=lambda item: item["path"])
    return sha256_bytes(canonical_json(normalized))


def approval_records(report: Mapping[str, Any]) -> List[Mapping[str, Any]]:
    records: List[Mapping[str, Any]] = []
    artifacts = report.get("artifacts")
    if isinstance(artifacts, dict):
        for value in artifacts.values():
            values = value if isinstance(value, list) else [value]
            records.extend(item for item in values if isinstance(item, dict))
    for name in ("layoutReportArtifact", "pdfReportArtifact", "atsReportArtifact"):
        value = report.get(name)
        if isinstance(value, dict):
            records.append(value)
    for name in ("candidate", "screenshots", "reports"):
        value = report.get(name)
        if isinstance(value, list):
            records.extend(item for item in value if isinstance(item, dict))
    if isinstance(report.get("order"), dict):
        records.append(report["order"])
    unique: Dict[str, Mapping[str, Any]] = {}
    for record in records:
        key = str(record.get("path", "")).lower()
        if key not in unique:
            unique[key] = record
    return sorted(unique.values(), key=lambda item: str(item.get("path", "")))


def assert_artifacts_current(records: Sequence[Mapping[str, Any]], root: Path) -> None:
    for record in records:
        raw = str(record.get("path", "")).replace("\\", "/")
        if not raw or re.search(r"(^|/)\.\.(/|$)", raw):
            raise ContractError("Ungültiger Freigabe-Artefaktpfad: %s" % raw)
        candidate = Path(raw)
        if not candidate.is_absolute():
            candidate = root / candidate
        candidate = safe_path(candidate, root, must_exist=True, kind="file")
        expected_bytes = record.get("bytes")
        expected_hash = str(record.get("sha256", "")).upper()
        if not isinstance(expected_bytes, int) or isinstance(expected_bytes, bool) or not re.fullmatch(r"[A-F0-9]{64}", expected_hash):
            raise ContractError("Ungültiger Freigabe-Artefaktrecord: %s" % raw)
        if candidate.stat().st_size != expected_bytes or sha256_file(candidate) != expected_hash:
            raise ContractError("Freigabe-Artefakt wurde verändert: %s" % raw)


def new_approval_id() -> str:
    return "FR-" + uuid.uuid4().hex[:12].upper()


def validate_artifact_record(record: Mapping[str, Any]) -> bool:
    return (
        isinstance(record, dict)
        and isinstance(record.get("path"), str)
        and isinstance(record.get("bytes"), int)
        and not isinstance(record.get("bytes"), bool)
        and bool(re.fullmatch(r"[A-Fa-f0-9]{64}", str(record.get("sha256", ""))))
    )


__all__ = [
    "approval_records", "artifact_record", "artifact_set_hash", "assert_artifacts_current",
    "document_scope", "new_approval_id", "new_evidence_draft", "new_matrix_draft",
    "scope_from_cli", "validate_artifact_record",
]
