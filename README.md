# monitorer

**Switch your monitor's Picture Format, input and volume from the macOS command line.**

`monitorer` drives three settings of a **Philips 346B1C** ultrawide monitor over DDC/CI: the
built-in *Picture Format* (**Wide screen (21:9)** or **16:9**), the *Input* (**USB-C** or
**HDMI**) and the speaker *Volume*, so you no longer have to dig through the on-screen menu. One hotkey moves the
monitor between a Mac on USB-C using the whole panel and a 16:9 device on HDMI (a game
console, say) shown without stretching. It changes the monitor's own settings, not the macOS
resolution.

```console
$ monitorer toggle
Picture format: 16:9, input: HDMI

$ monitorer toggle
Picture format: Wide screen, input: USB-C
```

- **One self-contained binary.** It talks to the monitor directly through IOKit; no m1ddc,
  ddcctl, Python or GUI app required.
- **Safe by design.** The monitor is identified by its EDID name, only a handful of known
  values of two VCP codes are ever written, and every write is verified by reading it back.
- **Works from either side.** The monitor keeps answering DDC on the inactive input, so the
  Mac can call the monitor back to itself while it is showing the HDMI device.
- **Fast.** A picture format switch takes about a second, a full scene switch two to three,
  which makes it a good fit for a hotkey.
- **Launcher friendly.** Clear output and exit codes for Raycast, Alfred, Shortcuts or scripts.
- **A volume slider on a hotkey.** `monitorer volume` pops up a small floating slider that
  drives the monitor's speakers and goes away on Escape or a click anywhere else.

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
| `monitorer toggle` | Switch between the two scenes: **USB-C + Wide screen** and **HDMI + 16:9** |
| `monitorer wide` | Switch the picture format to Wide screen (does nothing if already there) |
| `monitorer narrow` | Switch the picture format to 16:9 (does nothing if already there) |
| `monitorer usbc` | Switch the input to USB-C (does nothing if already there) |
| `monitorer hdmi` | Switch the input to HDMI (does nothing if already there) |
| `monitorer volume` | Open a floating volume slider; Escape or a click outside closes it |
| `monitorer --help` | Show usage |

`toggle` looks at the current input: on HDMI it goes to USB-C + Wide screen, on USB-C (or any
other input) it goes to HDMI + 16:9. The picture format is changed first and the input second,
so the device being switched to never sees the old format. The single-setting commands never
touch the other setting.

| Exit code | Meaning |
|---|---|
| `0` | Done; the resulting format, input or volume is printed to stdout |
| `1` | Monitor not found, no valid reply, or the new value was not applied (details on stderr). For `toggle` this can mean the format changed but the input did not; run it again or use `usbc` / `hdmi`. |
| `2` | Unknown command or wrong arguments |

### Hotkeys with Raycast

