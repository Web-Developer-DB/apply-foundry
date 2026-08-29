"""Browser, PNG and PDF primitives for the native Python workflow.

Only the Python standard library is used.  The module deliberately mirrors the
PowerShell contracts: native programs receive an argument vector, every run is
bounded, and a timeout terminates the whole process group.
"""

from __future__ import annotations

import base64
import binascii
from collections import Counter
from html.parser import HTMLParser
import json
import os
import platform
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple
from urllib.parse import urlsplit


class BrowserError(RuntimeError):
    """Controlled browser or render failure."""


class _CandidateLinkParser(HTMLParser):
    """Collect candidate anchors while keeping the HTML contract dependency-free."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: List[Dict[str, str]] = []
        self.errors: List[str] = []
        self._current: Optional[Dict[str, Any]] = None

    def handle_starttag(self, tag: str, attrs: List[Tuple[str, Optional[str]]]) -> None:
        values = {key.lower(): value or "" for key, value in attrs}
        lowered = tag.lower()
        if lowered == "a":
            if self._current is not None:
                self.errors.append("Verschachtelte <a>-Elemente sind nicht zulässig.")
            self._current = {"href": values.get("href", ""), "text": []}
        elif "href" in values:
            self.errors.append(f"Nur <a>-Elemente dürfen ein href-Attribut besitzen ({lowered}).")
        if "src" in values:
            source = values["src"].strip()
            if not source.startswith("data:"):
                self.errors.append(f"{lowered} lädt über src eine externe oder lokale Ressource.")

    def handle_startendtag(self, tag: str, attrs: List[Tuple[str, Optional[str]]]) -> None:
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_data(self, data: str) -> None:
        if self._current is not None:
            self._current["text"].append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() != "a":
            return
        if self._current is None:
            self.errors.append("Schließendes </a> ohne öffnendes <a>-Element.")
            return
        href = str(self._current["href"]).strip()
        visible = " ".join("".join(self._current["text"]).split())
        if not href:
            self.errors.append("<a>-Element benötigt ein href-Attribut.")
        else:
            self.links.append({"target": href, "visibleText": visible})
        self._current = None

    def close(self) -> None:
        super().close()
        if self._current is not None:
            self.errors.append("Nicht geschlossenes <a>-Element.")
            self._current = None


def candidate_link_contract(source: str) -> Tuple[List[str], List[str]]:
    """Return permitted PDF link targets and static-contract errors for candidate HTML."""

    parser = _CandidateLinkParser()
    try:
        parser.feed(source)
        parser.close()
    except Exception as exc:  # HTMLParser must never turn malformed candidate HTML into a crash.
        return [], [f"HTML-Linkprüfung konnte nicht ausgeführt werden: {exc}"]
    errors = list(parser.errors)
    targets: List[str] = []
    for link in parser.links:
        target = link["target"]
        visible = link["visibleText"]
        lowered = target.lower()
        if lowered.startswith("https://"):
            parsed = urlsplit(target)
            if not parsed.netloc or parsed.username or parsed.password or parsed.fragment or any(char.isspace() for char in target):
                errors.append(f"HTTPS-Link ist ungültig oder nicht druckstabil: {target}")
                continue
            if visible != target:
                errors.append(f"HTTPS-Link muss als vollständige sichtbare URL erscheinen: {target}")
                continue
        elif lowered.startswith("mailto:"):
            address = target[7:]
            if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", address) or visible.casefold() != address.casefold():
                errors.append(f"mailto-Link muss exakt die sichtbare E-Mail-Adresse enthalten: {target}")
                continue
        else:
            errors.append(f"Nur https://- und mailto:-Links sind in Bewerbungs-HTML zulässig: {target}")
            continue
        targets.append(target)
    forbidden = re.search(r"(?is)<script\b|@import\b|<link\b|\b(?:src|href)\s*=\s*['\"](?:file:|//|javascript:)", source)
    if forbidden:
        errors.append("HTML lädt Skripte oder externe/lokale Ressourcen.")
    for reference in re.findall(r"(?is)url\(\s*(['\"]?)(.*?)\1\s*\)", source):
        value = reference[1].strip()
        if value and not value.startswith("data:"):
            errors.append(f"CSS darf keine externe oder lokale Ressource über url() laden: {value}")
    return targets, list(dict.fromkeys(errors))


@dataclass(frozen=True)
class BrowserInfo:
    name: str
    engine: str
    path: Path
    version: str
    version_text: str


@dataclass(frozen=True)
class ProcessResult:
    exit_code: int
    stdout: str
    stderr: str
    timed_out: bool = False
    stdout_truncated: bool = False
    stderr_truncated: bool = False


def utc_now() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def os_release() -> Dict[str, str]:
    result: Dict[str, str] = {}
    path = Path("/etc/os-release")
    if not path.is_file():
        return result
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"^([A-Z][A-Z0-9_]*)=(.*)$", line)
        if not match:
            continue
        value = match.group(2).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        result[match.group(1)] = value.replace(r"\"", '"').replace(r"\\", "\\")
    return result


def package_manager() -> Optional[str]:
    if sys.platform == "win32":
        return "winget" if shutil.which("winget") else None
    if sys.platform == "darwin":
        return "brew" if shutil.which("brew") else None
    for command, label in (("apt-get", "apt"), ("dnf", "dnf"), ("yum", "yum"), ("pacman", "pacman"), ("zypper", "zypper")):
        if shutil.which(command):
            return label
    return None


def runtime_fingerprint(browser: Optional[BrowserInfo] = None) -> Dict[str, Any]:
    release = os_release()
    os_id = "windows" if sys.platform == "win32" else "macos" if sys.platform == "darwin" else "linux"
    browser_value: Optional[Dict[str, str]] = None
    if browser is not None:
        browser_value = {
            "name": browser.name,
            "version": browser.version,
            "executable": str(browser.path.resolve()),
        }
    is_wsl = bool(os.environ.get("WSL_DISTRO_NAME"))
    if not is_wsl:
        try:
            is_wsl = bool(re.search(r"microsoft|wsl", Path("/proc/sys/kernel/osrelease").read_text(encoding="utf-8"), re.I))
        except OSError:
            pass
    return {
        "schemaVersion": 1,
        "os": os_id,
        "osDescription": platform.platform(),
        "distributionId": release.get("ID") if os_id == "linux" else os_id,
        "distributionVersion": release.get("VERSION_ID") if os_id == "linux" else platform.version(),
        "packageManager": package_manager(),
        "wsl": is_wsl,
        "architecture": "x64" if platform.machine().lower() in {"x86_64", "amd64"} else "arm64" if platform.machine().lower() in {"arm64", "aarch64"} else platform.machine().lower(),
        # Legacy keys remain readable for reports created by the PowerShell engine.
        "powerShellVersion": None,
        "psEdition": None,
        "pythonVersion": platform.python_version(),
        "coreRuntime": {
            "platform": os_id,
            "language": "python",
            "kind": "python",
            "version": platform.python_version(),
            "minimumVersion": "3.11",
            "path": str(Path(sys.executable).resolve()),
            "executable": str(Path(sys.executable).resolve()),
        },
        "browser": browser_value,
    }


def run_process(
    executable: Path,
    arguments: Sequence[str],
    timeout_seconds: int,
    max_stdout: int = 65536,
    max_stderr: int = 65536,
    cwd: Optional[Path] = None,
) -> ProcessResult:
    startup: Dict[str, Any] = {}
    if os.name == "nt":
        startup["creationflags"] = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    else:
        startup["start_new_session"] = True
    try:
        proc = subprocess.Popen(
            [str(executable), *[str(value) for value in arguments]],
            cwd=str(cwd) if cwd else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            **startup,
        )
    except OSError as exc:
        raise BrowserError(f"Natives Programm konnte nicht gestartet werden: {executable} ({exc})") from exc
    timed_out = False
    try:
        stdout, stderr = proc.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        if os.name == "nt":
            # /T is essential: Chromium creates children which otherwise
            # survive a timeout and can lock the temporary profile.
            try:
                subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8, check=False)
            except (OSError, subprocess.TimeoutExpired):
                proc.kill()
            stdout, stderr = proc.communicate()
        else:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                stdout, stderr = proc.communicate(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                stdout, stderr = proc.communicate()
    stdout_truncated = len(stdout) > max_stdout
    stderr_truncated = len(stderr) > max_stderr
    return ProcessResult(
        exit_code=proc.returncode if not timed_out else 1,
        stdout=stdout[:max_stdout],
        stderr=stderr[:max_stderr],
        timed_out=timed_out,
        stdout_truncated=stdout_truncated,
        stderr_truncated=stderr_truncated,
    )


def _browser_identity(path: Path) -> BrowserInfo:
    real = path.resolve(strict=True)
    if sys.platform.startswith("linux") and (str(real) == "/usr/bin/snap" or str(real).startswith("/snap/")):
        raise BrowserError(f"Snap-Browser liegt außerhalb des unterstützten Browservertrags: {real}")
    try:
        if real.stat().st_size <= 131072:
            prefix = real.read_bytes()[:131072]
            if sys.platform.startswith("linux") and prefix.startswith(b"#!") and re.search(rb"(?im)(?:^|[\s/])snap(?:\s+run)?\s+", prefix):
                raise BrowserError(f"Snap-Transition-Launcher liegt außerhalb des unterstützten Browservertrags: {real}")
    except OSError as exc:
        raise BrowserError(f"Browserpfad konnte nicht sicher geprüft werden: {real} ({exc})") from exc
    result = run_process(real, ["--version"], 8, 4096, 4096)
    text = re.sub(r"[\r\n]+", " ", result.stdout + result.stderr).strip()
    if result.timed_out or result.exit_code != 0 or not text:
        raise BrowserError(f"Browser-Version konnte nicht sicher ermittelt werden: {real}")
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
        raise BrowserError(f"Executable konnte keinem unterstützten Browser zugeordnet werden: {real}")
    version_match = re.search(r"(?<!\d)(\d+(?:\.\d+){1,3})(?!\d)", text)
    if not version_match:
        raise BrowserError(f"Browser meldet keine auswertbare Version: {real}")
    return BrowserInfo(name, "gecko" if name == "firefox" else "chromium", real, version_match.group(1), text)


def browser_candidates(
    requested: str = "auto",
    executable_path: Optional[str] = None,
    allow_firefox: bool = False,
    require_chromium: bool = False,
) -> List[BrowserInfo]:
    if executable_path:
        path = Path(executable_path)
        if not path.is_file():
            raise BrowserError(f"Expliziter Browserpfad muss auf eine vorhandene Datei zeigen: {path}")
        info = _browser_identity(path)
        if requested != "auto" and info.name != requested:
            raise BrowserError(f"Browserpfad meldet '{info.name}', angefordert wurde '{requested}'.")
        if info.engine != "chromium" and (require_chromium or not allow_firefox):
            raise BrowserError("Firefox ist nur für eine ausdrücklich aktivierte Layoutdiagnose zulässig.")
        return [info]

    if sys.platform == "win32":
        program_files = [os.environ.get("PROGRAMFILES", ""), os.environ.get("PROGRAMFILES(X86)", ""), os.environ.get("LOCALAPPDATA", "")]
        definitions = [
            ("chrome", [str(Path(base) / "Google/Chrome/Application/chrome.exe") for base in program_files if base], ["chrome.exe", "chrome"]),
            ("chromium", [], ["chromium.exe", "chromium"]),
            ("edge", [str(Path(base) / "Microsoft/Edge/Application/msedge.exe") for base in program_files if base], ["msedge.exe", "msedge"]),
            ("firefox", [str(Path(base) / "Mozilla Firefox/firefox.exe") for base in program_files if base], ["firefox.exe", "firefox"]),
        ]
    elif sys.platform == "darwin":
        definitions = [
            ("chrome", ["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"], ["google-chrome", "chrome"]),
            ("chromium", ["/Applications/Chromium.app/Contents/MacOS/Chromium"], ["chromium"]),
            ("edge", ["/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"], ["microsoft-edge", "msedge"]),
            ("firefox", ["/Applications/Firefox.app/Contents/MacOS/firefox"], ["firefox"]),
        ]
    else:
        definitions = [
            ("chrome", ["/usr/bin/google-chrome-stable", "/usr/bin/google-chrome"], ["google-chrome-stable", "google-chrome", "chrome"]),
            ("chromium", ["/usr/bin/chromium", "/usr/bin/chromium-browser"], ["chromium", "chromium-browser"]),
            ("edge", ["/usr/bin/microsoft-edge-stable", "/usr/bin/microsoft-edge"], ["microsoft-edge-stable", "microsoft-edge", "msedge"]),
            ("firefox", ["/usr/bin/firefox"], ["firefox"]),
        ]
    found: List[BrowserInfo] = []
    seen: set = set()
    for name, paths, commands in definitions:
        if requested != "auto" and name != requested:
            continue
        if requested == "auto" and name == "firefox" and not allow_firefox:
            continue
        for raw in [*paths, *[shutil.which(command) or "" for command in commands]]:
            if not raw:
                continue
            path = Path(raw)
            try:
                canonical = str(path.resolve(strict=True))
            except OSError:
                continue
            if canonical in seen:
                continue
            seen.add(canonical)
            try:
                info = _browser_identity(path)
            except BrowserError:
                continue
            if info.name != name or (require_chromium and info.engine != "chromium"):
                continue
            found.append(info)
            break
    return found


def resolve_browser(requested: str = "auto", executable_path: Optional[str] = None, allow_firefox: bool = False, require_chromium: bool = False) -> BrowserInfo:
    values = browser_candidates(requested, executable_path, allow_firefox, require_chromium)
    if not values:
        raise BrowserError(f"Kein passender Browser gefunden (angefordert: {requested}).")
    return values[0]


def sha256(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def safe_name(value: str) -> str:
    return re.sub(r"\s+", "-", re.sub(r"[\\/:*?\"<>|]+", "-", value)).strip("-")


def html_pages(text: str) -> List[str]:
    pattern = re.compile(r"<main\b(?=[^>]*\bclass\s*=\s*[\"'][^\"']*\bpage\b[^\"']*[\"'])[^>]*>(.*?)</main\s*>", re.I | re.S)
    return [match.group(0) for match in pattern.finditer(text)]


def html_page_bodies(text: str) -> List[str]:
    pattern = re.compile(r"<main\b(?=[^>]*\bclass\s*=\s*[\"'][^\"']*\bpage\b[^\"']*[\"'])[^>]*>(.*?)</main\s*>", re.I | re.S)
    return [match.group(1) for match in pattern.finditer(text)]


def build_capture_html(source: str, page_html: str) -> str:
    capture_css = """<style id=\"layoutcheck-page-capture\">html,body{width:210mm!important;height:297mm!important;min-height:297mm!important;margin:0!important;padding:0!important;overflow:hidden!important;background:#fff!important}body>main.page{width:210mm!important;height:297mm!important;margin:0!important;box-shadow:none!important;break-after:auto!important;break-before:auto!important}</style>"""
    geometry = """<script id=\"layoutcheck-geometry-audit\">(()=>{const p=document.querySelector('body > main.page');const r={available:!!p,pageOverflowX:false,pageOverflowY:false,outsideElements:[],pageClientWidth:0,pageClientHeight:0,pageScrollWidth:0,pageScrollHeight:0};if(!p){r.error='isolierter page-Container fehlt'}else{const q=p.getBoundingClientRect();r.pageClientWidth=p.clientWidth;r.pageClientHeight=p.clientHeight;r.pageScrollWidth=p.scrollWidth;r.pageScrollHeight=p.scrollHeight;r.pageOverflowX=p.scrollWidth>p.clientWidth+1;r.pageOverflowY=p.scrollHeight>p.clientHeight+1;for(const e of Array.from(p.querySelectorAll('*'))){if(['SCRIPT','STYLE','META','LINK'].includes(e.tagName))continue;const s=getComputedStyle(e);if(s.display==='none'||s.visibility==='hidden')continue;const b=e.getBoundingClientRect();if(b.width<=0||b.height<=0)continue;if(b.left<q.left-1||b.top<q.top-1||b.right>q.right+1||b.bottom>q.bottom+1){r.outsideElements.push({tag:e.tagName.toLowerCase(),left:Math.round(b.left-q.left),top:Math.round(b.top-q.top),right:Math.round(b.right-q.left),bottom:Math.round(b.bottom-q.top)});if(r.outsideElements.length>=12)break}}}document.documentElement.setAttribute('data-layoutcheck-geometry-b64',btoa(JSON.stringify(r)))})();</script>"""
    if not re.search(r"</head\s*>", source, re.I):
        raise BrowserError("HTML enthält kein schließendes head-Element.")
    result = re.sub(r"</head\s*>", capture_css + "\n</head>", source, count=1, flags=re.I)
    body = re.compile(r"(?P<open><body\b[^>]*>).*?(?P<close></body\s*>)", re.I | re.S)
    if not body.search(result):
        raise BrowserError("HTML enthält kein vollständiges body-Element.")
    return body.sub(lambda match: match.group("open") + "\n" + page_html + "\n" + geometry + "\n" + match.group("close"), result, count=1)


