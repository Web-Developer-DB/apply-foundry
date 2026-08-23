"""Native, isolated prompt-regression runner for the Linux test dispatcher.

The runner mirrors the public Schema-1 report used on Windows.  It copies only
public repository files into an ephemeral Git worktree, passes exactly one
declared credential to the selected agent process and never prints credentials.
Every agent process additionally runs in a fail-closed bubblewrap mount/PID/user
namespace: only the synthetic worktree and read-only system runtimes are visible.
"""

import fnmatch
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence

from .errors import ContractError
from .io import read_json, sha256_file, write_atomic_json
from .paths import resolve_order_paths


@dataclass(frozen=True)
class _Process:
    exit_code: int
    stdout: str
    stderr: str
    timed_out: bool
    duration_ms: int


def _utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _run(
    executable: str,
    arguments: Sequence[str],
    *,
    cwd: Optional[Path] = None,
    environment: Optional[Mapping[str, str]] = None,
    timeout: int = 15,
    max_stdout: int = 262144,
    max_stderr: int = 16384,
) -> _Process:
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            [executable, *arguments], cwd=str(cwd) if cwd else None,
            env=dict(environment) if environment is not None else None,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            encoding="utf-8", errors="replace", start_new_session=True,
        )
    except OSError as exc:
        raise ContractError("Natives Programm konnte nicht gestartet werden: %s (%s)" % (executable, exc)) from exc
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=3)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
    return _Process(
        1 if timed_out else int(process.returncode), stdout[:max_stdout], stderr[:max_stderr],
        timed_out, max(0, int(round((time.monotonic() - started) * 1000))),
    )


_SANDBOX_ROOT = Path("/workspace")
_SYSTEM_RUNTIME_ROOTS = tuple(Path(value) for value in ("/usr", "/bin", "/sbin", "/lib", "/lib64", "/opt", "/nix/store"))


def _sandbox_runtime_path() -> str:
    """Keep hosted-toolcache runtimes while dropping every home-local PATH."""

    defaults = ("/usr/local/sbin", "/usr/local/bin", "/usr/sbin", "/usr/bin", "/sbin", "/bin")
    candidates = [*os.environ.get("PATH", "").split(os.pathsep), *defaults]
    approved: List[str] = []
    for value in candidates:
        if not value or not Path(value).is_absolute():
            continue
        try:
            resolved = Path(value).resolve(strict=True)
        except OSError:
            continue
        if not resolved.is_dir() or not any(resolved.is_relative_to(root) for root in _SYSTEM_RUNTIME_ROOTS):
            continue
        normalized = str(resolved)
        if normalized not in approved:
            approved.append(normalized)
    if not approved:
        raise ContractError("Prompt-Sandbox besitzt keinen freigegebenen System-PATH.")
    return os.pathsep.join(approved)


def _approved_runtime_executable(executable: str) -> Path:
    try:
        resolved = Path(executable).resolve(strict=True)
    except OSError as exc:
        raise ContractError("Agenten-CLI konnte nicht kanonisch aufgelöst werden: %s" % executable) from exc
    if not resolved.is_file() or not any(resolved.is_relative_to(root) for root in _SYSTEM_RUNTIME_ROOTS):
        raise ContractError(
            "Agenten-CLI liegt außerhalb der im Prompt-Sandboxvertrag erlaubten System-Runtimes: %s" % resolved
        )
    return resolved


def _sandbox_arguments(executable: str, arguments: Sequence[str], scenario_root: Path) -> List[str]:
    """Build a mount-isolated invocation without exposing the host home tree."""

    resolved_executable = _approved_runtime_executable(executable)
    result = [
        "--die-with-parent", "--new-session", "--unshare-all", "--unshare-user", "--share-net",
        "--disable-userns", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp",
    ]
    # A fresh bubblewrap root has no usr-merge aliases.  Recreate system
    # symlinks rather than bind-mounting a symlink as an ambiguous path.
    for runtime_root in _SYSTEM_RUNTIME_ROOTS:
        if runtime_root.is_symlink():
            result.extend(("--symlink", os.readlink(str(runtime_root)), str(runtime_root)))
        elif runtime_root.exists():
            if runtime_root == Path("/nix/store"):
                result.extend(("--dir", "/nix"))
            result.extend(("--ro-bind", str(runtime_root), str(runtime_root)))
    if Path("/etc").is_dir():
        result.extend(("--ro-bind", "/etc", "/etc"))
    # systemd-resolved commonly makes /etc/resolv.conf point into this narrow
    # runtime subtree.  Never expose all of /run (which may hold user secrets).
    resolver = Path("/run/systemd/resolve")
    if resolver.is_dir():
        result.extend(("--dir", "/run", "--dir", "/run/systemd", "--ro-bind", str(resolver), str(resolver)))
    result.extend((
        "--dir", str(_SANDBOX_ROOT),
        "--bind", str(scenario_root), str(_SANDBOX_ROOT),
        "--chdir", str(_SANDBOX_ROOT),
        str(resolved_executable),
    ))
    result.extend(str(item) for item in arguments)
    return result