Raycast runs plain shell scripts as [Script Commands](https://github.com/raycast/script-commands)
and lets you bind a hotkey to each one. Both commands below assume the binary is installed with
`make install`; launchers do not load your shell `PATH`, so the scripts use the absolute path.

1. Pick a folder for your scripts, for example `~/raycast-scripts`, and create it.
2. Put the script files below into it and make them executable:

   ```sh
   chmod +x ~/raycast-scripts/*.sh
   ```

3. In Raycast open **Settings → Extensions → Script Commands → Add Directories** and add
   that folder. The scripts show up as commands named after their `@raycast.title`.
4. Select a command in the same list and set its **Hotkey**.

#### Scene toggle

`~/raycast-scripts/monitor-toggle.sh`:

```bash
#!/bin/bash

# @raycast.title Monitor Toggle
# @raycast.description Switch the monitor between USB-C + Wide screen and HDMI + 16:9
# @raycast.mode compact
# @raycast.schemaVersion 1

~/.local/bin/monitorer toggle
```

`compact` mode shows the result (or the error) as a toast once the command finishes.

#### Volume slider

`~/raycast-scripts/monitor-volume.sh`:

```bash
#!/bin/bash

# @raycast.title Monitor Volume
# @raycast.description Show a volume slider for the monitor speakers
# @raycast.mode silent
# @raycast.schemaVersion 1

~/.local/bin/monitorer volume
```

Use `silent` mode here: the command keeps running while the slider window is open, and
`compact` would show a spinner for that whole time. Pressing the hotkey opens the slider in the
middle of the screen under the mouse; drag it or nudge it with the arrow keys, then press Escape
or click anywhere else to dismiss it.

Every change is written to the monitor in the background; while a write is in flight only the
latest slider position is kept, so the monitor follows the slider without replaying intermediate
values. A DDC error is shown in red under the slider instead of closing the window.

## How it works

The monitor exposes all three settings as standard MCCS controls: Picture Format as **VCP
`0x86` (Display Scaling)**, the input as **VCP `0x60` (Input Select)** and the volume as **VCP
`0x62` (Audio Speaker Volume)**:

| OSD setting | VCP code | Value |
|---|---|---|
| Picture Format: Wide screen | `0x86` | `0x08` |
| Picture Format: 16:9 | `0x86` | `0x04` |
| Input: USB-C | `0x60` | `0x15` |
| Input: HDMI 1 | `0x60` | `0x11` |
| Volume | `0x62` | `0`...`100`, as reported by the monitor |

The format values were not taken from documentation. They were found by reading every VCP code
before and after switching the setting by hand in the OSD and comparing the two snapshots;
`0x86` was the only code that changed. The input values follow MCCS 2.2 and were confirmed by
switching over DDC and watching the monitor. The tool used for both lives in
[`tools/ddc-probe`](tools/ddc-probe).

Under the hood `monitorer`:

1. finds the external display named `PHL 346B1C` through the private `IOAVService` API (the
   same mechanism used by [m1ddc](https://github.com/waydabber/m1ddc) and
   [MonitorControl](https://github.com/MonitorControl/MonitorControl)), and refuses to continue
   if it is missing or ambiguous;
2. reads the VCP code to learn the current value and skips the write if nothing would change;
3. writes the target value and polls until the monitor reports it back.

The 346B1C has a few quirks the client handles: it answers a request only when the request is
written **twice** in a row; it **ignores DDC for a moment** after a format change, so reads are
retried for up to about five seconds; and on reads of `0x60` it fills the **high byte with a
vendor value** (`0x3515` for USB-C, `0x2111` for HDMI), so only the low byte is compared when
verifying an input switch.

## Troubleshooting

- **`display "PHL 346B1C" not found`**: check that DDC/CI is enabled in the monitor OSD and
  that the monitor is connected directly to the Mac. Some docks and adapters do not pass DDC
  through.
- **`no valid reply …` / `did not become …`**: the monitor was busy or the cable dropped the
  request. Run the command again; if it keeps failing, try another cable or port.
- **The monitor shows "no signal" after `hdmi`**: nothing is connected to HDMI 1 (or the
  device is asleep). Run `monitorer usbc` from the Mac, or pick the input in the OSD.
- **Another monitor model**: the picture format values are model specific, and the input
  values depend on which ports the monitor has. Use `tools/ddc-probe` to find the right VCP
  codes and values for your monitor before changing the constants in `PictureFormat.swift`
  and `InputSource.swift` and the name in `main.swift`.

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
    InputSource.swift   Input values and switching logic
    Scene.swift         format + input pairs and the toggle between them
    Volume.swift        speaker volume
    EDID.swift          monitor name from EDID
    IOAVService.swift   IOKit transport and display lookup
  monitorer/          command-line entry point
    main.swift          argument parsing and the one-shot commands
    VolumeWindow.swift  AppKit panel behind the volume command
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

If `swift test` fails with "plugin for module 'TestingMacros' not found", the Command Line
Tools toolchain is not loading the Swift Testing macros on its own; point it at them:

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## Disclaimer

`monitorer` relies on private macOS APIs, which may change between macOS releases. It writes
only values that were verified on a Philips 346B1C; use it with other monitors at your own risk.