def png_dimensions(path: Path) -> Tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise BrowserError(f"Screenshot hat keine gültige PNG-Signatur: {path}")
    return struct.unpack(">II", data[16:24])


def _paeth(left: int, up: int, upper_left: int) -> int:
    estimate = left + up - upper_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= up_distance and left_distance <= upper_left_distance:
        return left
    if up_distance <= upper_left_distance:
        return up
    return upper_left


def read_png_pixels(path: Path, maximum_pixels: int = 50_000_000) -> Tuple[int, int, int, int, bytes]:
    """Return ``width, height, color_type, channels, unfiltered pixels``.

    Chromium currently emits non-interlaced 8-bit RGB/RGBA images.  Keeping a
    small decoder here avoids a hidden Pillow/PyPI dependency and lets the
    Linux implementation enforce the same density gate as PowerShell.
    """

    data = path.read_bytes()
    if len(data) > 256 * 1024 * 1024:
        raise BrowserError("PNG überschreitet die Sicherheitsgrenze von 256 MiB.")
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise BrowserError(f"Screenshot hat keine gültige PNG-Signatur: {path}")
    offset = 8
    width = height = channels = 0
    color_type = -1
    compressed = bytearray()
    seen_header = seen_data = seen_end = False
    while offset < len(data):
        if offset + 12 > len(data):
            raise BrowserError("PNG-Chunk ist abgeschnitten.")
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        end = offset + 12 + length
        if end > len(data):
            raise BrowserError("PNG-Chunk ist abgeschnitten.")
        payload = data[offset + 8 : offset + 8 + length]
        expected_crc = struct.unpack(">I", data[offset + 8 + length : end])[0]
        if (binascii.crc32(kind + payload) & 0xFFFFFFFF) != expected_crc:
            raise BrowserError(f"PNG-Chunk besitzt eine ungültige CRC: {kind.decode('ascii', errors='replace')}.")
        if kind == b"IHDR":
            if seen_header or length != 13 or offset != 8:
                raise BrowserError("PNG muss genau einen führenden IHDR-Chunk enthalten.")
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            if width < 1 or height < 1 or width * height > maximum_pixels:
                raise BrowserError("PNG-Abmessungen sind ungültig oder überschreiten die Pixelgrenze.")
            if bit_depth != 8 or color_type not in (0, 2, 6):
                raise BrowserError("Nur 8-Bit-PNG in Graustufen-, RGB- oder RGBA-Darstellung wird unterstützt.")
            if compression != 0 or filtering != 0 or interlace != 0:
                raise BrowserError("PNG verwendet eine nicht unterstützte Kompression, Filtermethode oder Interlace-Darstellung.")
            channels = {0: 1, 2: 3, 6: 4}[color_type]
            seen_header = True
        elif kind == b"IDAT":
            if not seen_header:
                raise BrowserError("PNG-IDAT steht vor IHDR.")
            compressed.extend(payload)
            seen_data = True
        elif kind == b"IEND":
            if not seen_header or not seen_data or payload:
                raise BrowserError("PNG-IEND ist ungültig.")
            seen_end = True
            offset = end
            break
        elif kind[:1].isupper() and kind != b"PLTE":
            raise BrowserError(f"Nicht unterstützter kritischer PNG-Chunk: {kind.decode('ascii', errors='replace')}.")
        offset = end
    if not seen_end or offset != len(data):
        raise BrowserError("PNG endet nicht exakt mit IEND.")
    try:
        filtered = zlib.decompress(bytes(compressed))
    except zlib.error as exc:
        raise BrowserError(f"PNG-Daten konnten nicht dekomprimiert werden: {exc}") from exc
    stride = width * channels
    expected = (stride + 1) * height
    if len(filtered) != expected:
        raise BrowserError("PNG-Datenlänge stimmt nicht mit den Abmessungen überein.")
    pixels = bytearray(stride * height)
    for y in range(height):
        source = y * (stride + 1)
        filter_kind = filtered[source]
        if filter_kind > 4:
            raise BrowserError(f"Nicht unterstützter PNG-Zeilenfilter: {filter_kind}.")
        destination = y * stride
        for x in range(stride):
            raw = filtered[source + 1 + x]
            left = pixels[destination + x - channels] if x >= channels else 0
            up = pixels[destination - stride + x] if y else 0
            upper_left = pixels[destination - stride + x - channels] if y and x >= channels else 0
            predictor = (0, left, up, (left + up) // 2, _paeth(left, up, upper_left))[filter_kind]
            pixels[destination + x] = (raw + predictor) & 0xFF
    return width, height, color_type, channels, bytes(pixels)


def measure_bottom_whitespace(path: Path, document_name: str, page_number: int, page_count: int, bottom_reserve_mm: float) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "available": False,
        "bottomWhitespacePx": None,
        "bottomWhitespaceMm": None,
        "pageNumber": page_number,
        "pageCount": page_count,
        "scanBottomReserveMm": bottom_reserve_mm,
        "warning": None,
    }
    try:
        width, height, color_type, channels, pixels = read_png_pixels(path)
        stride = width * channels
        left = max(8, int(width * 0.03))
        right = min(width - 9, int(width * 0.97))
        if right < left:
            raise BrowserError("PNG ist für die Layoutdichteprüfung zu schmal.")
        reserve_pixels = max(2, round(bottom_reserve_mm * height / 297.0))
        scan_bottom = max(0, height - 1 - reserve_pixels)
        last_ink = -1
        for y in range(scan_bottom, -1, -1):
            ink_samples = 0
            for x in range(left, right + 1, 2):
                value = y * stride + x * channels
                if color_type == 0:
                    red = green = blue = pixels[value]
                    alpha = 255
                else:
                    red, green, blue = pixels[value : value + 3]
                    alpha = pixels[value + 3] if color_type == 6 else 255
                if alpha < 255:
                    red = round((red * alpha + 255 * (255 - alpha)) / 255.0)
                    green = round((green * alpha + 255 * (255 - alpha)) / 255.0)
                    blue = round((blue * alpha + 255 * (255 - alpha)) / 255.0)
                if red < 242 or green < 242 or blue < 242:
                    ink_samples += 1
                    if ink_samples >= 2:
                        last_ink = y
                        break
            if last_ink >= 0:
                break
        if last_ink >= 0:
            whitespace_px = scan_bottom - last_ink
            whitespace_mm = round(whitespace_px * 297.0 / height, 1)
            result.update(available=True, bottomWhitespacePx=whitespace_px, bottomWhitespaceMm=whitespace_mm)
            maximum = 55.0 if document_name.startswith("Lebenslauf -") else 70.0
            if whitespace_mm > maximum:
                result["warning"] = f"Seite {page_number} von {page_count} hat ungewöhnlich viel freie Fläche im nutzbaren Inhaltsbereich: {whitespace_mm} mm."
            elif whitespace_mm < 4.0:
                result["warning"] = f"Inhalt auf Seite {page_number} von {page_count} liegt mit nur {whitespace_mm} mm Abstand nahe an der unteren Inhaltsgrenze."
        else:
            result["warning"] = f"Auf Seite {page_number} von {page_count} wurde im nutzbaren Inhaltsbereich kein auswertbarer Inhalt erkannt."
    except (OSError, BrowserError, ValueError, struct.error) as exc:
        result["warning"] = f"Layoutdichte konnte nicht automatisch ausgewertet werden: {exc}"
    return result