def _require_sandbox(scenario_root: Path) -> str:
    if os.name != "posix" or not Path("/proc/self/ns/mnt").exists():
        raise ContractError("Prompt-Regression benötigt unter Linux eine echte Mount-Namespace-Isolation.")
    bubblewrap = shutil.which("bwrap")
    if not bubblewrap:
        raise ContractError(
            "Prompt-Regression wurde sicher abgebrochen: bubblewrap fehlt; ein Agent darf nicht direkt auf dem Host-Dateisystem laufen."
        )
    probe_environment = {
        "PATH": _sandbox_runtime_path(),
        "HOME": str(_SANDBOX_ROOT / ".probe-home"),
        "TMPDIR": "/tmp",
    }
    probe = _run(
        bubblewrap,
        _sandbox_arguments("/usr/bin/true", (), scenario_root),
        cwd=scenario_root,
        environment=probe_environment,
        timeout=10,
        max_stdout=4096,
        max_stderr=8192,
    )
    if probe.timed_out or probe.exit_code != 0:
        detail = (probe.stderr or probe.stdout).strip()
        raise ContractError(
            "Prompt-Regression wurde sicher abgebrochen: bubblewrap-Isolation ist nicht nutzbar%s."
            % (" (%s)" % detail if detail else "")
        )
    return bubblewrap


def _load_catalog(path: Path, member: str) -> List[Mapping[str, Any]]:
    value = read_json(path)
    if not isinstance(value, dict) or value.get("schemaVersion") != 1 or not isinstance(value.get(member), list):
        raise ContractError("Prompt-Regressionskatalog besitzt kein unterstütztes Schema 1: %s" % path)
    result = value[member]
    if any(not isinstance(item, dict) for item in result):
        raise ContractError("Prompt-Regressionskatalog enthält einen ungültigen Eintrag: %s" % path)
    return result


def _copy_public_repository(source: Path, destination: Path) -> None:
    excluded = {".git", "Private", ".agents", ".codex", "__pycache__", ".pytest_cache"}
    destination.mkdir(parents=True)
    for current, directory_names, file_names in os.walk(str(source), topdown=True, followlinks=False):
        current_path = Path(current)
        relative_dir = current_path.relative_to(source)
        directory_names[:] = [
            name for name in directory_names
            if name not in excluded and not (current_path / name).is_symlink()
        ]
        target_dir = destination / relative_dir
        target_dir.mkdir(parents=True, exist_ok=True)
        for name in file_names:
            source_file = current_path / name
            if source_file.is_symlink() or name == "test-fast.json" or any(part in excluded for part in source_file.relative_to(source).parts):
                continue
            target = target_dir / name
            shutil.copy2(str(source_file), str(target))


