"""Atomic UTF-8/JSON I/O and deterministic hashes."""

import hashlib
import json
import os
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Iterator

from .errors import ContractError


UTF8 = "utf-8"


def utc_now() -> str:
    from datetime import datetime, timezone

    return datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def read_text(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    try:
        return raw.decode(UTF8, errors="strict")
    except UnicodeDecodeError as exc:
        raise ContractError("Datei ist kein gültiges UTF-8: %s" % path) from exc


def read_json(path: Path) -> Any:
    try:
        value = json.loads(read_text(path))
    except json.JSONDecodeError as exc:
        raise ContractError("JSON-Datei ist nicht lesbar: %s (%s)" % (path, exc)) from exc
    return value


def _atomic_replace(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and (path.is_symlink() or not path.is_file()):
        raise ContractError("Atomisches Schreibziel ist keine reguläre Datei: %s" % path)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".%s." % path.name, suffix=".tmp", dir=str(path.parent))
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(str(temporary), str(path))
        try:
            directory_fd = os.open(str(path.parent), os.O_RDONLY)
        except OSError:
            directory_fd = None
        if directory_fd is not None:
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def write_atomic_text(path: Path, value: str) -> None:
    if not value.endswith("\n"):
        value += "\n"
    _atomic_replace(path, value.encode(UTF8))


def write_atomic_bytes(path: Path, value: bytes) -> None:
    _atomic_replace(path, value)


def write_atomic_json(path: Path, value: Any) -> None:
    text = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
    _atomic_replace(path, text.encode(UTF8))


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode(UTF8)


@contextmanager
def file_lock(target: Path, timeout_seconds: float = 5.0) -> Iterator[None]:
    """Small cross-process lock based on exclusive file creation."""

    lock = target.with_name(".%s.lock" % target.name)
    deadline = time.monotonic() + timeout_seconds
    fd = None
    while fd is None:
        try:
            fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            if time.monotonic() >= deadline:
                raise ContractError("Dateisperre konnte nicht rechtzeitig übernommen werden: %s" % target)
            time.sleep(0.05)
    try:
        os.write(fd, ("pid=%d\n" % os.getpid()).encode("ascii"))
        os.close(fd)
        fd = None
        yield
    finally:
        if fd is not None:
            os.close(fd)
        try:
            lock.unlink()
        except FileNotFoundError:
            pass


def artifact_record(path: Path, root: Path) -> Dict[str, Any]:
    relative = path.relative_to(root).as_posix()
    stat = path.stat()
    return {"path": relative, "bytes": stat.st_size, "sha256": sha256_file(path)}