def validate_png(path: Path, width: int, height: int, started: float) -> None:
    if not path.is_file():
        raise BrowserError(f"Screenshot wurde nicht erzeugt: {path}")
    if path.stat().st_mtime < started - 1:
        raise BrowserError(f"Screenshot ist älter als der aktuelle Browserlauf: {path}")
    if path.stat().st_size <= 5000:
        raise BrowserError(f"Screenshot ist zu klein ({path.stat().st_size} Bytes): {path}")
    actual = png_dimensions(path)
    if actual != (width, height):
        raise BrowserError(f"Screenshot hat unerwartete Abmessungen ({actual[0]} x {actual[1]} statt {width} x {height}): {path}")


def pdf_media_boxes(path: Path) -> List[Tuple[float, float]]:
    text = path.read_bytes().decode("latin-1", errors="ignore")
    boxes: List[Tuple[float, float]] = []
    for match in re.finditer(r"/MediaBox\s*\[\s*([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s+([-+]?[0-9]*\.?[0-9]+)\s*\]", text):
        left, bottom, right, top = [float(match.group(i)) for i in range(1, 5)]
        boxes.append((abs(right - left), abs(top - bottom)))
    return boxes


def pdf_page_count(path: Path) -> int:
    return len(re.findall(rb"/Type\s*/Page(?!s)", path.read_bytes()))