def _initialize_fixture(root: Path, fixture_id: str, scenario_id: Optional[str] = None) -> None:
    data = root / "Private/Daten"
    work = root / "Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle"
    target = root / "Private/Bewerbungen/Synthetische-Firma/2026-08-19--Synthetische-Rolle"
    candidate = work / "Kandidat"
    data.mkdir(parents=True)
    work.mkdir(parents=True)
    candidate.mkdir(parents=True)
    personal = data / "01_PERSOENLICHE_DATEN.md"
    profile = data / "02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"
    job = candidate / "Stellenbeschreibung.md"
    personal.write_text(
        "# Persönliche Daten\n"
        "- Vollständiger Name: Synthetische Person\n- Vorname: Synthetische\n- Nachname: Person\n"
        "- Dateiname-Name: SYNTHETISCHE.PERSON\n- Adresse: Testweg 1, 12345 Beispielstadt\n"
        "- Telefon: +49 000 000000\n- E-Mail: synthetische.person@example.invalid\n"
        "- Verfügbarkeit: nach Vereinbarung\n- Frühester Eintrittstermin: nach Vereinbarung\n"
        "- Gewünschte Stellenart: Vollzeit\n- Gewünschtes Arbeitsmodell: hybrid\n"
        "- Gewünschte Region: Deutschland\n- Wunschgehalt verwenden: nein\n"
        "- Wunschgehalt manuell: nicht angegeben\n- Gehaltsmodell: Jahresbrutto\n",
        encoding="utf-8",
    )
    profile.write_text(
        "# Bewerberprofil\n## Synthetische Belege\n"
        "- Beruflich belegte Dokumentation und strukturierte Kommunikation\n"
        "- Weiterbildung mit nachvollziehbarer Praxis\n"
        "- Eigene Projektpraxis und ehrliche Transfergrundlage\n",
        encoding="utf-8",
    )
    job.write_text(
        "# Synthetische Stelle: %s\n- Fiktive Anforderungen, Dokumentation und verlässliche Zusammenarbeit\n"
        "- Konkrete Aufgaben mit nachvollziehbarem eigenem Beitrag\n" % fixture_id,
        encoding="utf-8",
    )
    order_path = work / "Bewerbungsauftrag.json"
    dialog: Dict[str, Any] = {
        "schemaVersion": 1, "status": "bereit_zur_dokumenterstellung",
        "rueckfragen": [], "angaben": [], "updatedAtUtc": "2026-08-19T12:00:00Z",
    }
    if scenario_id == "widerspruch-und-fortsetzung":
        dialog = {
            "schemaVersion": 1, "status": "rueckfragen_offen", "updatedAtUtc": "2026-08-19T12:00:00Z",
            "rueckfragen": [{
                "id": "frage-verfuegbarkeit", "art": "widerspruch", "status": "offen",
                "frage": "Gilt 'sofort' oder 'in drei Monaten'?", "runde": 1,
                "blockiertDokumenterstellung": True, "widerspruch": True,
                "widerspruchGeklaert": False, "angabeIds": ["angabe-verfuegbarkeit"],
            }],
            "angaben": [{
                "id": "angabe-verfuegbarkeit", "wert": "in drei Monaten",
                "wahrheitsstatus": "widerspruechlich", "widerspruch": True,
                "widerspruchGeklaert": False, "speicherentscheidung": "nur_auftrag",
                "profilaktualisierung": {"status": "nicht_geaendert"},
            }],
        }
    work_relative = "Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle"
    write_atomic_json(order_path, {
        "schemaVersion": 5, "pfadModus": "relativ_zu_bewerbungen_root",
        "firma": "Synthetische Firma", "firmaSlug": "Synthetische-Firma",
        "rolle": "Synthetische Rolle", "rolleSlug": "Synthetische-Rolle", "datum": "2026-08-19",
        "bewerberDateiname": "SYNTHETISCHE.PERSON", "dokumentmodus": "vollbewerbung",
        "dokumentumfang": {
            "auswahl": "A", "kennung": "komplette_bewerbung", "lebenslauf": "individuell",
            "anschreiben": True, "emailNachricht": True, "quelle": "direkter_auftrag",
            "bestaetigt": True, "emailAlleinBestaetigt": False,
            "bestaetigtAtUtc": "2026-08-19T12:00:00Z",
        },
        "bewerbungsentscheidung": "bewerben",
        "zielOrdner": "Synthetische-Firma/2026-08-19--Synthetische-Rolle",
        "arbeitsOrdner": work_relative, "kandidatOrdner": work_relative + "/Kandidat",
        "seitenstrategie": "eine_seite", "universalLebenslauf": None,
        "bewerbungslogistik": {"verfuegbarkeit": "sofort"}, "dialog": dialog,
        "quellnachweise": {"stammdatenSha256BeiAnlage": sha256_file(personal), "profilSha256BeiAnlage": sha256_file(profile)},
        "createdAtUtc": "2026-08-19T12:00:00Z",
    })
    (work / "Arbeitsnotizen.md").write_text(
        "# Arbeitsnotizen\n\n- Firma: Synthetische Firma\n- Zielrolle: Synthetische Rolle\n"
        "- Dokumentmodus: vollbewerbung\n- Dokumentumfang: Lebenslauf=individuell; Anschreiben=true; E-Mail=true\n"
        "- Finaler Bewerbungsordner: %s\n- Entwurfs-/Arbeitsdateien: %s\n- Kandidatendateien vor Freigabe: %s\n"
        % (target, work, candidate),
        encoding="utf-8",
    )


