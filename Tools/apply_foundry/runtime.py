"""Read-only runtime and dependency detection for supported desktop platforms."""

import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

from .io import utc_now


def os_release() -> Dict[str, str]:
    result: Dict[str, str] = {}
    path = Path("/etc/os-release")
    if path.is_file():
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" not in line or line.lstrip().startswith("#"):
                continue
            key, value = line.split("=", 1)
            result[key] = value.strip().strip('"').strip("'")
    return result


def package_manager() -> Optional[str]:
    if sys.platform == "win32":
        return "winget" if shutil.which("winget") else None
    if sys.platform == "darwin":
        return "brew" if shutil.which("brew") else None
    for executable, name in (("apt-get", "apt"), ("dnf", "dnf"), ("yum", "yum"), ("pacman", "pacman"), ("zypper", "zypper")):
        if shutil.which(executable):
            return name
    return None


def _version_output(executable: str, argument: str = "--version") -> Optional[str]:
    try:
        result = subprocess.run([executable, argument], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=8, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    text = re.sub(r"[\r\n]+", " ", result.stdout + " " + result.stderr).strip()
    return text if result.returncode == 0 and text else None


def _version(executable: str, argument: str = "--version") -> Optional[str]:
    text = _version_output(executable, argument)
    if text is None:
        return None
    match = re.search(r"(?<!\d)v?(\d+(?:\.\d+){1,3})(?!\d)", text)
    return match.group(1) if match else None


def _browser_identity(executable: str) -> Optional[Tuple[str, str, str]]:
    """Return the browser name, engine and version proven by ``--version``."""

    text = _version_output(executable)
    if text is None:
        return None
    lowered = text.lower()
    if "microsoft edge" in lowered or "msedge" in lowered:
        name = "edge"
    elif "chromium" in lowered:
        name = "chromium"
    elif "google chrome" in lowered or "google-chrome" in lowered:
        name = "chrome"
    elif "firefox" in lowered:
        name = "firefox"
    else:
        return None
    match = re.search(r"(?<!\d)(\d+(?:\.\d+){1,3})(?!\d)", text)
    if not match:
        return None
    return name, "gecko" if name == "firefox" else "chromium", match.group(1)


def _snap_launcher(path: Path) -> bool:
    if not sys.platform.startswith("linux"):
        return False
    try:
        resolved = path.resolve(strict=True)
        if str(resolved) == "/usr/bin/snap" or str(resolved).startswith("/snap/"):
            return True
        if resolved.stat().st_size > 131072:
            return False
        prefix = resolved.read_bytes()[:131072]
        return prefix.startswith(b"#!") and re.search(rb"(?im)(?:^|[\s/])snap(?:\s+run)?\s+", prefix) is not None
    except OSError:
        return True


def executable_details(names) -> Dict[str, Any]:
    for name in names:
        found = shutil.which(name)
        if found:
            path = str(Path(found).resolve())
            version = _version(path)
            return {"available": version is not None, "version": version, "path": path}
    return {"available": False, "version": None, "path": None}


def browser_details(requested: str = "auto", executable_path: Optional[Path] = None) -> Dict[str, Any]:
    candidates = []
    if executable_path is not None:
        candidates.append((requested, str(executable_path)))
    else:
        table = {
            "chrome": ("google-chrome", "google-chrome-stable", "chrome", "chrome.exe"),
            "chromium": ("chromium", "chromium-browser", "chromium.exe"),
            "edge": ("microsoft-edge", "microsoft-edge-stable", "msedge", "msedge.exe"),
            "firefox": ("firefox", "firefox.exe"),
        }
        names = ("chrome", "chromium", "edge") if requested == "auto" else (requested,)
        for browser_name in names:
            for executable in table.get(browser_name, ()):
                found = shutil.which(executable)
                if found:
                    candidates.append((browser_name, found))
    for requested_name, raw_path in candidates:
        try:
            resolved_path = Path(raw_path).resolve(strict=True)
            path = str(resolved_path)
        except (OSError, RuntimeError):
            continue
        # Snap packages are intentionally outside the supported dependency
        # contract; a distro-owned Chromium is required.
        if path.startswith("/snap/") or "/snap/" in path or _snap_launcher(resolved_path):
            continue
        identity = _browser_identity(path)
        if identity:
            name, engine, version = identity
            if requested_name != "auto" and name != requested_name:
                continue
            return {"available": True, "name": name, "engine": engine, "version": version, "path": path}
    return {"available": False, "name": None, "engine": None, "version": None, "path": None}


def font_details() -> Dict[str, Any]:
    if sys.platform == "win32":
        fonts = Path(os.environ.get("WINDIR", r"C:\\Windows")) / "Fonts"
        arial = fonts / "arial.ttf"
        return {"available": arial.is_file(), "font": "Arial", "path": str(arial) if arial.is_file() else None, "version": None}
    if sys.platform == "darwin":
        for path in (Path("/System/Library/Fonts/Supplemental/Arial.ttf"), Path("/Library/Fonts/Arial.ttf")):
            if path.is_file():
                return {"available": True, "font": "Arial", "path": str(path), "version": None}
    paths = (
        Path("/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"),
        Path("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"),
    )
    for path in paths:
        if path.is_file():
            return {"available": True, "font": "Liberation Sans", "path": str(path), "version": None}
    fc_match = shutil.which("fc-match")
    if fc_match:
        try:
            family = subprocess.run([fc_match, "--format=%{family}", "Liberation Sans"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=8, check=False)
            file_probe = subprocess.run([fc_match, "--format=%{file}", "Liberation Sans"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=8, check=False)
            if family.returncode == 0 and re.search(r"(?:^|,)Liberation Sans(?:$|,)", family.stdout, re.I):
                return {"available": True, "font": "Liberation Sans", "path": file_probe.stdout.strip() or None, "version": None}
        except (OSError, subprocess.TimeoutExpired):
            pass
    return {"available": False, "font": "Liberation Sans", "path": None, "version": None}


def runtime_fingerprint(browser: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    release = os_release()
    platform_id = "windows" if sys.platform == "win32" else "macos" if sys.platform == "darwin" else "linux"
    result: Dict[str, Any] = {
        "schemaVersion": 2,
        "os": platform_id,
        "architecture": platform.machine().lower(),
        "distributionId": release.get("ID", "") if platform_id == "linux" else platform_id,
        "distributionVersion": release.get("VERSION_ID", "") if platform_id == "linux" else platform.version(),
        "wsl": bool(os.environ.get("WSL_DISTRO_NAME")),
        "coreRuntime": {
            "platform": platform_id,
            "language": "python",
            "kind": "python",
            "version": platform.python_version(),
            "minimumVersion": "3.11",
            "path": str(Path(sys.executable).resolve()),
            # Kept for readers of the existing technical fingerprint contract.
            "executable": str(Path(sys.executable).resolve()),
        },
    }
    if browser and browser.get("available"):
        result["browser"] = {
            "name": browser.get("name"),
            "engine": browser.get("engine"),
            "version": browser.get("version"),
            "path": browser.get("path"),
            "executable": browser.get("path"),
        }
    return result


def diagnose(browser: str = "auto", executable_path: Optional[Path] = None, browser_required: bool = False) -> Dict[str, Any]:
    release = os_release()
    architecture = platform.machine().lower()
    manager = package_manager()
    platform_id = "windows" if sys.platform == "win32" else "macos" if sys.platform == "darwin" else "linux" if sys.platform.startswith("linux") else sys.platform
    supported_arch = architecture in ("x86_64", "amd64", "arm64", "aarch64")
    supported_os = platform_id in ("windows", "linux", "macos")
    supported = supported_os and supported_arch and manager is not None
    checks = []
    exit_code = 0

    def add(name: str, status: str, required: bool, detail: str, failure_code: int = 1) -> None:
        nonlocal exit_code
        checks.append({"name": name, "status": status, "required": required, "detail": detail})
        if status == "error" and required:
            exit_code = max(exit_code, failure_code)

    python_ok = sys.version_info >= (3, 11)
    add("core_runtime", "ok" if python_ok else "error", True, "Python %s; erforderlich: 3.11 oder neuer (%s)." % (platform.python_version(), sys.executable), 2)
    add("plattform", "ok" if supported_os and supported_arch else "error", True, "%s; Architektur %s." % (platform_id, architecture), 2)
    add("paketmanager", "ok" if manager else "error", True, "Erkannt: %s." % manager if manager else "Kein unterstützter Paketmanager/Homebrew erkannt.", 2)
    try:
        probe = Path(tempfile.gettempdir()) / (".apply-foundry-probe-" + uuid.uuid4().hex)
        probe.write_bytes(b"*")
        probe.unlink()
        add("temp_schreibzugriff", "ok", True, "Temporärer Schreib-/Löschtest bestanden: %s" % tempfile.gettempdir())
    except OSError as exc:
        add("temp_schreibzugriff", "error", True, str(exc))
    font = font_details()
    add("schriftart", "ok" if font["available"] else "error", True, "%s gefunden: %s" % (font.get("font"), font.get("path")) if font["available"] else "Erforderliche Schriftart wurde nicht gefunden.")
    shellcheck = executable_details(("shellcheck",))
    add("shellcheck", "ok" if shellcheck["available"] else "warning", False, "ShellCheck %s (%s)" % (shellcheck.get("version"), shellcheck.get("path")) if shellcheck["available"] else "ShellCheck fehlt; vollständige Bash-/CI-Prüfung ist nicht verfügbar.")
    explicit_browser = browser_required or browser != "auto" or executable_path is not None
    browser_info = browser_details(browser, executable_path)
    add("browser", "ok" if browser_info["available"] else ("error" if explicit_browser else "warning"), explicit_browser, "%s %s (%s)" % (browser_info.get("name"), browser_info.get("version"), browser_info.get("path")) if browser_info["available"] else "Kein unterstützter distributionsbasierter Chromium-Browser gefunden.")
    setup = "python3 Tools/setup.py"
    core = {
        "platform": platform_id, "name": "python", "language": "python", "status": "present" if python_ok else "missing",
        "version": platform.python_version(), "minimumVersion": "3.11", "path": str(Path(sys.executable).resolve()),
        "source": "System-Python", "installable": supported,
        "setupCommand": setup + " --runtime --dry-run --format json", "permission": "Administrationsrechte falls Installation nötig",
    }
    browser_present = bool(browser_info["available"] and browser_info.get("engine") == "chromium")
    browser_source = (
        "Vorhandener versionsgeprüfter Systembrowser (%s)" % browser_info.get("name")
        if browser_present else "Chromium/Chrome aus dem deklarierten Paketweg"
    )
    dependencies = [
        core,
        {"name": "browser", "requested": "chromium", "detectedAs": browser_info.get("name"), "status": "present" if browser_present else "missing", "version": browser_info.get("version"), "path": browser_info.get("path"), "source": browser_source, "installable": supported, "setupCommand": setup + " --browser chromium --dry-run --format json", "permission": "Administrationsrechte falls Installation nötig"},
        {"name": "fonts", "status": "present" if font["available"] else "missing", "version": None, "path": font.get("path"), "source": "%s-Systemschrift" % font.get("font"), "installable": supported, "setupCommand": setup + " --fonts --dry-run --format json", "permission": "Administrationsrechte falls Installation nötig"},
        {"name": "shellcheck", "status": "present" if shellcheck["available"] else "missing", "version": shellcheck.get("version"), "path": shellcheck.get("path"), "source": "ShellCheck aus dem deklarierten Paketweg", "installable": supported, "setupCommand": setup + " --shellcheck --dry-run --format json", "permission": "Administrationsrechte falls Installation nötig"},
    ]
    status = "nicht_unterstuetzt" if exit_code == 2 else "nicht_bereit" if exit_code == 1 else "bereit_mit_warnungen" if any(item["status"] == "warning" for item in checks) else "bereit"
    return {
        "schemaVersion": 4, "checkedAtUtc": utc_now(), "status": status, "exitCode": exit_code,
        "checks": checks,
        "platform": {"name": platform_id, "distributionId": release.get("ID", "") if platform_id == "linux" else platform_id, "distributionVersion": release.get("VERSION_ID", "") if platform_id == "linux" else platform.version(), "architecture": architecture, "packageManager": manager},
        "coreRuntime": core,
        "setup": {"command": setup + " --all --dry-run --format json"},
        "dependencies": dependencies,
        "runtimeFingerprint": runtime_fingerprint(browser_info),
    }


__all__ = ["browser_details", "diagnose", "font_details", "os_release", "package_manager", "runtime_fingerprint"]