def pdf_media_box_summary(path: Path) -> Optional[str]:
    boxes = pdf_media_boxes(path)
    return None if not boxes else f"{boxes[0][0]:.2f} x {boxes[0][1]:.2f} pt"


def validate_pdf(path: Path, expected_pages: int, started: float, min_bytes: int = 5000) -> None:
    if not path.is_file():
        raise BrowserError(f"PDF wurde nicht erzeugt: {path}")
    stat = path.stat()
    if stat.st_mtime < started - 1:
        raise BrowserError(f"PDF ist älter als der aktuelle Browserlauf: {path}")
    if stat.st_size < min_bytes:
        raise BrowserError(f"PDF ist zu klein ({stat.st_size} Bytes): {path}")
    data = path.read_bytes()
    if not data.startswith(b"%PDF-"):
        raise BrowserError(f"PDF-Datei hat keinen PDF-Header: {path}")
    if not re.search(rb"%%EOF\s*$", data[-4096:]):
        raise BrowserError(f"PDF-Datei hat keinen gültigen EOF-Marker: {path}")
    boxes = pdf_media_boxes(path)
    if not boxes:
        raise BrowserError(f"PDF enthält keine lesbare MediaBox: {path}")
    for width, height in boxes:
        if not (590 <= width <= 600 and 838 <= height <= 846):
            raise BrowserError(f"PDF ist nicht DIN A4. MediaBox: {width:.2f} x {height:.2f} pt, erwartet ca. 595 x 842 pt: {path}")
    count = pdf_page_count(path)
    if count != expected_pages:
        raise BrowserError(f"PDF-Seitenzahl stimmt nicht mit dem HTML überein ({count} statt {expected_pages}): {path}")