def _git(root: Path, arguments: Sequence[str]) -> _Process:
    git = shutil.which("git")
    if not git:
        raise ContractError("Git fehlt; isolierte Prompt-Regression ist nicht verfügbar.")
    result = _run(git, arguments, cwd=root, timeout=30, max_stdout=131072, max_stderr=131072)
    if result.exit_code != 0:
        raise ContractError("Git-Schritt fehlgeschlagen: %s" % (result.stderr.strip() or "Exitcode %d" % result.exit_code))
    return result


def _initialize_git(root: Path) -> None:
    _git(root, ["init", "--quiet"])
    info = root / ".git/info/exclude"
    with info.open("a", encoding="utf-8") as stream:
        stream.write("\n.agent-home/\n.tmp/\n")
    _git(root, ["add", "-A", "--", "."])
    _git(root, ["-c", "user.name=apply-foundry", "-c", "user.email=tests@example.invalid", "commit", "--quiet", "-m", "synthetic baseline"])


def _base_sandbox_environment(
    home: Path,
    sandbox_home: Path = _SANDBOX_ROOT / ".agent-home",
) -> Dict[str, str]:
    environment: Dict[str, str] = {
        "PATH": _sandbox_runtime_path(),
        "SHELL": "/bin/sh",
    }
    for name in ("LANG", "LC_ALL", "CI"):
        value = os.environ.get(name)
        if value:
            environment[name] = value
    environment["HOME"] = str(sandbox_home)
    environment["USERPROFILE"] = str(sandbox_home)
    environment["XDG_CONFIG_HOME"] = str(sandbox_home / ".config")
    environment["XDG_DATA_HOME"] = str(sandbox_home / ".local/share")
    environment["CODEX_HOME"] = str(sandbox_home / ".codex")
    environment["OPENCODE_CONFIG_DIR"] = str(sandbox_home / ".config/opencode")
    environment["TEMP"] = str(_SANDBOX_ROOT / ".tmp")
    environment["TMP"] = str(_SANDBOX_ROOT / ".tmp")
    environment["TMPDIR"] = str(_SANDBOX_ROOT / ".tmp")
    for path in (home / ".config/opencode", home / ".local/share", home / ".codex", home.parent / ".tmp"):
        path.mkdir(parents=True, exist_ok=True)
    return environment


def _isolated_environment(
    credential_name: str,
    home: Path,
    sandbox_home: Path = _SANDBOX_ROOT / ".agent-home",
) -> Dict[str, str]:
    if not re.fullmatch(r"[A-Z][A-Z0-9_]{1,79}", credential_name):
        raise ContractError("Ungültiger Credential-Variablenname im Modellkatalog.")
    credential = os.environ.get(credential_name)
    if not credential or not credential.strip():
        raise ContractError("Credential fehlt: %s" % credential_name)
    environment = _base_sandbox_environment(home, sandbox_home)
    environment[credential_name] = credential
    return environment


def _arguments(model: Mapping[str, Any], prompt: str) -> List[str]:
    raw = model.get("arguments")
    if not isinstance(raw, list) or any(not isinstance(item, str) for item in raw):
        raise ContractError("Modellkatalog enthält keine sichere Argumentliste: %s" % model.get("id"))
    result = list(raw)
    requested_model = model.get("model")
    if not isinstance(requested_model, str) or not requested_model.strip():
        raise ContractError("Modellkatalog enthält kein explizites Zielmodell: %s" % model.get("id"))
    if "--model" not in result:
        raise ContractError("Agentenaufruf bindet das Zielmodell nicht mit --model: %s" % model.get("id"))
    model_index = result.index("--model")
    if model_index + 1 >= len(result) or result[model_index + 1] != requested_model:
        raise ContractError("Agentenaufruf und Zielmodell widersprechen sich: %s" % model.get("id"))
    if model.get("agent") == "codex" and "--ignore-user-config" not in result:
        raise ContractError("Codex-Promptlauf muss nutzerlokale Konfiguration mit --ignore-user-config ausschließen.")
    # All mutation remains confined to the bubblewrap-bound synthetic
    # /workspace.  Plan/read-only modes would make the role scenarios
    # impossible by construction, so use each CLI's explicit edit policy.
    policy_flags = {
        "codex": ("--sandbox", "workspace-write"),
        "claude": ("--permission-mode", "acceptEdits"),
        "gemini": ("--approval-mode", "auto_edit"),
    }
    policy = policy_flags.get(str(model.get("agent")))
    if policy is not None:
        flag, value = policy
        if flag not in result:
            raise ContractError("Agentenaufruf enthält keinen expliziten Workspace-Modus: %s" % model.get("id"))
        policy_index = result.index(flag)
        if policy_index + 1 >= len(result):
            raise ContractError("Agentenaufruf enthält keinen Wert für %s: %s" % (flag, model.get("id")))
        result[policy_index + 1] = value
    if model.get("agent") == "gemini" and "--prompt" in result:
        index = result.index("--prompt")
        if index + 1 < len(result) and result[index + 1] == "":
            result[index + 1] = prompt
            return result
    result.append(prompt)
    return result


