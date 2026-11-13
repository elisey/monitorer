"""DDC/CI probe for finding and setting monitor controls on Apple Silicon Macs."""

import argparse
import sys
from pathlib import Path

from .ddc import DDCClient, DDCError
from .snapshot import diff_snapshots, load_snapshot, save_snapshot, take_snapshot

# Codes and values that may be written, as declared in the Philips 346B1C capabilities
# string. 0x86 (Display Scaling) is the OSD Picture Format setting.
WRITABLE_VALUES = {
    0x86: {0x01, 0x02, 0x04, 0x08, 0x21, 0x22},
    0x60: {0x11, 0x15},
    0x62: set(range(0, 101)),
}


def check_writable(code: int, value: int) -> None:
    allowed = WRITABLE_VALUES.get(code)
    if allowed is None:
        raise DDCError(f"writing VCP 0x{code:02X} is not allowed")
    if value not in allowed:
        listed = ", ".join(f"0x{v:02X}" for v in sorted(allowed))
        raise DDCError(f"value 0x{value:02X} is not allowed for VCP 0x{code:02X} ({listed})")


def _format_value(value: dict | None) -> str:
    if value is None:
        return "—"
    return f"current={value['current']} (0x{value['current']:04X}) max={value['max']}"


def _client(display_index: int) -> DDCClient:
    from .iokit import external_display_transports

    transports = external_display_transports()
    if not transports:
        raise DDCError("no external display found")
    if display_index >= len(transports):
        raise DDCError(f"display index {display_index} out of range ({len(transports)} found)")
    return DDCClient(transports[display_index])


def _cmd_caps(args) -> None:
    print(_client(args.display).read_capabilities())


def _cmd_get(args) -> None:
    code = int(args.code, 0)
    value = _client(args.display).get_vcp(code)
    if not value.supported:
        print(f"0x{code:02X}: unsupported")
    else:
        print(
            f"0x{code:02X}: type={value.vcp_type} "
            f"current={value.current} (0x{value.current:04X}) max={value.maximum}"
        )


def _cmd_set(args) -> None:
    code = int(args.code, 0)
    value = int(args.value, 0)
    check_writable(code, value)
    result = _client(args.display).set_vcp(code, value)
    print(f"0x{code:02X}: set to {result.current}, verified")


def _cmd_snapshot(args) -> None:
    client = _client(args.display)

    def progress(code: int) -> None:
        print(f"\rreading 0x{code:02X}", end="", file=sys.stderr, flush=True)

    snapshot = take_snapshot(client, on_progress=progress)
    print(file=sys.stderr)
    save_snapshot(snapshot, Path(args.output))
    print(
        f"saved {len(snapshot['values'])} supported codes, "
        f"{len(snapshot['errors'])} read errors to {args.output}"
    )


def _cmd_diff(args) -> None:
    changes = diff_snapshots(load_snapshot(Path(args.before)), load_snapshot(Path(args.after)))
    if not changes:
        print("no differences")
        return
    for change in changes:
        print(f"0x{change.code:02X}: {_format_value(change.before)}  ->  {_format_value(change.after)}")


def main() -> None:
    parser = argparse.ArgumentParser(prog="ddc-probe", description=__doc__)
    parser.add_argument("--display", type=int, default=0, help="external display index")
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("caps", help="print the display capabilities string").set_defaults(
        func=_cmd_caps
    )

    get = commands.add_parser("get", help="read one VCP code, e.g. 0x10")
    get.add_argument("code")
    get.set_defaults(func=_cmd_get)

    set_ = commands.add_parser("set", help="write an allowed VCP value and verify it")
    set_.add_argument("code")
    set_.add_argument("value")
    set_.set_defaults(func=_cmd_set)

    snapshot = commands.add_parser("snapshot", help="read all VCP codes into a JSON file")
    snapshot.add_argument("output")
    snapshot.set_defaults(func=_cmd_snapshot)

    diff = commands.add_parser("diff", help="compare two snapshot files")
    diff.add_argument("before")
    diff.add_argument("after")
    diff.set_defaults(func=_cmd_diff)

    args = parser.parse_args()
    try:
        args.func(args)
    except DDCError as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
