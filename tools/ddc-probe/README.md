# ddc-probe

A small DDC/CI research tool for finding which VCP code controls a monitor setting before
adding that setting to `monitorer`. It talks to external displays on Apple Silicon Macs through
the private `IOAVService` API (via `ctypes`), the same mechanism `monitorer`, m1ddc and
MonitorControl use.

Reads are safe. Writes are restricted to an explicit allowlist (`WRITABLE_VALUES` in
`src/ddc_probe/__init__.py`).

## Commands

Run everything from this directory with `uv`:

```sh
uv run ddc-probe caps                 # capabilities string declared by the monitor
uv run ddc-probe get 0x86             # read one VCP code
uv run ddc-probe snapshot out.json    # read all codes 0x00–0xFF into a JSON file (~20 s)
uv run ddc-probe diff a.json b.json   # show codes that differ between two snapshots
uv run ddc-probe set 0x86 8           # write an allowlisted value and verify it by reading back
uv run pytest                         # unit tests (no monitor needed)
```

`--display N` picks another external display (index among external displays, default `0`).

## Finding the VCP code for a setting

1. **Check the capabilities string.** `uv run ddc-probe caps` lists every code the monitor
   declares, with allowed values in parentheses for non-continuous controls, e.g.
   `86(01 02 04 21 22 08)`. Keep it next to the snapshots (`snapshots/capabilities.txt`).
2. **Take a baseline snapshot** with the setting in a known state:
   `uv run ddc-probe snapshot snapshots/<setting>-<state-a>.json`.
3. **Change the setting by hand in the monitor OSD.** Change nothing else.
4. **Take a second snapshot:** `uv run ddc-probe snapshot snapshots/<setting>-<state-b>.json`.
5. **Compare:** `uv run ddc-probe diff snapshots/<…a>.json snapshots/<…b>.json`.
   Ideally exactly one code changes. If several do, repeat with another state to see
   which one follows the setting.
6. **Map all states.** Repeat steps 3–5 for each OSD option you care about and write down
   the value of each one.
7. **Verify a write.** Add the code and the observed values to `WRITABLE_VALUES`, then
   `uv run ddc-probe set <code> <value>` and confirm on screen that the monitor changed.
   Switch back the same way. Never write values you have not observed or that the
   capabilities string does not declare.
8. **Add the command to `monitorer`** (see the root README).

Do not write to undocumented codes blindly: some VCP codes trigger factory resets or
other irreversible actions.

## Philips 346B1C notes

- Picture Format is VCP `0x86` (MCCS Display Scaling). Observed values:
  Wide screen = `8`, 16:9 = `4`. The capabilities string also declares `01 02 21 22`, which
  presumably map to 4:3, 1:1, Movie 1 and Movie 2; this has not been verified.
- Input is VCP `0x60` (MCCS Input Select). Writing the MCCS value switches the input:
  USB-C = `0x15`, HDMI 1 = `0x11`. On reads the monitor adds a vendor value in the high byte
  (`0x3515` on USB-C, `0x2111` on HDMI 1), so `ddc-probe set 0x60 …` reports "did not become"
  even though the switch happened; check the low byte of the "last read" value instead. The
  capabilities string also declares `00 0F 21 2F 35`; `0x0F` is DisplayPort per MCCS, the rest
  has not been mapped.
- Volume is VCP `0x62` (MCCS Audio Speaker Volume), continuous `0`...`100`; writes are echoed
  back exactly. VCP `0x8D` (Audio Mute) reads `2` (unmuted) and has not been written yet.
- The monitor keeps answering DDC from the Mac while it shows another input, which is what
  makes switching back from the Mac possible.
- The monitor answers a request only when it is written twice in a row; otherwise it replies
  with a null message ("not ready").
- After a Picture Format change the monitor ignores DDC requests for a couple of seconds.
- VCP `0xFE` returns a malformed reply; it is not relevant to anything known so far.
- `snapshots/` contains the capabilities string and the Wide screen / 16:9 snapshots used to
  identify `0x86`.