def _scenario_output_error(scenario: Mapping[str, Any], output: str) -> Optional[str]:
    folded = output.casefold()
    for pattern in scenario.get("requiredPatterns") or []:
        if str(pattern).casefold() not in folded:
            return "Pflichtsignal fehlt: %s" % pattern
    for pattern in scenario.get("forbiddenPatterns") or []:
        if str(pattern).casefold() in folded:
            return "Verbotenes Signal gefunden: %s" % pattern
    return None


def _changed_paths(changes: Sequence[str]) -> List[str]:
    result = []
    for change in changes:
        relative = re.sub(r"^[ MADRCU?!]{1,3}\s+", "", change).strip().replace("\\", "/")
        if " -> " in relative:
            relative = relative.split(" -> ", 1)[1]
        if relative:
            result.append(relative)
    return result


def _scenario_artifact_error(
    scenario: Mapping[str, Any],
    root: Path,
    changes: Sequence[str],
) -> Optional[str]:
    if not str(scenario.get("id", "")).startswith("rollenstrategie-"):
        return None
    base = Path("Private/Bewerbungen/Synthetische-Firma/_Arbeitsdateien/2026-08-19--Synthetische-Rolle")
    candidate = base / "Kandidat"
    required = ("Bewerbungsauftrag.json", "Anforderungsmatrix.json", "Evidenzindex.json")
    for name in required:
        relative = base / name
        if not (root / relative).is_file():
            return "Erwartetes Rollenartefakt fehlt: %s" % relative.as_posix()
    changed = set(_changed_paths(changes))
    for name in ("Anforderungsmatrix.json", "Evidenzindex.json"):
        relative = (base / name).as_posix()
        if relative not in changed:
            return "Rollenartefakt wurde im Szenariolauf nicht erzeugt oder geändert: %s" % relative
    try:
        applications = root / "Private/Bewerbungen"
        work = root / base
        order_path = work / "Bewerbungsauftrag.json"
        order = read_json(order_path)
        resolve_order_paths(order, applications, work)
        matrix = read_json(work / "Anforderungsmatrix.json")
        evidence = read_json(work / "Evidenzindex.json")
    except (ContractError, OSError, ValueError, TypeError) as exc:
        return "Rollenartefakte verletzen den Pfad-/JSON-Vertrag: %s" % exc
    requirements = matrix.get("requirements") if isinstance(matrix, dict) else None
    strategy = matrix.get("recruiterStrategie") if isinstance(matrix, dict) else None
    coverage = matrix.get("stellenanzeigeAbdeckung") if isinstance(matrix, dict) else None
    letter_strategy = matrix.get("anschreibenStrategie") if isinstance(matrix, dict) else None
    job = root / candidate / "Stellenbeschreibung.md"
    if matrix.get("schemaVersion") != 5 or not isinstance(requirements, list) or not requirements:
        return "Anforderungsmatrix ist keine inhaltliche Schema-5-Matrix."
    if not isinstance(coverage, dict) or str(coverage.get("sourceSha256", "")).upper() != sha256_file(job):
        return "Anforderungsmatrix ist nicht an die synthetische Stellenbeschreibung gebunden."
    if not isinstance(strategy, dict) or not str(strategy.get("kernbotschaft", "")).strip() or strategy.get("profilSubstanz") in (None, "", "noch_zu_pruefen"):
        return "Anforderungsmatrix enthält keine abgeschlossene Recruiter-Strategie."
    if not isinstance(letter_strategy, dict) or letter_strategy.get("status") != "final" or not isinstance(letter_strategy.get("argumente"), list) or not letter_strategy["argumente"]:
        return "Anforderungsmatrix enthält keine finale, belegte Anschreibenstrategie."
    if evidence.get("schemaVersion") != 1 or evidence.get("profilSha256") != sha256_file(root / "Private/Daten/02_BEWERBER_PROFIL_UND_POSITIONIERUNG.md"):
        return "Evidenzindex ist nicht an das synthetische Profil gebunden."
    if evidence.get("auftragSha256") != sha256_file(order_path) or not isinstance(evidence.get("belege"), list) or not evidence["belege"]:
        return "Evidenzindex ist nicht an Auftrag und konkrete Belege gebunden."
    evidence_ids = {str(item.get("id")) for item in evidence["belege"] if isinstance(item, dict)}
    for requirement in requirements:
        if not isinstance(requirement, dict) or not str(requirement.get("id", "")):
            return "Anforderungsmatrix enthält einen ungültigen Requirement-Eintrag."
        references = requirement.get("belegRefIds")
        if not isinstance(references, list) or not references or any(str(item) not in evidence_ids for item in references):
            return "Requirement %s besitzt keine auflösbaren Evidenzreferenzen." % requirement.get("id", "?")
    if scenario.get("id") == "rollenstrategie-direkt":
        expected_documents = (
            candidate / "Lebenslauf - SYNTHETISCHE.PERSON.html",
            candidate / "Anschreiben - SYNTHETISCHE.PERSON.html",
            candidate / "Email-Nachricht--Synthetische-Firma.md",
        )
        for relative in expected_documents:
            path = root / relative
            if not path.is_file() or relative.as_posix() not in changed:
                return "Ausgewählter Rollenentwurf wurde nicht neu erzeugt: %s" % relative.as_posix()
            text = path.read_text(encoding="utf-8")
            if re.search(r"(?i)\[ergänzen\]|\{\{[^}]+\}\}|TODO|DOKUMENT NOCH NICHT FINAL", text):
                return "Ausgewählter Rollenentwurf enthält einen Platzhalter: %s" % relative.as_posix()
            if path.suffix == ".html" and not (
                re.search(r"@page\s*\{[^}]*size\s*:\s*A4\s*;[^}]*margin\s*:\s*0\s*;", text, re.I | re.S)
                and re.search(r"\.page\s*\{[^}]*width\s*:\s*210mm\s*;[^}]*height\s*:\s*297mm\s*;", text, re.I | re.S)
            ):
                return "HTML-Rollenentwurf verletzt den A4-Vertrag: %s" % relative.as_posix()
    return None


