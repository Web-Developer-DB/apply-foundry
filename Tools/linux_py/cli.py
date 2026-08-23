"""Strict GNU-long-option dispatcher shared by every Python Linux entry."""

import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Dict, IO, Mapping, MutableMapping, Optional, Sequence, Tuple

from .errors import CliUsageError, WorkflowError


Handler = Callable[["CommandContext", Mapping[str, Any]], int]


@dataclass(frozen=True)
class OptionSpec:
    key: str
    kind: str = "string"
    allowed: Tuple[str, ...] = ()
    minimum: Optional[int] = None
    maximum: Optional[int] = None
    placeholder: str = "WERT"


@dataclass(frozen=True)
class CommandSpec:
    summary: str
    options: Mapping[str, OptionSpec]
    required: Tuple[str, ...] = ()


@dataclass
class CommandContext:
    invocation_dir: Path
    project_root: Path
    stdout: IO[str] = sys.stdout
    stderr: IO[str] = sys.stderr

    def out(self, value: str = "") -> None:
        print(value, file=self.stdout)

    def err(self, value: str) -> None:
        print(value, file=self.stderr)

    def ok(self, value: str) -> None:
        self.out("[OK] " + value)

    def warning(self, value: str) -> None:
        self.out("[WARNUNG] " + value)

    def error(self, value: str) -> None:
        self.err("[FEHLER] " + value)


def _value(raw: str, name: str, spec: OptionSpec, invocation_dir: Path) -> Any:
    if raw == "" or raw.strip() == "" or re.search(r"[\x00-\x1f\x7f]", raw):
        raise CliUsageError("Leerer Wert oder Steuerzeichen für %s sind nicht zulässig." % name)
    if spec.kind == "string":
        return raw
    if spec.kind == "path":
        path = Path(raw)
        if not path.is_absolute():
            path = invocation_dir / path
        return Path(os.path.abspath(str(path)))
    if spec.kind == "path_list":
        values = []
        for item in raw.split(","):
            item = item.strip()
            if not item:
                raise CliUsageError("Leerer Pfad in %s ist nicht zulässig." % name)
            path = Path(item)
            values.append(Path(os.path.abspath(str(path if path.is_absolute() else invocation_dir / path))))
        return values
    if spec.kind == "enum":
        for allowed in spec.allowed:
            if raw.lower() == allowed.lower():
                return allowed
        raise CliUsageError("Ungültiger Wert für %s. Erlaubt: %s." % (name, ", ".join(spec.allowed)))
    if spec.kind in ("int", "long"):
        if not re.fullmatch(r"[+-]?\d+", raw):
            raise CliUsageError("%s erfordert eine ganze Zahl." % name)
        value = int(raw)
        if spec.minimum is not None and value < spec.minimum or spec.maximum is not None and value > spec.maximum:
            raise CliUsageError("Wert für %s liegt außerhalb des erlaubten Bereichs %s-%s." % (name, spec.minimum, spec.maximum))
        return value
    if spec.kind == "datetime":
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError as exc:
            raise CliUsageError("%s erfordert einen gültigen ISO-Zeitpunkt." % name) from exc
    if spec.kind == "documents":
        result = []
        for item in raw.split(","):
            normalized = item.strip().lower()
            if normalized not in ("lebenslauf", "anschreiben", "email_nachricht"):
                raise CliUsageError("Ungültiges Dokument in %s. Erlaubt: lebenslauf, anschreiben, email_nachricht." % name)
            if normalized in result:
                raise CliUsageError("Dokument '%s' wurde in %s mehrfach angegeben." % (normalized, name))
            result.append(normalized)
        return result
    raise RuntimeError("Unbekannter Optionstyp: %s" % spec.kind)


def _global_help(specs: Mapping[str, CommandSpec], order: Sequence[str]) -> str:
    lines = ["Einheitlicher Bewerbungsworkflow für Linux (Python)", "", "Aufruf:", "  python3 Tools/bewerbung.py <subcommand> [optionen]", "", "Subcommands:"]
    for name in order:
        lines.append("  %-20s %s" % (name, specs[name].summary))
    lines.extend(("", "Details: <subcommand> --help"))
    return "\n".join(lines)


