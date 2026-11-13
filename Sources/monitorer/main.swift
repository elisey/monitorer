import Foundation
import MonitorerCore

let monitorName = "PHL 346B1C"

let usage = """
    usage: monitorer <command>

    Controls the \(monitorName) monitor over DDC/CI: picture format, input and volume.

    commands:
      toggle    switch between the USB-C + Wide screen and HDMI + 16:9 scenes
      wide      switch the picture format to Wide screen
      narrow    switch the picture format to 16:9
      usbc      switch the input to USB-C
      hdmi      switch the input to HDMI
      volume    open a volume slider; Escape or a click outside closes it
    """

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 1, let command = arguments.first else { fail(usage, code: 2) }

if command == "-h" || command == "--help" {
    print(usage)
    exit(0)
}

enum Command {
    case toggle
    case format(PictureFormat)
    case input(InputSource)
    case volume
}

let parsed: Command
switch command {
case "toggle": parsed = .toggle
case "wide": parsed = .format(.wideScreen)
case "narrow": parsed = .format(.sixteenByNine)
case "usbc": parsed = .input(.usbC)
case "hdmi": parsed = .input(.hdmi1)
case "volume": parsed = .volume
default: fail("unknown command: \(command)\n\n\(usage)", code: 2)
}

do {
    let client = DDCClient(transport: try ExternalDisplays.find(named: monitorName))
    switch parsed {
    case .toggle:
        let scene = try SceneController(client: client).toggle()
        print("Picture format: \(scene.format.displayName), input: \(scene.input.displayName)")
    case .format(let format):
        try PictureFormatController(client: client).set(format)
        print("Picture format: \(format.displayName)")
    case .input(let input):
        try InputSourceController(client: client).set(input)
        print("Input: \(input.displayName)")
    case .volume:
        let controller = VolumeController(client: client)
        VolumeApp.run(controller: controller, initial: try controller.current())
    }
} catch {
    fail("error: \(error)")
}