def _chromium_base(profile: Path, width: int = 794, height: int = 1123) -> List[str]:
    arguments = [
        "--headless=new", "--disable-gpu", "--disable-dev-shm-usage",
        "--no-first-run", "--disable-background-networking", "--disable-extensions", "--hide-scrollbars",
        f"--user-data-dir={profile}", f"--window-size={width},{height}",
    ]
    effective_uid = os.geteuid() if hasattr(os, "geteuid") else -1
    if sys.platform.startswith("linux") and effective_uid == 0:
        if os.environ.get("APPLY_FOUNDRY_ALLOW_UNSANDBOXED_BROWSER") != "1":
            raise BrowserError(
                "Chromium wird als Root nicht ohne Browser-Sandbox gestartet. "
                "Verwende einen normalen Benutzer; nur ein isolierter ephemerer CI-Container darf "
                "APPLY_FOUNDRY_ALLOW_UNSANDBOXED_BROWSER=1 setzen."
            )
        arguments.append("--no-sandbox")
    return arguments


def render_screenshot(browser: BrowserInfo, capture_html: Path, output: Path, width: int, height: int, timeout: int, temp_root: Path) -> Dict[str, Any]:
    if browser.engine != "chromium":
        raise BrowserError(f"Browser {browser.name} unterstützt keine verbindliche DOM-Geometrieprüfung.")
    run_root = Path(tempfile.mkdtemp(prefix="layout-", dir=str(temp_root)))
    try:
        profile = run_root / "profile"
        profile.mkdir()
        browser_html = run_root / "capture.html"
        shutil.copy2(capture_html, browser_html)
        dump = run_process(browser.path, [*_chromium_base(profile, width, height), "--dump-dom", browser_html.as_uri()], timeout, 262144, 8192)
        if dump.timed_out:
            raise BrowserError(f"DOM-Geometrieprüfung überschritt das Zeitlimit von {timeout} Sekunden.")
        if dump.exit_code != 0 or dump.stdout_truncated:
            raise BrowserError(f"DOM-Geometrieprüfung endete mit Exitcode {dump.exit_code}: {dump.stderr.strip()}")
        match = re.search(r'data-layoutcheck-geometry-b64="([A-Za-z0-9+/=]+)"', dump.stdout)
        if not match:
            raise BrowserError("DOM-Geometrieprüfung lieferte keinen auswertbaren Messwert.")
        try:
            geometry = json.loads(base64.b64decode(match.group(1)).decode("utf-8"))
        except (ValueError, binascii.Error, UnicodeError) as exc:
            raise BrowserError(f"DOM-Geometrieprüfung lieferte ungültige Messdaten: {exc}") from exc
        if not geometry.get("available"):
            raise BrowserError(f"DOM-Geometrieprüfung konnte die A4-Seite nicht messen: {geometry.get('error')}")
        if geometry.get("pageOverflowX") or geometry.get("pageOverflowY") or geometry.get("outsideElements"):
            raise BrowserError(
                "DOM-Geometrie meldet Überlauf "
                f"(horizontal={geometry.get('pageOverflowX')}, vertikal={geometry.get('pageOverflowY')}, "
                f"Elemente außerhalb={len(geometry.get('outsideElements') or [])})."
            )
        browser_png = run_root / "capture.png"
        started = time.time()
        shot = run_process(browser.path, [*_chromium_base(profile, width, height), f"--screenshot={browser_png}", browser_html.as_uri()], timeout, 4096, 8192)
        if shot.timed_out:
            raise BrowserError(f"Browserlauf hat das Zeitlimit von {timeout} Sekunden überschritten.")
        if shot.exit_code != 0:
            raise BrowserError(f"Browser beendete den Lauf mit Exitcode {shot.exit_code}. stderr: {shot.stderr.strip()}")
        validate_png(browser_png, width, height, started)
        pending = output.with_name(output.name + ".pending")
        shutil.copy2(browser_png, pending)
        os.replace(pending, output)
        validate_png(output, width, height, started)
        return geometry
    finally:
        shutil.rmtree(run_root, ignore_errors=True)