def _changes(root: Path) -> List[str]:
    output = _git(root, ["status", "--short", "--untracked-files=all"]).stdout
    return [line.rstrip() for line in output.splitlines() if line.strip()]


def _mutation_error(changes: Sequence[str], patterns: Sequence[str]) -> Optional[str]:
    for change in changes:
        relative_values = _changed_paths((change,))
        if not relative_values:
            continue
        relative = relative_values[0]
        if not any(fnmatch.fnmatchcase(relative, str(pattern).replace("\\", "/")) for pattern in patterns):
            return "Nicht erlaubte Dateimutation: %s" % relative
    return None


def _reported_model(output: str, expected: str) -> tuple[Optional[str], Optional[str]]:
    candidates: List[str] = []

    def visit(value: Any) -> None:
        if isinstance(value, dict):
            provider = value.get("providerID") or value.get("providerId") or value.get("provider")
            model_id = value.get("modelID") or value.get("modelId")
            if isinstance(provider, str) and isinstance(model_id, str):
                candidates.append(provider + "/" + model_id)
            for key, item in value.items():
                normalized = str(key).replace("_", "").replace("-", "").casefold()
                if normalized in ("model", "modelid", "modelname") and isinstance(item, str):
                    candidates.append(item)
                visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)

    documents = [output]
    documents.extend(line for line in output.splitlines() if line.strip())
    for document in documents:
        try:
            visit(json.loads(document))
        except (json.JSONDecodeError, TypeError):
            continue
    if not candidates:
        for match in re.finditer(r'"(?:model|modelId|modelID|model_name)"\s*:\s*"([^"\\]+)"', output):
            candidates.append(match.group(1))
    unique = list(dict.fromkeys(item.strip() for item in candidates if item.strip()))

    def equivalent(actual: str) -> bool:
        return actual == expected or ("/" in expected and actual == expected.split("/", 1)[1])

    for candidate in unique:
        if equivalent(candidate):
            return candidate, None
    if not unique:
        # Some pinned CLIs (notably Codex exec --json) expose no backend model
        # in their event stream.  The caller records the exact, catalog-bound
        # --model vector as routing evidence without claiming an actual model.
        return None, None
    return unique[0], "Unerwartete Modellweiterleitung: %s statt %s" % (unique[0], expected)


