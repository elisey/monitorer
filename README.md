# monitorer

**Switch your monitor's Picture Format from the macOS command line.**

`monitorer` toggles the built-in *Picture Format* setting of a **Philips 346B1C** ultrawide
monitor between **Wide screen (21:9)** and **16:9** over DDC/CI, so you no longer have to dig
through the on-screen menu. It changes the monitor's own setting, not the macOS resolution.

```console
$ monitorer toggle
Picture format: 16:9

$ monitorer toggle
Picture format: Wide screen
```

- **One self-contained binary.** It talks to the monitor directly through IOKit; no m1ddc,
  ddcctl, Python or GUI app required.
- **Safe by design.** The monitor is identified by its EDID name, only two known values of one
  VCP code are ever written, and every write is verified by reading it back.
- **Fast.** A switch takes well under a second, which makes it a good fit for a hotkey.
- **Launcher friendly.** Clear output and exit codes for Raycast, Alfred, Shortcuts or scripts.

## Requirements

| | |
|---|---|
| Mac | Apple Silicon (tested on a MacBook Air M1, macOS 15.7) |
| Monitor | Philips 346B1C with **DDC/CI enabled** in the OSD |
| Connection | USB-C / DisplayPort (tested with a USB-C → DisplayPort cable) |
| Build tools | Xcode Command Line Tools (`xcode-select --install`) |

## Installation

```sh
git clone git@github.com:elisey/monitorer.git
cd monitorer
make install
```

This builds a release binary and installs it to `~/.local/bin/monitorer`; no `sudo` needed.
To install somewhere else, pass a prefix:

```sh
sudo make install PREFIX=/usr/local   # installs to /usr/local/bin
make uninstall                        # use the same PREFIX as for install
```

## Usage

| Command | Effect |
|---|---|
| `monitorer wide` | Switch to Wide screen (does nothing if already there) |
| `monitorer 16:9` | Switch to 16:9 (does nothing if already there) |
| `monitorer toggle` | Wide screen → 16:9; 16:9 or any other format → Wide screen |
| `monitorer --help` | Show usage |

| Exit code | Meaning |
|---|---|
| `0` | Done; the resulting format is printed to stdout |
| `1` | Monitor not found, no valid reply, or the new value was not applied (details on stderr) |
| `2` | Unknown command or wrong arguments |

### Hotkey with Raycast

Create a [Script Command](https://github.com/raycast/script-commands) and assign it a hotkey in
Raycast settings:

```bash
#!/bin/bash

# @raycast.title Monitor Toggle
# @raycast.description Toggle monitor Picture Format between Wide screen and 16:9
# @raycast.mode compact
# @raycast.schemaVersion 1

~/.local/bin/monitorer toggle
```

`compact` mode shows the result (or the error) as a toast. Launchers do not load your shell
`PATH`, so always use the absolute path to the binary.

## How it works

The monitor exposes Picture Format as the standard MCCS control **VCP `0x86` (Display
Scaling)**:

| OSD setting | VCP `0x86` value |
|---|---|
| Wide screen | `0x08` |
| 16:9 | `0x04` |

These values were not taken from documentation. They were found by reading every VCP code
before and after switching the setting by hand in the OSD and comparing the two snapshots;
`0x86` was the only code that changed. The tool used for that lives in
[`tools/ddc-probe`](tools/ddc-probe).

Under the hood `monitorer`:

1. finds the external display named `PHL 346B1C` through the private `IOAVService` API (the
   same mechanism used by [m1ddc](https://github.com/waydabber/m1ddc) and
   [MonitorControl](https://github.com/MonitorControl/MonitorControl)), and refuses to continue
   if it is missing or ambiguous;
2. reads VCP `0x86` to learn the current format;
3. writes the target value and polls until the monitor reports it back.

The 346B1C has two quirks the client handles: it answers a request only when the request is
written **twice** in a row, and it **ignores DDC for a moment** after a format change, so
reads are retried for up to about five seconds.

## Troubleshooting

- **`display "PHL 346B1C" not found`**: check that DDC/CI is enabled in the monitor OSD and
  that the monitor is connected directly to the Mac. Some docks and adapters do not pass DDC
  through.
- **`no valid reply …` / `did not become …`**: the monitor was busy or the cable dropped the
  request. Run the command again; if it keeps failing, try another cable or port.
- **Another monitor model**: the picture format values are model specific. Use
  `tools/ddc-probe` to find the right VCP code and values for your monitor before changing the
  constants in `PictureFormat.swift` and the name in `main.swift`.

## Development

```sh
make test    # unit tests (Swift Testing); no monitor needed
make build   # release build in .build/release/monitorer
```

```text
Sources/
  MonitorerCore/      library: everything testable lives here
    DDC.swift           DDC/CI packets and reply parsing
    DDCClient.swift     retries and verified writes over an I2C transport
    PictureFormat.swift Picture Format values and switching logic
    EDID.swift          monitor name from EDID
    IOAVService.swift   IOKit transport and display lookup
  monitorer/          command-line entry point
Tests/                unit tests using an in-memory fake display
tools/ddc-probe/      Python tool for discovering VCP codes of other settings
```

### Adding a command for another setting

1. Find the VCP code and its values with [`tools/ddc-probe`](tools/ddc-probe) (snapshot →
   change the setting in the OSD → snapshot → diff) and verify a write with `ddc-probe set`.
2. Model the setting in `MonitorerCore` the way `PictureFormat.swift` does: an enum of the
   observed values plus a small controller on top of `DDCClient`, covered by tests with
   `FakeDisplay`.
3. Add the command and its usage line to `Sources/monitorer/main.swift`.

## Disclaimer

`monitorer` relies on private macOS APIs, which may change between macOS releases. It writes
only values that were observed on a Philips 346B1C; use it with other monitors at your own risk.