def print_html(browser: BrowserInfo, html: Path, output: Path, timeout: int, temp_root: Path, min_bytes: int = 5000) -> Dict[str, Any]:
    if browser.engine != "chromium":
        raise BrowserError("Der verbindliche PDF-Export benötigt einen Chromium-Browser.")
    pages = len(html_pages(html.read_text(encoding="utf-8")))
    if pages <= 0:
        raise BrowserError(f"HTML enthält keine expliziten A4-Seitencontainer: {html.name}")
    run_root = Path(tempfile.mkdtemp(prefix="print-", dir=str(temp_root)))
    try:
        profile = run_root / "profile"
        profile.mkdir()
        browser_pdf = run_root / "document.pdf"
        started = time.time()
        result = run_process(
            browser.path,
            [*_chromium_base(profile), f"--print-to-pdf={browser_pdf}", "--print-to-pdf-no-header", "--no-pdf-header-footer", html.resolve().as_uri()],
            timeout,
            4096,
            8192,
        )
        if result.timed_out:
            raise BrowserError(f"PDF-Browserlauf überschritt das Zeitlimit von {timeout} Sekunden.")
        if result.exit_code != 0:
            raise BrowserError(f"PDF-Browserlauf endete mit Exitcode {result.exit_code}: {result.stderr.strip()}")
        validate_pdf(browser_pdf, pages, started, min_bytes)
        output.parent.mkdir(parents=True, exist_ok=True)
        pending = output.with_name(output.name + ".pending")
        shutil.copy2(browser_pdf, pending)
        os.replace(pending, output)
        validate_pdf(output, pages, started, min_bytes)
        return {
            "expectedPageCount": pages,
            "actualPageCount": pdf_page_count(output),
            "pdfBytes": output.stat().st_size,
            "mediaBox": pdf_media_box_summary(output),
            "a4": True,
        }
    finally:
        shutil.rmtree(run_root, ignore_errors=True)


