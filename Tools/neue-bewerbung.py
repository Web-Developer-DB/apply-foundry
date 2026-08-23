#!/usr/bin/env python3
"""Compatibility entry for creating an application on Linux."""

import sys
import platform
from pathlib import Path

if sys.version_info < (3, 9):
    print("Fehler: Python 3.9 oder neuer ist erforderlich.", file=sys.stderr)
    raise SystemExit(2)
if sys.prefix != getattr(sys, "base_prefix", sys.prefix):
    print("Fehler: Eine virtuelle Python-Umgebung ist nicht Teil des Linux-Laufzeitvertrags. Verwende System-Python.", file=sys.stderr)
    raise SystemExit(2)
if not sys.platform.startswith("linux") or platform.machine().lower() not in ("x86_64", "amd64"):
    print("Fehler: Die Python-Kernimplementierung unterstützt ausschließlich Linux x64.", file=sys.stderr)
    raise SystemExit(2)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from Tools.linux_py.cli import main  # noqa: E402


if __name__ == "__main__":
    main(["neu"] + sys.argv[1:])
