import Testing

@testable import MonitorerCore

private func controller(_ display: FakeDisplay) -> PictureFormatController {
    PictureFormatController(client: makeClient(display))
}

@Test func observedValues() {
    #expect(PictureFormat.vcpCode == 0x86)
    #expect(PictureFormat.wideScreen.rawValue == 8)
    #expect(PictureFormat.sixteenByNine.rawValue == 4)
}

@Test func setsSixteenByNine() throws {
    let display = FakeDisplay(values: [0x86: 8])
    try controller(display).set(.sixteenByNine)
    #expect(display.values[0x86] == 4)
}

@Test func setsWideScreen() throws {
    let display = FakeDisplay(values: [0x86: 4])
    try controller(display).set(.wideScreen)
    #expect(display.values[0x86] == 8)
}

@Test func setSkipsWriteWhenAlreadyInFormat() throws {
    let display = FakeDisplay(values: [0x86: 8])
    try controller(display).set(.wideScreen)
    #expect(display.setRequests.isEmpty)
}

@Test func toggleSwitchesWideToSixteenByNine() throws {
    let display = FakeDisplay(values: [0x86: 8])
    #expect(try controller(display).toggle() == .sixteenByNine)
    #expect(display.values[0x86] == 4)
}

@Test func toggleSwitchesSixteenByNineToWide() throws {
    let display = FakeDisplay(values: [0x86: 4])
    #expect(try controller(display).toggle() == .wideScreen)
    #expect(display.values[0x86] == 8)
}

@Test func toggleSwitchesUnmanagedFormatToWide() throws {
    // 0x01 is another Picture Format declared by the monitor (e.g. 4:3).
    let display = FakeDisplay(values: [0x86: 1])
    #expect(try controller(display).current() == nil)
    #expect(try controller(display).toggle() == .wideScreen)
    #expect(display.values[0x86] == 8)
}

@Test func twoTogglesReturnToOriginalFormat() throws {
    let display = FakeDisplay(values: [0x86: 8])
    let formats = controller(display)
    try formats.toggle()
    try formats.toggle()
    #expect(display.values[0x86] == 8)
}