def check_chromium_readiness(browser: BrowserInfo, timeout: int, temp_root: Path) -> None:
    """Prove that the selected Chromium can safely render and print a local A4 page."""

    if browser.engine != "chromium":
        raise BrowserError("Die Browser-Vorprüfung akzeptiert ausschließlich Chromium.")
    run_root = Path(tempfile.mkdtemp(prefix="browser-readiness-", dir=str(temp_root)))
    try:
        source = run_root / "readiness.html"
        output = run_root / "readiness.pdf"
        source.write_text(
            "<!doctype html><html lang=\"de\"><head><meta charset=\"utf-8\">"
            "<style>@page { size: A4; margin: 0; }.page { width: 210mm; height: 297mm; }</style>"
            "</head><body><main class=\"page\">Browser bereit</main></body></html>",
            encoding="utf-8",
        )
        print_html(browser, source, output, timeout, temp_root)
    finally:
        shutil.rmtree(run_root, ignore_errors=True)


def _pdf_literal(raw: bytes, start: int) -> Tuple[Optional[str], int]:
    """Decode a PDF literal string beginning at ``start`` (the opening parenthesis)."""

    if start >= len(raw) or raw[start:start + 1] != b"(":
        return None, start
    output = bytearray()
    depth, index = 1, start + 1
    escapes = {ord("n"): b"\n", ord("r"): b"\r", ord("t"): b"\t", ord("b"): b"\b", ord("f"): b"\f"}
    while index < len(raw):
        value = raw[index]
        index += 1
        if value == ord("\\"):
            if index >= len(raw):
                break
            escaped = raw[index]
            index += 1
            if escaped in escapes:
                output.extend(escapes[escaped])
            elif escaped in (ord("\n"), ord("\r")):
                if escaped == ord("\r") and index < len(raw) and raw[index] == ord("\n"):
                    index += 1
            elif ord("0") <= escaped <= ord("7"):
                digits = bytes([escaped])
                while index < len(raw) and len(digits) < 3 and ord("0") <= raw[index] <= ord("7"):
                    digits += bytes([raw[index]])
                    index += 1
                output.append(int(digits, 8))
            else:
                output.append(escaped)
            continue
        if value == ord("("):
            depth += 1
        elif value == ord(")"):
            depth -= 1
            if depth == 0:
                return output.decode("utf-8", errors="replace"), index
        output.append(value)
    return None, index


def _pdf_uri_values(raw: bytes) -> List[str]:
    """Extract URI actions from annotation dictionaries in direct or object streams."""

    targets: List[str] = []
    for annotation in re.finditer(rb"(?s)/Subtype\s*/Link\b(.*?)(?=/Subtype\s*/Link\b|\bendobj\b|\Z)", raw):
        value = annotation.group(0)
        if not re.search(rb"/S\s*/URI\b", value):
            continue
        for match in re.finditer(rb"/URI\s*", value):
            index = match.end()
            while index < len(value) and value[index] in b" \t\r\n\f\x00":
                index += 1
            if value[index:index + 1] == b"(":
                decoded, _ = _pdf_literal(value, index)
                if decoded is not None:
                    targets.append(decoded)
            elif value[index:index + 1] == b"<":
                closing = value.find(b">", index + 1)
                if closing > index:
                    try:
                        targets.append(bytes.fromhex(value[index + 1:closing].decode("ascii")).decode("utf-8", errors="replace"))
                    except ValueError:
                        pass
    return targets


def extract_pdf_link_targets(path: Path) -> List[str]:
    """Read URI link annotations without accepting text-only link representations."""

    data = path.read_bytes()
    objects = [match.group(2) for match in re.finditer(rb"(?s)(\d+)\s+\d+\s+obj\b(.*?)\bendobj", data)]
    if not objects:
        raise BrowserError("PDF enthält keine lesbaren Objekte für die Linkprüfung.")
    targets: List[str] = []
    for body in objects:
        targets.extend(_pdf_uri_values(body))
        if b"/Type" not in body or b"/ObjStm" not in body or b"/FlateDecode" not in body:
            continue
        marker = re.search(rb"(?<![A-Za-z])stream(?:\r\n|\n|\r)", body)
        length = re.search(rb"/Length\s+(\d+)(?!\s+\d+\s+R)", body[:marker.start()] if marker else b"")
        if not marker or not length:
            continue
        raw = body[marker.end():marker.end() + int(length.group(1))]
        try:
            targets.extend(_pdf_uri_values(zlib.decompress(raw)))
        except zlib.error:
            continue
    return targets


def verify_pdf_link_targets(path: Path, expected_targets: Sequence[str]) -> Dict[str, Any]:
    """Return a hash-bound, exact annotation comparison for one generated PDF."""

    expected = Counter(expected_targets)
    actual = Counter(extract_pdf_link_targets(path))
    missing = list((expected - actual).elements())
    unexpected = list((actual - expected).elements())
    return {
        "expectedCount": sum(expected.values()),
        "actualCount": sum(actual.values()),
        "expectedTargets": sorted(expected.elements()),
        "actualTargets": sorted(actual.elements()),
        "missingTargets": sorted(missing),
        "unexpectedTargets": sorted(unexpected),
        "passed": not missing and not unexpected,
    }


