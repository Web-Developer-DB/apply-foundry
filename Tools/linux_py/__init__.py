"""Linux-native apply-foundry workflow implementation.

The package intentionally depends on the Python standard library only.  Core
handlers live in :mod:`commands_core`; browser/finalization handlers may be
provided by :mod:`commands_browser` without creating a hard dependency.
"""

from importlib import import_module
from typing import Dict


def load_handlers() -> Dict[str, object]:
    """Return all installed command handlers.

    Optional browser handlers override placeholders from the core mapping.  A
    missing optional module is expected while the two implementations are
    developed independently; import errors *inside* an existing module remain
    visible instead of being silently swallowed.
    """

    from .commands_core import CORE_HANDLERS

    handlers: Dict[str, object] = dict(CORE_HANDLERS)
    try:
        module = import_module("Tools.linux_py.commands_browser")
    except ModuleNotFoundError as exc:
        if exc.name != "Tools.linux_py.commands_browser":
            raise
    else:
        handlers.update(getattr(module, "BROWSER_HANDLERS"))
    return handlers


__all__ = ["load_handlers"]