def _command_help(name: str, spec: CommandSpec) -> str:
    lines = [spec.summary, "", "Aufruf: %s [optionen]" % name]
    if spec.options:
        lines.extend(("", "Optionen:"))
        for cli_name, option in spec.options.items():
            suffix = "" if option.kind == "switch" else " " + option.placeholder
            required = " (Pflicht)" if cli_name in spec.required else ""
            lines.append("  %s%s%s" % (cli_name, suffix, required))
        lines.append("  -h, --help")
    return "\n".join(lines)


def parse(command: str, argv: Sequence[str], spec: CommandSpec, invocation_dir: Path) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    index = 0
    while index < len(argv):
        token = argv[index]
        if not token.startswith("--"):
            raise CliUsageError("Unerwartetes Argument '%s'. Es sind nur GNU-Langoptionen zulässig." % token)
        name, separator, inline = token.partition("=")
        if name not in spec.options:
            raise CliUsageError("Option '%s' ist für '%s' nicht zulässig." % (name, command))
        option = spec.options[name]
        if option.key in result:
            raise CliUsageError("Option '%s' wurde mehrfach angegeben." % name)
        if option.kind == "switch":
            if separator:
                raise CliUsageError("Schalter '%s' akzeptiert keinen Wert." % name)
            result[option.key] = True
            index += 1
            continue
        if not separator:
            index += 1
            if index >= len(argv):
                raise CliUsageError("Fehlender Wert für %s." % name)
            inline = argv[index]
        result[option.key] = _value(inline, name, option, invocation_dir)
        index += 1
    for required in spec.required:
        key = spec.options[required].key
        if key not in result:
            raise CliUsageError("Pflichtoption %s fehlt für '%s'." % (required, command))
    return result


def run(
    argv: Optional[Sequence[str]] = None,
    *,
    extra_handlers: Optional[Mapping[str, Handler]] = None,
    context: Optional[CommandContext] = None,
) -> int:
    from .registry import COMMAND_ORDER, COMMANDS
    from . import load_handlers

    arguments = list(sys.argv[1:] if argv is None else argv)
    ctx = context or CommandContext(Path.cwd(), Path(__file__).resolve().parents[2])
    handlers: MutableMapping[str, Handler] = load_handlers()  # type: ignore[assignment]
    if extra_handlers:
        handlers.update(extra_handlers)
    try:
        if not arguments:
            ctx.out(_global_help(COMMANDS, COMMAND_ORDER))
            return 0
        subcommand = arguments.pop(0)
        if subcommand in ("-h", "--help", "help"):
            if arguments:
                raise CliUsageError("Die globale Hilfe akzeptiert keine weiteren Argumente.")
            ctx.out(_global_help(COMMANDS, COMMAND_ORDER))
            return 0
        if re.search(r"[\x00-\x1f\x7f]", subcommand):
            raise CliUsageError("Ungültiges Subcommand.")
        name = subcommand.lower()
        if name not in COMMANDS:
            raise CliUsageError("Unbekanntes Subcommand '%s'. Mit --help werden alle Subcommands angezeigt." % subcommand)
        if arguments and arguments[0] in ("-h", "--help"):
            if len(arguments) != 1:
                raise CliUsageError("Die Subcommand-Hilfe akzeptiert keine weiteren Argumente.")
            ctx.out(_command_help(name, COMMANDS[name]))
            return 0
        values = parse(name, arguments, COMMANDS[name], ctx.invocation_dir)
        handler = handlers.get(name)
        if handler is None:
            raise WorkflowError("Subcommand '%s' ist in der Python-Laufzeit noch nicht implementiert." % name)
        code = int(handler(ctx, values))
        return code if code in (0, 1, 2) else 1
    except WorkflowError as exc:
        ctx.err("Fehler: %s" % exc)
        return exc.code
    except (OSError, ValueError, TypeError, KeyError) as exc:
        ctx.err("Fehler: Subcommand konnte nicht ausgeführt werden: %s" % exc)
        return 1


def main(argv: Optional[Sequence[str]] = None) -> None:
    raise SystemExit(run(argv))


__all__ = ["CommandContext", "CommandSpec", "Handler", "OptionSpec", "main", "parse", "run"]
