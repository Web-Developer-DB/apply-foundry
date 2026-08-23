#!/usr/bin/env sh
# Compatibility alias for the canonical minimal Python bootstrap.
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec "$base/Tools/setup.sh" "$@"
