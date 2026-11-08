import Foundation
import MonitorerCore

let monitorName = "PHL 346B1C"

let usage = """
    usage: monitorer <command>

    Switches the Picture Format of the \(monitorName) monitor over DDC/CI.

    commands:
      wide      switch to Wide screen
      16:9      switch to 16:9
      toggle    switch Wide screen to 16:9, anything else to Wide screen
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

let requested: PictureFormat?
switch command {
case "wide": requested = .wideScreen
case "16:9": requested = .sixteenByNine
case "toggle": requested = nil
default: fail("unknown command: \(command)\n\n\(usage)", code: 2)
}

do {
    let controller = PictureFormatController(
        client: DDCClient(transport: try ExternalDisplays.find(named: monitorName)))
    let format: PictureFormat
    if let requested {
        try controller.set(requested)
        format = requested
    } else {
        format = try controller.toggle()
    }
    print("Picture format: \(format.displayName)")
} catch {
    fail("error: \(error)")
}