def extract_pdf_text(path: Path) -> str:
    """Extract Chrome's ToUnicode text with length-bound PDF streams.

    PDF streams are binary data.  Searching for ``endstream`` inside them is
    unsafe because those bytes can occur in Flate data; Chrome 151 exposed
    precisely that failure mode.  We first index indirect objects as bytes and
    then read each stream from its dictionary's direct ``/Length`` value (or a
    referenced length object).  The text/CMap grammar is decoded only after
    the stream boundary is proven.
    """
    data = path.read_bytes()
    objects: Dict[int, bytes] = {}
    for match in re.finditer(rb"(?s)(\d+)\s+\d+\s+obj\b(.*?)\bendobj", data):
        objects[int(match.group(1))] = match.group(2)
    if not objects:
        raise BrowserError("PDF enthält keine lesbaren Objekte.")

    def text(body: bytes) -> str:
        return body.decode("latin-1", errors="ignore")

    def stream(body: bytes) -> str:
        marker = re.search(rb"(?<![A-Za-z])stream(?:\r\n|\n|\r)", body)
        if not marker:
            return ""
        dictionary = body[: marker.start()]
        direct = re.search(rb"/Length\s+(\d+)(?!\s+\d+\s+R)", dictionary)
        indirect = re.search(rb"/Length\s+(\d+)\s+\d+\s+R", dictionary)
        length: Optional[int] = int(direct.group(1)) if direct else None
        if indirect:
            length_body = objects.get(int(indirect.group(1)))
            number = re.search(rb"\b(\d+)\b", length_body or b"")
            length = int(number.group(1)) if number else None
        if length is None:
            raise BrowserError("PDF-Stream besitzt keine auswertbare /Length-Angabe.")
        start = marker.end()
        end = start + length
        if length < 0 or end > len(body):
            raise BrowserError("PDF-Streamlänge überschreitet die Objektgrenze.")
        raw = body[start:end]
        trailer = body[end : end + 32].lstrip(b"\r\n")
        if not trailer.startswith(b"endstream"):
            raise BrowserError("PDF-Stream endet nicht an der durch /Length gebundenen Grenze.")
        if b"/FlateDecode" in dictionary:
            try:
                raw = zlib.decompress(raw)
            except zlib.error as exc:
                raise BrowserError(f"Komprimierter PDF-Textstrom konnte nicht gelesen werden: {exc}") from exc
        return text(raw)

    def hex_unicode(value: str) -> str:
        try:
            raw = bytes.fromhex(value)
        except ValueError:
            return ""
        if len(raw) == 1:
            return chr(raw[0])
        return raw.decode("utf-16-be", errors="ignore")

    def cmap(value: str) -> Dict[str, str]:
        result: Dict[str, str] = {}
        for match in re.finditer(r"(?im)^\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*$", value):
            result[match.group(1).upper()] = hex_unicode(match.group(2))
        for match in re.finditer(r"(?im)^\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*$", value):
            start, end, target = int(match.group(1), 16), int(match.group(2), 16), int(match.group(3), 16)
            sw, tw = len(match.group(1)), len(match.group(3))
            for code in range(start, end + 1):
                result[f"{code:0{sw}X}"] = hex_unicode(f"{target + code - start:0{tw}X}")
        for match in re.finditer(r"(?ims)<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*?)\]", value):
            start, width = int(match.group(1), 16), len(match.group(1))
            targets = re.findall(r"<([0-9A-Fa-f]+)>", match.group(3))
            for index, target in enumerate(targets):
                result[f"{start + index:0{width}X}"] = hex_unicode(target)
        return result

    font_maps: Dict[int, Dict[str, str]] = {}
    for number, raw_body in objects.items():
        body = text(raw_body)
        match = re.search(r"/ToUnicode\s+(\d+)\s+0\s+R", body)
        if match and int(match.group(1)) in objects:
            font_maps[number] = cmap(stream(objects[int(match.group(1))]))
    if not font_maps:
        raise BrowserError("PDF enthält keine auswertbare ToUnicode-Zuordnung.")
    page_objects = [(number, text(body)) for number, body in sorted(objects.items()) if re.search(rb"/Type\s*/Page(?!s)", body)]
    if not page_objects:
        raise BrowserError("PDF enthält keine auswertbaren Seitenobjekte.")

    def decode_hex(value: str, mapping: Mapping[str, str]) -> str:
        width = 4 if len(value) % 4 == 0 else 2
        return "".join(mapping.get(value[i : i + width].upper(), hex_unicode(value[i : i + width])) for i in range(0, len(value) - width + 1, width))

    output: List[str] = []
    token_pattern = re.compile(r"(?s)(\bBT\b)|(\bET\b)|/([A-Za-z0-9]+)\s+[-+0-9.]+\s+Tf|<([0-9A-Fa-f]+)>\s*Tj|\(((?:\\.|[^\\)])*)\)\s*Tj|\[(.*?)\]\s*TJ")
    for _, page in page_objects:
        resources: Dict[str, int] = {}
        font_block = re.search(r"(?s)/Font\s*<<(.*?)>>", page)
        if font_block:
            resources = {name: int(number) for name, number in re.findall(r"/([A-Za-z0-9]+)\s+(\d+)\s+0\s+R", font_block.group(1))}
        array = re.search(r"(?s)/Contents\s*\[(.*?)\]", page)
        refs = [int(value) for value in re.findall(r"(\d+)\s+0\s+R", array.group(1))] if array else []
        if not refs:
            single = re.search(r"/Contents\s+(\d+)\s+0\s+R", page)
            if single:
                refs = [int(single.group(1))]
        mapping: Mapping[str, str] = {}
        for ref in refs:
            if ref not in objects:
                continue
            content = stream(objects[ref])
            for token in token_pattern.finditer(content):
                if token.group(3):
                    mapping = font_maps.get(resources.get(token.group(3), -1), {})
                elif token.group(4):
                    output.append(decode_hex(token.group(4), mapping))
                elif token.group(5):
                    output.append(re.sub(r"\\([()\\])", r"\1", token.group(5)).replace(r"\n", "\n").replace(r"\r", "\r").replace(r"\t", "\t"))
                elif token.group(6):
                    for hex_value, literal in re.findall(r"<([0-9A-Fa-f]+)>|\(((?:\\.|[^\\)])*)\)", token.group(6)):
                        output.append(decode_hex(hex_value, mapping) if hex_value else re.sub(r"\\([()\\])", r"\1", literal))
                elif token.group(2):
                    output.append("\n")
        output.append("\n")
    return "".join(output)
