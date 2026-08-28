#!/usr/bin/env python3
"""Platform-neutral apply-foundry dispatcher (Python 3.11+, standard library)."""

import platform
import sys
from pathlib import Path

if sys.version_info < (3, 11):
    print("Fehler: Python 3.11 oder neuer ist erforderlich.", file=sys.stderr)
    raise SystemExit(2)
if sys.platform not in ("win32", "darwin") and not sys.platform.startswith("linux"):
    print("Fehler: Unterstützt werden Windows, Linux und macOS.", file=sys.stderr)
    raise SystemExit(2)
if platform.machine().lower() not in ("x86_64", "amd64"):
    print("Fehler: Unterstützt wird derzeit ausschließlich x64 (Intel/AMD).", file=sys.stderr)
    raise SystemExit(2)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from Tools.apply_foundry.cli import main  # noqa: E402


if __name__ == "__main__":
    main()
