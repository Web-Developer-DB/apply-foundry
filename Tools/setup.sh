#!/usr/bin/env sh
# The only POSIX exception to the Python core: bootstrap Python itself.
set -eu
base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,11) else 1)'; then
  exec python3 "$base/Tools/setup.py" "$@"
fi
case " $* " in *' --runtime '*) ;; *) printf '%s\n' 'Python 3.11+ fehlt. Plan: installiere nur Python über den System-Paketmanager. Mit --runtime --yes darf dieser Starter die Installation ausführen.' >&2; exit 2;; esac
case " $* " in *' --yes '*) ;; *) printf '%s\n' 'Read-only: Python 3.11+ fehlt. Wiederhole nach Prüfung mit --runtime --yes.' >&2; exit 2;; esac
if command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install --yes python3
elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y python3
elif command -v yum >/dev/null 2>&1; then sudo yum install -y python3
elif command -v pacman >/dev/null 2>&1; then sudo pacman -Syu --noconfirm --needed python
elif command -v zypper >/dev/null 2>&1; then sudo zypper --non-interactive install python3
else printf '%s\n' 'Kein unterstützter Paketmanager erkannt. Installiere Python 3.11+ manuell und starte erneut.' >&2; exit 2
fi
exec python3 "$base/Tools/setup.py" "$@"
