"""Full VCP snapshots and comparison between two snapshots."""

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .ddc import DDCClient, DDCError

ALL_VCP_CODES = range(0x00, 0x100)


@dataclass(frozen=True)
class Change:
    code: int
    before: dict | None
    after: dict | None


def take_snapshot(
    client: DDCClient,
    codes=ALL_VCP_CODES,
    on_progress: Callable[[int], None] | None = None,
) -> dict:
    """Read every code and return supported values plus codes that failed to read."""
    values = {}
    errors = {}
    for code in codes:
        if on_progress:
            on_progress(code)
        key = f"0x{code:02X}"
        try:
            value = client.get_vcp(code)
        except DDCError as error:
            errors[key] = str(error)
            continue
        if value.supported:
            values[key] = {"type": value.vcp_type, "max": value.maximum, "current": value.current}
    return {"values": values, "errors": errors}


def save_snapshot(snapshot: dict, path: Path) -> None:
    path.write_text(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")


def load_snapshot(path: Path) -> dict:
    return json.loads(path.read_text())


def diff_snapshots(before: dict, after: dict) -> list[Change]:
    """Return codes whose value changed, appeared or disappeared, ordered by code."""
    before_values = before["values"]
    after_values = after["values"]
    changes = []
    for key in sorted(set(before_values) | set(after_values), key=lambda k: int(k, 16)):
        old = before_values.get(key)
        new = after_values.get(key)
        if old != new:
            changes.append(Change(code=int(key, 16), before=old, after=new))
    return changes
