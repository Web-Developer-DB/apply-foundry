#!/usr/bin/env bash
set -euo pipefail

script_source="${BASH_SOURCE[0]}"
if [[ "$script_source" == */* ]]; then script_parent="${script_source%/*}"; else script_parent=.; fi
script_dir="$(cd -- "$script_parent" && pwd -P)"
readonly script_dir
dispatcher="$script_dir/bewerbung.py"
readonly dispatcher

if [[ ! -f "$dispatcher" ]]; then
  printf 'Fehler: Python-Dispatcher fehlt: %s\n' "$dispatcher" >&2
  exit 1
fi

python_path=''
for candidate in /usr/bin/python3 /bin/python3 /usr/local/bin/python3 /usr/bin/python /bin/python; do
  [[ -n "$candidate" && -x "$candidate" ]] || continue
  if "$candidate" -I -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) and sys.prefix == getattr(sys, "base_prefix", sys.prefix) else 1)' >/dev/null 2>&1; then
    python_path="$candidate"
    break
  fi
done

if [[ -z "$python_path" ]]; then
  printf 'Fehler: System-Python 3.9 oder neuer wurde nicht gefunden.\n' >&2
  printf 'Vorschlag: ./Tools/setup-linux.sh --runtime --dry-run\n' >&2
  exit 2
fi

exec "$python_path" "$dispatcher" "$@"
