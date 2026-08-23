#!/usr/bin/env sh
# Minimal POSIX bootstrap; workflow logic lives exclusively in Python.
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)'; then
  exec python3 "$base/Tools/bewerbung.py" "$@"
fi
printf '%s\n' 'Python 3.11+ fehlt. Bitte zuerst den read-only Plan ausführen: Tools/setup.sh --runtime --dry-run --format json' >&2
exit 2
