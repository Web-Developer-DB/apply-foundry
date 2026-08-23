#!/usr/bin/env python3
"""Installationsplan und Bootstrap für die deklarierten Linux-Abhängigkeiten.

Das Modul verwendet ausschließlich die Python-Standardbibliothek. Paketnamen
und Quellen stammen aus Linux-dependencies.json; Paketmanager werden immer mit
getrennten Argumentlisten aufgerufen.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shlex
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


EXIT_OK = 0
EXIT_RUNTIME_ERROR = 1
EXIT_USAGE_OR_PLATFORM = 2
COMPONENT_NAMES = ("coreRuntime", "browser", "fonts", "shellcheck")
COMPONENT_LABELS = {
    "coreRuntime": "Python",
    "browser": "Chromium",
    "fonts": "Liberation Sans",
    "shellcheck": "ShellCheck",
}
PACKAGE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+_.-]*$")
VERSION_RE = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?(?:[^0-9].*)?$")
CATALOG_PATH = Path(__file__).with_name("Linux-dependencies.json")


class SetupError(Exception):
    def __init__(self, message: str, exit_code: int = EXIT_RUNTIME_ERROR) -> None:
        super().__init__(message)
        self.exit_code = exit_code


class CommandError(SetupError):
    pass


@dataclass(frozen=True)
class Options:
    runtime: bool
    browser: bool
    fonts: bool
    shellcheck: bool
    dry_run: bool
    assume_yes: bool
    output_format: str

    @property
    def selected(self) -> Mapping[str, bool]:
        return {
            "coreRuntime": self.runtime,
            "browser": self.browser,
            "fonts": self.fonts,
            "shellcheck": self.shellcheck,
        }


@dataclass(frozen=True)
class PlatformContext:
    distro_id: str
    distro_version: str
    architecture: str
    manager: str
    manager_executable: str


@dataclass(frozen=True)
class Detection:
    present: bool
    version: Optional[str] = None
    path: Optional[str] = None
    provider: Optional[str] = None


def minimum_version_tuple(value: str) -> Tuple[int, int]:
    match = VERSION_RE.fullmatch(value)
    if match is None:
        raise SetupError(
            "Das Linux-Abhängigkeitsmanifest enthält eine ungültige Python-Mindestversion.",
            EXIT_USAGE_OR_PLATFORM,
        )
    return int(match.group(1)), int(match.group(2))


def load_catalog(path: Path = CATALOG_PATH) -> Dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise SetupError(
            "Linux-Abhängigkeitsmanifest konnte nicht gelesen werden: {0}".format(exc),
            EXIT_USAGE_OR_PLATFORM,
        ) from exc

    if not isinstance(raw, dict) or type(raw.get("schemaVersion")) is not int:
        raise SetupError("Linux-Abhängigkeitsmanifest besitzt kein gültiges Schema.", EXIT_USAGE_OR_PLATFORM)
    if raw.get("schemaVersion") != 1 or raw.get("kind") != "apply-foundry-linux-dependencies":
        raise SetupError("Linux-Abhängigkeitsmanifest verwendet einen unbekannten Vertrag.", EXIT_USAGE_OR_PLATFORM)
    minimum_version_tuple(str(raw.get("minimumPythonVersion", "")))

    architectures = raw.get("supportedArchitectures")
    precedence = raw.get("managerPrecedence")
    managers = raw.get("packageManagers")
    if architectures != ["x86_64"] or not isinstance(precedence, list) or not isinstance(managers, dict):
        raise SetupError("Linux-Abhängigkeitsmanifest ist unvollständig.", EXIT_USAGE_OR_PLATFORM)
    if not precedence or len(set(precedence)) != len(precedence):
        raise SetupError("Paketmanager-Priorität im Manifest ist ungültig.", EXIT_USAGE_OR_PLATFORM)

    for manager_name in precedence:
        manager = managers.get(manager_name)
        if not isinstance(manager_name, str) or not isinstance(manager, dict):
            raise SetupError("Paketmanager im Manifest ist ungültig.", EXIT_USAGE_OR_PLATFORM)
        executable = manager.get("executable")
        components = manager.get("components")
        if not isinstance(executable, str) or PACKAGE_RE.fullmatch(executable) is None:
            raise SetupError("Paketmanager-Executable im Manifest ist unsicher.", EXIT_USAGE_OR_PLATFORM)
        if not isinstance(components, dict) or set(components) != set(COMPONENT_NAMES):
            raise SetupError("Komponentenliste im Manifest ist unvollständig.", EXIT_USAGE_OR_PLATFORM)
        for component_name in COMPONENT_NAMES:
            component = components.get(component_name)
            if not isinstance(component, dict):
                raise SetupError("Komponentendefinition im Manifest ist ungültig.", EXIT_USAGE_OR_PLATFORM)
            packages = component.get("packages")
            source = component.get("source")
            if not isinstance(packages, list) or not packages or not all(
                isinstance(package, str) and PACKAGE_RE.fullmatch(package) is not None for package in packages
            ):
                raise SetupError("Unsichere Paketdefinition im Linux-Manifest.", EXIT_USAGE_OR_PLATFORM)
            if not isinstance(source, str) or not source.strip():
                raise SetupError("Paketquelle im Linux-Manifest fehlt.", EXIT_USAGE_OR_PLATFORM)
    return raw


def read_os_release(path: Path = Path("/etc/os-release")) -> Mapping[str, str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise SetupError("/etc/os-release fehlt oder ist nicht lesbar.", EXIT_USAGE_OR_PLATFORM) from exc
    values: Dict[str, str] = {}
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, encoded = stripped.split("=", 1)
        if re.fullmatch(r"[A-Z0-9_]+", key) is None:
            continue
        try:
            parsed = shlex.split(encoded, posix=True)
        except ValueError:
            continue
        if len(parsed) == 1:
            values[key] = parsed[0]
        elif encoded == "":
            values[key] = ""
    return values


def normalize_architecture(value: str) -> str:
    lowered = value.strip().lower()
    if lowered in ("x86_64", "amd64"):
        return "x86_64"
    return lowered


def resolve_trusted_executable(path: str) -> Optional[str]:
    """Accept only system-owned executables that cannot be replaced by users.

    In managed/user-namespace sandboxes the host root owner can be mapped to a
    nonzero UID. Comparing against the owner of ``/`` keeps that environment
    testable without accepting executables owned by the invoking user.
    """
    try:
        candidate = Path(path)
        if not candidate.is_absolute():
            return None
        resolved = candidate.resolve(strict=True)
        metadata = resolved.stat()
        system_owner = Path("/").stat().st_uid
    except OSError:
        return None
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != system_owner or metadata.st_mode & 0o022:
        return None
    for parent in resolved.parents:
        try:
            parent_metadata = parent.stat()
        except OSError:
            return None
        if parent_metadata.st_uid != system_owner or parent_metadata.st_mode & 0o022:
            return None
    if not os.access(str(resolved), os.X_OK):
        return None
    return str(resolved)


def build_context(
    catalog: Mapping[str, Any],
    which: Callable[[str], Optional[str]] = shutil.which,
    machine: Optional[str] = None,
    os_release_path: Path = Path("/etc/os-release"),
    trust_executable: Callable[[str], Optional[str]] = resolve_trusted_executable,
) -> PlatformContext:
    architecture = normalize_architecture(machine if machine is not None else platform.machine())
    if architecture not in catalog["supportedArchitectures"]:
        raise SetupError("Nur Linux x86_64 wird unterstützt.", EXIT_USAGE_OR_PLATFORM)
    os_release = read_os_release(os_release_path)
    distro_id = os_release.get("ID", "unknown").strip().lower() or "unknown"
    distro_version = os_release.get("VERSION_ID", "unknown").strip() or "unknown"
    for manager_name in catalog["managerPrecedence"]:
        executable_name = catalog["packageManagers"][manager_name]["executable"]
        executable_path = which(executable_name)
        if executable_path:
            trusted_path = trust_executable(executable_path)
            if trusted_path:
                return PlatformContext(distro_id, distro_version, architecture, manager_name, trusted_path)
    raise SetupError(
        "Kein unterstützter Paketmanager erkannt (APT, DNF/YUM, Pacman oder Zypper). "
        "Manuell benötigt: System-Python >= {0}, Chromium, Liberation Sans und optional ShellCheck.".format(
            catalog["minimumPythonVersion"]
        ),
        EXIT_USAGE_OR_PLATFORM,
    )


def capture_command(args: Sequence[str], timeout: int = 10) -> Optional[subprocess.CompletedProcess[str]]:
    try:
        return subprocess.run(
            list(args),
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def python_candidates(which: Callable[[str], Optional[str]] = shutil.which) -> Iterable[str]:
    candidates: List[str] = []
    for fixed in ("/usr/bin/python3", "/bin/python3"):
        if Path(fixed).is_file():
            candidates.append(fixed)
    for name in ("python3", "python"):
        found = which(name)
        if found:
            candidates.append(found)
    candidates.append(sys.executable)
    seen = set()
    for candidate in candidates:
        try:
            normalized = str(Path(candidate).resolve(strict=True))
        except OSError:
            continue
        trusted = resolve_trusted_executable(normalized)
        if trusted is not None and trusted not in seen:
            seen.add(trusted)
            yield trusted


def detect_python(minimum: Tuple[int, int], which: Callable[[str], Optional[str]] = shutil.which) -> Detection:
    probe = (
        "import json,sys; "
        "print(json.dumps({'version':list(sys.version_info[:3]),'executable':sys.executable,"
        "'prefix':sys.prefix,'base_prefix':getattr(sys,'base_prefix',sys.prefix)}))"
    )
    for executable in python_candidates(which):
        result = capture_command((executable, "-I", "-c", probe))
        if result is None or result.returncode != 0:
            continue
        try:
            data = json.loads(result.stdout)
            version_values = data["version"]
            version = tuple(int(part) for part in version_values[:3])
            is_system = str(data["prefix"]) == str(data["base_prefix"])
            reported_path = str(Path(str(data["executable"])).resolve(strict=True))
        except (KeyError, TypeError, ValueError, OSError, json.JSONDecodeError):
            continue
        if is_system and version[:2] >= minimum:
            return Detection(True, ".".join(str(part) for part in version), reported_path)
    return Detection(False)


def detect_browser(
    which: Callable[[str], Optional[str]] = shutil.which,
    trust_executable: Callable[[str], Optional[str]] = resolve_trusted_executable,
) -> Detection:
    candidates = (
        ("google-chrome", "Google Chrome"),
        ("google-chrome-stable", "Google Chrome"),
        ("chromium", "Chromium"),
        ("chromium-browser", "Chromium"),
        ("microsoft-edge", "Microsoft Edge"),
        ("microsoft-edge-stable", "Microsoft Edge"),
    )
    seen = set()
    for name, provider in candidates:
        executable = which(name)
        if not executable or executable.startswith("/snap/"):
            continue
        try:
            resolved = str(Path(executable).resolve(strict=True))
        except OSError:
            continue
        if resolved == "/usr/bin/snap" or resolved.startswith("/snap/"):
            continue
        trusted = trust_executable(resolved)
        if trusted is None:
            continue
        resolved = trusted
        try:
            launcher = Path(resolved)
            if launcher.stat().st_size <= 131072:
                prefix = launcher.read_bytes()[:131072]
                if prefix.startswith(b"#!") and re.search(rb"(?im)(?:^|[\s/])snap(?:\s+run)?\s+", prefix):
                    continue
        except OSError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        result = capture_command((executable, "--version"))
        if result is None or result.returncode != 0:
            continue
        output = (result.stdout + "\n" + result.stderr).strip()
        match = re.search(
            r"\b(?:Google Chrome|Chromium|Microsoft Edge)\s+(\d+(?:\.\d+)+)",
            output,
            re.IGNORECASE,
        )
        if match:
            return Detection(True, match.group(1), resolved, provider)
    return Detection(False)


def detect_fonts(
    which: Callable[[str], Optional[str]] = shutil.which,
    trust_executable: Callable[[str], Optional[str]] = resolve_trusted_executable,
    font_roots: Optional[Sequence[Path]] = None,
) -> Detection:
    executable = which("fc-match")
    if executable:
        trusted = trust_executable(executable)
        if trusted is not None:
            result = capture_command((trusted, "--format=%{family}\n%{file}\n", "Liberation Sans"))
            if result is not None and result.returncode == 0:
                lines = result.stdout.splitlines()
                if lines and "Liberation Sans" in lines[0]:
                    font_path = lines[1].strip() if len(lines) > 1 and lines[1].strip() else None
                    return Detection(True, None, font_path)

    # Minimal distribution images may install the font package without the
    # optional fontconfig CLI.  Validate the actual regular face in trusted
    # system font roots so --no-install-recommends remains usable.
    roots = tuple(font_roots or (Path("/usr/share/fonts"), Path("/usr/local/share/fonts")))
    expected_names = {"liberationsans-regular.ttf", "liberationsans-regular.otf"}
    for root in roots:
        try:
            resolved_root = root.resolve(strict=True)
        except OSError:
            continue
        if not resolved_root.is_dir():
            continue
        try:
            candidates = resolved_root.rglob("*")
            for candidate in candidates:
                if candidate.name.casefold() not in expected_names or candidate.is_symlink():
                    continue
                try:
                    resolved = candidate.resolve(strict=True)
                    resolved.relative_to(resolved_root)
                    if not resolved.is_file() or resolved.stat().st_size < 1024:
                        continue
                    with resolved.open("rb") as stream:
                        signature = stream.read(4)
                    if signature not in (b"\x00\x01\x00\x00", b"OTTO", b"true", b"typ1"):
                        continue
                except (OSError, ValueError):
                    continue
                return Detection(True, None, str(resolved))
        except OSError:
            continue
    return Detection(False)


def detect_shellcheck(
    which: Callable[[str], Optional[str]] = shutil.which,
    trust_executable: Callable[[str], Optional[str]] = resolve_trusted_executable,
) -> Detection:
    executable = which("shellcheck")
    if not executable:
        return Detection(False)
    trusted = trust_executable(executable)
    if trusted is None:
        return Detection(False)
    executable = trusted
    result = capture_command((executable, "--version"))
    if result is None or result.returncode != 0:
        return Detection(False)
    match = re.search(r"(?im)^version:\s*([^\s]+)\s*$", result.stdout)
    if match is None or re.fullmatch(r"\d+(?:\.\d+){1,2}", match.group(1)) is None:
        return Detection(False)
    try:
        resolved = str(Path(executable).resolve(strict=True))
    except OSError:
        resolved = executable
    return Detection(True, match.group(1), resolved)


def collect_detections(catalog: Mapping[str, Any]) -> Mapping[str, Detection]:
    minimum = minimum_version_tuple(str(catalog["minimumPythonVersion"]))
    return {
        "coreRuntime": detect_python(minimum),
        "browser": detect_browser(),
        "fonts": detect_fonts(),
        "shellcheck": detect_shellcheck(),
    }


def distribution_block_reason(
    context: PlatformContext, component_name: str, detection: Detection
) -> Optional[str]:
    if detection.present:
        return None
    if component_name == "browser" and context.manager == "apt" and context.distro_id == "ubuntu":
        return (
            "Ubuntu stellt Chromium über APT nur als Snap-Transition bereit; "
            "Snap wird nicht automatisch installiert."
        )
    if (
        component_name in ("browser", "shellcheck")
        and context.manager in ("dnf", "yum")
        and context.distro_id in ("rhel", "rocky", "almalinux", "centos")
    ):
        return (
            "Die RHEL-kompatiblen Basis-Paketquellen stellen diese Komponente nicht bereit; "
            "EPEL oder andere Communityquellen werden nicht automatisch registriert."
        )
    return None


def manual_action(context: PlatformContext, component_name: str, reason: str) -> Dict[str, Any]:
    if component_name == "browser":
        return {
            "component": component_name,
            "action": "provide-native-package",
            "reason": reason,
            "requirement": (
                "Ein Administrator muss einen nativen x86_64-Chrome-, Chromium- oder Edge-Browser "
                "aus einer nach der lokalen Distributionsrichtlinie freigegebenen Systemquelle bereitstellen; "
                "Snap und automatisch registrierte Fremd-/Communityquellen bleiben ausgeschlossen."
            ),
            "verificationCommand": "python3 Tools/bewerbung.py diagnose --browser-erforderlich --als-json",
        }
    if component_name == "shellcheck":
        return {
            "component": component_name,
            "action": "provide-native-package",
            "reason": reason,
            "requirement": "ShellCheck muss aus einer vom Administrator freigegebenen Systemquelle bereitgestellt werden.",
            "verificationCommand": "shellcheck --version",
        }
    return {
        "component": component_name,
        "action": "provide-native-package",
        "reason": reason,
        "requirement": "Die Komponente muss aus einer freigegebenen Distributionsquelle bereitgestellt werden.",
        "verificationCommand": "python3 Tools/setup-linux.py --all --dry-run --format json",
    }


def apply_command(options: Options) -> str:
    args = ["python3", "Tools/setup-linux.py"]
    if options.runtime:
        args.append("--runtime")
    if options.browser:
        args.extend(("--browser", "chromium"))
    if options.fonts:
        args.append("--fonts")
    if options.shellcheck:
        args.append("--shellcheck")
    args.append("--yes")
    if options.output_format == "json":
        args.extend(("--format", "json"))
    return shlex.join(args)


def build_report(
    options: Options,
    context: PlatformContext,
    catalog: Mapping[str, Any],
    detections: Optional[Mapping[str, Detection]] = None,
) -> Dict[str, Any]:
    actual = detections if detections is not None else collect_detections(catalog)
    manager_components = catalog["packageManagers"][context.manager]["components"]
    component_reports: Dict[str, Dict[str, Any]] = {}
    planned_changes: List[Dict[str, Any]] = []
    manual_actions: List[Dict[str, Any]] = []

    for name in COMPONENT_NAMES:
        selected = bool(options.selected[name])
        detection = actual[name]
        definition = manager_components[name]
        block_reason = distribution_block_reason(context, name, detection)
        blocked = block_reason is not None
        if not selected or detection.present:
            planned_action = "none"
        elif blocked:
            planned_action = "manual"
        else:
            planned_action = "install"
        component: Dict[str, Any] = {
            "selected": selected,
            "status": "present" if detection.present else "missing",
            "version": detection.version,
            "path": detection.path,
            "packages": list(definition["packages"]),
            "source": definition["source"],
            "permission": "root-or-sudo",
            "installable": not blocked,
            "blocked": blocked,
            "plannedAction": planned_action,
        }
        if name == "coreRuntime":
            component["platform"] = "linux"
            component["language"] = "python"
            component["minimumVersion"] = catalog["minimumPythonVersion"]
            component["setupCommand"] = "python3 Tools/setup-linux.py --runtime --dry-run --format json"
        if name == "browser" and detection.provider:
            component["detectedAs"] = detection.provider
        if blocked:
            component["reason"] = block_reason
        component_reports[name] = component
        if selected and planned_action == "install":
            first_pacman_change = context.manager == "pacman" and not planned_changes
            planned_changes.append(
                {
                    "component": name,
                    "action": "install",
                    "packages": list(definition["packages"]),
                    "source": definition["source"],
                    "permission": "root-or-sudo",
                    "includesFullSystemUpgrade": first_pacman_change,
                }
            )
        elif selected and planned_action == "manual":
            action = manual_action(context, name, str(component["reason"]))
            component["manualInstruction"] = action
            manual_actions.append(action)

    return {
        "schemaVersion": 2,
        "kind": "linux_setup_plan",
        "status": "planned" if planned_changes or manual_actions else "ready",
        "platform": {
            "id": context.distro_id,
            "version": context.distro_version,
            "architecture": context.architecture,
        },
        "packageManager": context.manager,
        "packageManagerPath": context.manager_executable,
        "coreRuntime": component_reports["coreRuntime"],
        "dependencies": {
            "browser": component_reports["browser"],
            "fonts": component_reports["fonts"],
            "shellcheck": component_reports["shellcheck"],
        },
        "plannedChanges": planned_changes,
        "manualActions": manual_actions,
        "changesRequired": bool(planned_changes),
        "manualActionRequired": bool(manual_actions),
        "requiresPrivilege": bool(planned_changes),
        "packageManagerOperation": {
            "refreshMetadata": bool(planned_changes and context.manager in ("apt", "pacman")),
            "fullSystemUpgrade": bool(planned_changes and context.manager == "pacman"),
            "detail": (
                "Der erste Pacman-Lauf synchronisiert Paketdaten und aktualisiert das vollständige System (-Syu), bevor die deklarierten Pakete installiert werden."
                if planned_changes and context.manager == "pacman"
                else "Es werden nur die aufgeführten Distributionspakete installiert."
            ),
        },
        "applyCommand": apply_command(options) if planned_changes else None,
        "dryRun": options.dry_run,
    }


def all_components(report: Mapping[str, Any]) -> Iterable[Tuple[str, Mapping[str, Any]]]:
    yield "coreRuntime", report["coreRuntime"]
    for name in ("browser", "fonts", "shellcheck"):
        yield name, report["dependencies"][name]


def emit_json(report: Mapping[str, Any]) -> None:
    print(json.dumps(report, ensure_ascii=False, separators=(",", ":"), sort_keys=False))


def emit_text(report: Mapping[str, Any], heading: str = "Geplante Projektabhängigkeiten:") -> None:
    platform_data = report["platform"]
    print(heading)
    print(
        "  Plattform: {0} {1} ({2})".format(
            platform_data["id"], platform_data["version"], platform_data["architecture"]
        )
    )
    print("  Paketmanager: {0} ({1})".format(report["packageManager"], report["packageManagerPath"]))
    for name, component in all_components(report):
        if not component["selected"]:
            continue
        detail = "{0}: {1} | Paket={2} | Quelle={3} | Rechte={4} | Änderung={5}".format(
            COMPONENT_LABELS[name],
            component["status"],
            ",".join(component["packages"]),
            component["source"],
            component["permission"],
            component["plannedAction"],
        )
        print("  " + detail)
        if component.get("path"):
            print("    validiert: {0} {1} ({2})".format(COMPONENT_LABELS[name], component.get("version") or "", component["path"]))
        if component.get("reason"):
            print("    Blockade: " + str(component["reason"]))
        instruction = component.get("manualInstruction")
        if isinstance(instruction, dict):
            print("    Manuelle Voraussetzung: " + str(instruction.get("requirement")))
            print("    Prüfung: " + str(instruction.get("verificationCommand")))
    operation = report.get("packageManagerOperation")
    if isinstance(operation, dict) and operation.get("fullSystemUpgrade"):
        print("  Pacman-Systemaktualisierung: " + str(operation.get("detail")))
    if report.get("applyCommand"):
        print("  Sicherer Setup-Befehl: " + str(report["applyCommand"]))


class CommandRunner:
    def run(self, args: Sequence[str]) -> None:
        try:
            result = subprocess.run(
                list(args),
                check=False,
                stdout=sys.stderr,
                stderr=sys.stderr,
            )
        except OSError as exc:
            raise CommandError("Paketbefehl konnte nicht gestartet werden: {0}".format(exc)) from exc
        if result.returncode != 0:
            raise CommandError(
                "Paketbefehl ist mit Exitcode {0} fehlgeschlagen: {1}".format(
                    result.returncode, shlex.join(list(args))
                )
            )


class PrivilegeExecutor:
    def __init__(
        self,
        runner: CommandRunner,
        effective_uid: Optional[int] = None,
        which: Callable[[str], Optional[str]] = shutil.which,
        trust_executable: Callable[[str], Optional[str]] = resolve_trusted_executable,
    ) -> None:
        self.runner = runner
        self.effective_uid = os.geteuid() if effective_uid is None else effective_uid
        sudo_candidate = None if self.effective_uid == 0 else which("sudo")
        self.sudo_path = trust_executable(sudo_candidate) if sudo_candidate else None

    def run(self, args: Sequence[str]) -> None:
        if self.effective_uid == 0:
            command = list(args)
        elif self.sudo_path:
            command = [self.sudo_path, "--"] + list(args)
        else:
            raise SetupError("Für Systemänderungen sind Root-Rechte oder sudo erforderlich.")
        self.runner.run(command)


class PackageInstaller:
    def __init__(self, context: PlatformContext, privilege: PrivilegeExecutor) -> None:
        self.context = context
        self.privilege = privilege
        self.metadata_refreshed = False

    def install(self, packages: Sequence[str]) -> None:
        if not packages or not all(PACKAGE_RE.fullmatch(package) is not None for package in packages):
            raise SetupError("Unsichere oder leere Paketliste wurde abgelehnt.", EXIT_USAGE_OR_PLATFORM)
        executable = self.context.manager_executable
        manager = self.context.manager
        if manager == "apt":
            if not self.metadata_refreshed:
                self.privilege.run((executable, "update"))
                self.metadata_refreshed = True
            self.privilege.run((executable, "install", "--yes", "--no-install-recommends", *packages))
        elif manager in ("dnf", "yum"):
            self.privilege.run((executable, "install", "-y", *packages))
        elif manager == "pacman":
            synchronize = "-Syu" if not self.metadata_refreshed else "-S"
            self.privilege.run((executable, synchronize, "--noconfirm", "--needed", *packages))
            self.metadata_refreshed = True
        elif manager == "zypper":
            self.privilege.run((executable, "--non-interactive", "install", "--no-recommends", *packages))
        else:
            raise SetupError("Nicht unterstützter Paketmanager: " + manager, EXIT_USAGE_OR_PLATFORM)


def parse_args(argv: Sequence[str]) -> Tuple[argparse.ArgumentParser, Options]:
    parser = argparse.ArgumentParser(
        prog="setup-linux.py",
        description="Deklarierte Apply-Foundry-Abhängigkeiten unter Linux planen oder installieren.",
    )
    parser.add_argument("--runtime", action="store_true", help="System-Python 3.9 oder neuer")
    parser.add_argument("--browser", choices=("chromium",), help="Chromium aus der Distribution")
    parser.add_argument("--fonts", action="store_true", help="Liberation Sans aus der Distribution")
    parser.add_argument("--shellcheck", action="store_true", help="ShellCheck aus der Distribution")
    parser.add_argument("--all", action="store_true", dest="select_all", help="alle deklarierten Komponenten")
    parser.add_argument("--dry-run", action="store_true", help="nur den Installationsplan ausgeben")
    parser.add_argument("--yes", action="store_true", dest="assume_yes", help="angezeigten Plan bestätigen")
    parser.add_argument("--format", choices=("text", "json"), default="text", dest="output_format")
    namespace = parser.parse_args(list(argv))
    select_all = bool(namespace.select_all)
    options = Options(
        runtime=bool(namespace.runtime or select_all),
        browser=bool(namespace.browser == "chromium" or select_all),
        fonts=bool(namespace.fonts or select_all),
        shellcheck=bool(namespace.shellcheck or select_all),
        dry_run=bool(namespace.dry_run),
        assume_yes=bool(namespace.assume_yes),
        output_format=str(namespace.output_format),
    )
    return parser, options


def confirm_installation(stdin: Any = sys.stdin, stdout: Any = sys.stdout) -> bool:
    if not stdin.isatty():
        raise SetupError(
            "Keine interaktive Eingabe verfügbar; nach Prüfung mit --yes erneut starten.",
            EXIT_USAGE_OR_PLATFORM,
        )
    print("Diese Änderungen jetzt ausführen? [j/N] ", end="", file=stdout, flush=True)
    answer = stdin.readline().strip().lower()
    return answer in ("j", "ja", "y", "yes")


def emit(report: Mapping[str, Any], output_format: str, heading: str = "Geplante Projektabhängigkeiten:") -> None:
    if output_format == "json":
        emit_json(report)
    else:
        emit_text(report, heading)


def run_setup(options: Options, context: PlatformContext, catalog: Mapping[str, Any]) -> int:
    initial = build_report(options, context, catalog)
    if options.dry_run:
        emit(initial, options.output_format)
        if options.output_format == "text":
            print("Dry-run abgeschlossen; es wurde nichts verändert.")
        return EXIT_OK

    if options.output_format == "text":
        emit_text(initial)

    requested_changes = list(initial["plannedChanges"])
    if requested_changes and not options.assume_yes:
        try:
            confirmed = confirm_installation()
        except SetupError as exc:
            initial["status"] = "confirmation_required"
            initial["error"] = str(exc)
            if options.output_format == "json":
                emit_json(initial)
            print("FEHLER: " + str(exc), file=sys.stderr)
            return exc.exit_code
        if not confirmed:
            initial["status"] = "cancelled"
            if options.output_format == "json":
                emit_json(initial)
            print("Setup wurde ohne Änderungen abgebrochen.", file=sys.stderr)
            return EXIT_RUNTIME_ERROR

    applied_changes: List[Dict[str, Any]] = []
    if requested_changes:
        installer = PackageInstaller(context, PrivilegeExecutor(CommandRunner()))
        for change in requested_changes:
            try:
                installer.install(change["packages"])
                refreshed = collect_detections(catalog)[change["component"]]
                if not refreshed.present:
                    raise SetupError(
                        "{0} konnte nach der Paketinstallation nicht validiert werden.".format(
                            COMPONENT_LABELS[change["component"]]
                        )
                    )
                applied_changes.append(change)
            except SetupError as exc:
                failed = build_report(options, context, catalog)
                failed["status"] = "failed"
                failed["error"] = str(exc)
                failed["failedComponent"] = change["component"]
                failed["requestedChanges"] = requested_changes
                failed["appliedChanges"] = applied_changes
                emit(failed, options.output_format, "Erreichter Teilzustand:")
                print("FEHLER: " + str(exc), file=sys.stderr)
                return exc.exit_code

    final = build_report(options, context, catalog)
    final["requestedChanges"] = requested_changes
    final["appliedChanges"] = applied_changes
    if final["manualActionRequired"]:
        final["status"] = "partial" if applied_changes else "blocked"
        emit(final, options.output_format, "Erreichter Teilzustand:")
        manual_components = ", ".join(
            COMPONENT_LABELS.get(str(item.get("component")), str(item.get("component")))
            for item in final["manualActions"]
        )
        print(
            "Manuelle Bereitstellung bleibt erforderlich für: {0}. "
            "Es wurden keine Snap-, AUR-, EPEL- oder anderen Communityquellen registriert.".format(
                manual_components
            ),
            file=sys.stderr,
        )
        return EXIT_USAGE_OR_PLATFORM
    final["status"] = "success" if applied_changes else "ready"
    emit(final, options.output_format, "Linux-Setup erfolgreich abgeschlossen:")
    if options.output_format == "text":
        if applied_changes:
            print("Linux-Setup erfolgreich abgeschlossen.")
        else:
            print("Alle ausgewählten Komponenten sind bereits passend installiert.")
    return EXIT_OK


def main(argv: Optional[Sequence[str]] = None) -> int:
    if sys.version_info < (3, 9):
        print(
            "FEHLER: System-Python 3.9 oder neuer ist erforderlich. "
            "Starte Tools/setup-linux.sh --runtime --dry-run.",
            file=sys.stderr,
        )
        return EXIT_USAGE_OR_PLATFORM
    parser, options = parse_args(sys.argv[1:] if argv is None else argv)
    if not any(options.selected.values()):
        parser.print_help()
        return EXIT_OK
    if not sys.platform.startswith("linux"):
        print("FEHLER: setup-linux.py unterstützt ausschließlich Linux.", file=sys.stderr)
        return EXIT_USAGE_OR_PLATFORM
    try:
        catalog = load_catalog()
        context = build_context(catalog)
        return run_setup(options, context, catalog)
    except SetupError as exc:
        print("FEHLER: " + str(exc), file=sys.stderr)
        return exc.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