def _failure_class(error: Optional[str]) -> Optional[str]:
    if error is None:
        return None
    if re.search(r"timeout", error, re.I):
        return "infrastructure_timeout"
    if re.search(r"credential|secret|PRIVATE|Private", error, re.I):
        return "security_or_configuration"
    if re.search(r"mutation|Modellweiterleitung", error, re.I):
        return "contract_violation"
    if re.search(r"exitcode", error, re.I):
        return "agent_runtime"
    return "scenario_assertion"


def _runtime() -> Dict[str, Any]:
    import platform

    return {
        "os": "linux", "architecture": platform.machine().lower(), "python": platform.python_version(),
        "coreRuntime": {"language": "python", "version": platform.python_version()},
    }


def run_prompt_regression(ctx: Any, matrix: str, report_path: Optional[Path], test_pattern: Optional[str]) -> int:
    if matrix not in ("pr", "vollstaendig"):
        raise ContractError("Unbekannte Prompt-Regressionsmatrix: %s" % matrix)
    started = datetime.now(timezone.utc)
    monotonic_started = time.monotonic()
    results: List[Dict[str, Any]] = []
    failures: List[str] = []
    try:
        model_path = ctx.project_root / "Tests/PromptRegression/models.json"
        scenario_path = ctx.project_root / "Tests/PromptRegression/scenarios.json"
        models = [item for item in _load_catalog(model_path, "models") if item.get("tier") == "pr" or matrix == "vollstaendig"]
        scenarios = [item for item in _load_catalog(scenario_path, "scenarios") if item.get("tier") == "pr" or matrix == "vollstaendig"]
        if test_pattern:
            try:
                pattern = re.compile(test_pattern)
            except re.error as exc:
                raise ContractError("TestNamePattern ist kein gültiger regulärer Ausdruck: %s" % exc) from exc
            scenarios = [item for item in scenarios if pattern.search(str(item.get("id", "")))]
        if not models:
            raise ContractError("Keine Prompt-Regression ist für die gewählte Matrix konfiguriert.")
        if not scenarios:
            raise ContractError("Kein Prompt-Szenario entspricht dem Muster: %s" % test_pattern)
        catalog = read_json(model_path)
        timeout = int(catalog.get("defaultTimeoutSeconds", 180))
        if timeout < 1 or timeout > 1800:
            raise ContractError("Prompt-Regressionskatalog enthält keinen sicheren Timeout.")
        with tempfile.TemporaryDirectory(prefix="bewerbungs-agent-prompt-") as temporary:
            temporary_root = Path(temporary)
            sandbox_executable: Optional[str] = None
            for model in models:
                command = str(model.get("command", ""))
                executable = shutil.which(command)
                if not executable:
                    raise ContractError("Agenten-CLI fehlt: %s" % command)
                probe_root = temporary_root / ".sandbox-probe"
                probe_root.mkdir(exist_ok=True)
                if sandbox_executable is None:
                    sandbox_executable = _require_sandbox(probe_root)
                probe_home = probe_root / ".agent-home"
                version = _run(
                    sandbox_executable,
                    _sandbox_arguments(executable, ("--version",), probe_root),
                    cwd=probe_root,
                    environment=_base_sandbox_environment(probe_home),
                    timeout=15,
                    max_stdout=4096,
                    max_stderr=4096,
                )
                version_text = (version.stdout + "\n" + version.stderr).strip()
                if version.timed_out or version.exit_code != 0:
                    raise ContractError("CLI '%s' meldet keine gültige Version." % command)
                if str(model.get("cliVersion", "")) not in version_text:
                    raise ContractError("CLI-Version für %s weicht ab. Erwartet %s, erhalten: %s" % (model.get("id"), model.get("cliVersion"), version_text))
                for scenario in scenarios:
                    scenario_root = temporary_root / ("%s-%s" % (model.get("id"), scenario.get("id")))
                    _copy_public_repository(ctx.project_root, scenario_root)
                    if scenario.get("fixture"):
                        _initialize_fixture(scenario_root, str(scenario["fixture"]), str(scenario.get("id", "")))
                    sentinel = scenario_root / "PRIVATE_SENTINEL.txt"
                    sentinel.write_text("PRIVATE_SENTINEL\n", encoding="utf-8")
                    _initialize_git(scenario_root)
                    home = scenario_root / ".agent-home"
                    environment = _isolated_environment(str(model.get("credentialVariable", "")), home)
                    prompt = str(scenario.get("prompt", ""))
                    invocation = _arguments(model, prompt)
                    attempt = 0
                    process: Optional[_Process] = None
                    combined = ""
                    while attempt < 3:
                        attempt += 1
                        process = _run(
                            sandbox_executable,
                            _sandbox_arguments(executable, invocation, scenario_root),
                            cwd=scenario_root,
                            environment=environment,
                            timeout=timeout,
                        )
                        combined = process.stdout + "\n" + process.stderr
                        transient = bool(re.search(r"rate.?limit|quota|temporar|timeout|transport|connection reset|503|429", combined, re.I))
                        if process.timed_out or not transient or attempt >= 3:
                            break
                        time.sleep(2 * attempt)
                    assert process is not None
                    error: Optional[str] = None
                    if process.timed_out:
                        error = "Timeout"
                    elif process.exit_code != 0:
                        error = "Exitcode %d" % process.exit_code
                    else:
                        error = _scenario_output_error(scenario, combined)
                    changes = _changes(scenario_root)
                    if error is None:
                        error = _scenario_artifact_error(scenario, scenario_root, changes)
                    allowed = [str(item) for item in (scenario.get("allowedFileChanges") or [])]
                    if error is None and not allowed and changes:
                        error = "Szenario sollte keine Dateimutationen erzeugen."
                    if error is None and allowed and not changes:
                        error = "Szenario verlangt nachweisbare Dateimutationen, erzeugte aber keine."
                    if error is None and allowed:
                        error = _mutation_error(changes, allowed)
                    actual_model, model_error = _reported_model(combined, str(model.get("model")))
                    if error is None and model_error is not None:
                        error = model_error
                    status = "bestanden" if error is None else "fehlgeschlagen"
                    result = {
                        "modelId": str(model.get("id")), "agent": str(model.get("agent")),
                        "provider": str(model.get("provider")), "credentialVariable": str(model.get("credentialVariable")),
                        "model": str(model.get("model")), "requestedModel": str(model.get("model")),
                        "actualModel": actual_model,
                        "modelEvidence": "machine_readable_cli_output" if actual_model else "explicit_catalog_bound_argument_vector",
                        "cliPackage": str(model.get("cliPackage")),
                        "cliVersion": str(model.get("cliVersion")), "tokenAvailability": "not_provided",
                        "tokenValues": None, "scenario": str(scenario.get("id")), "status": status,
                        "errorClass": _failure_class(error), "error": error, "exitCode": process.exit_code,
                        "timedOut": process.timed_out, "durationMs": process.duration_ms,
                        "attempts": attempt, "filesChanged": changes,
                        "workspaceIsolation": "bubblewrap_synthetic_workspace",
                    }
                    results.append(result)
                    if error is not None:
                        failures.append("%s/%s: %s" % (model.get("id"), scenario.get("id"), error))
    except (ContractError, OSError, ValueError, TypeError) as exc:
        failures.append(str(exc))
    ended = datetime.now(timezone.utc)
    report = {
        "schemaVersion": 1, "suite": "prompt-" + matrix, "matrix": matrix,
        "testNamePattern": test_pattern, "startedAtUtc": _utc(started), "endedAtUtc": _utc(ended),
        "durationMs": max(0, int(round((time.monotonic() - monotonic_started) * 1000))),
        "runtime": _runtime(),
        "isolation": {
            "kind": "bubblewrap_mount_pid_user_namespace", "hostHomeVisible": False,
            "networkSharedForProviderApi": True, "failClosedWhenUnavailable": True,
        },
        "status": "bestanden" if not failures else "fehlgeschlagen",
        "results": results, "failures": failures,
    }
    if report_path is not None:
        write_atomic_json(report_path, report)
        ctx.out("Prompt-Regressionsbericht: %s" % report_path)
    ctx.out("Prompt-Regressionssuite (%s): %d ausgeführt, %d fehlgeschlagen." % (matrix, len(results), len(failures)))
    for failure in failures:
        ctx.error(failure)
    return 0 if not failures else 1


__all__ = ["run_prompt_regression"]
