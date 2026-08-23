"""Typed workflow errors and their public exit-code mapping."""


class WorkflowError(Exception):
    """Expected, user-facing workflow failure."""

    def __init__(self, message: str, code: int = 1) -> None:
        super().__init__(message)
        self.code = 2 if code == 2 else 1


class CliUsageError(WorkflowError):
    """Invalid or unsafe CLI input (exit code 2)."""

    def __init__(self, message: str) -> None:
        super().__init__(message, 2)


class ContractError(WorkflowError):
    """A persisted artifact violates its declared contract."""


class UnsafePathError(CliUsageError):
    """A path cannot be proven safe for the requested operation."""
