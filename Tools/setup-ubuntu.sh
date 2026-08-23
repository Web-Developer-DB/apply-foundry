#!/usr/bin/env sh
# Compatibility alias; Ubuntu uses the same declared Linux package plan.
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec "$base/Tools/setup.sh" "$@"
