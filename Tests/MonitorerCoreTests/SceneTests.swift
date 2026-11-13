import Testing

@testable import MonitorerCore

private func controller(_ display: FakeDisplay) -> SceneController {
    SceneController(client: makeClient(display))
}

@Test func applySetsFormatBeforeInput() throws {
    let display = makeDisplayWithInput(0x15, format: 8)
    try controller(display).apply(.hdmiSixteenByNine)
    #expect(display.values[0x86] == 4)
    #expect(display.values[0x60] == 0x2111)
    #expect(display.setRequests.map(\.[2]) == [0x86, 0x86, 0x60, 0x60])
}

@Test func applySkipsStepsAlreadyInPlace() throws {
    let display = makeDisplayWithInput(0x11, format: 8)
    try controller(display).apply(.hdmiSixteenByNine)
    #expect(display.setRequests.map(\.[2]) == [0x86, 0x86])
}

@Test func toggleSwitchesUSBCToHDMIScene() throws {
    let display = makeDisplayWithInput(0x15, format: 8)
    #expect(try controller(display).toggle() == .hdmiSixteenByNine)
    #expect(display.values[0x86] == 4)
    #expect(display.values[0x60] == 0x2111)
}

@Test func toggleSwitchesHDMIToUSBCScene() throws {
    let display = makeDisplayWithInput(0x11, format: 4)
    #expect(try controller(display).toggle() == .usbCWide)
    #expect(display.values[0x86] == 8)
    #expect(display.values[0x60] == 0x3515)
}

@Test func toggleDecidesByInputNotFormat() throws {
    // Wide screen while on HDMI still counts as the HDMI scene, so toggle goes back to USB-C.
    let display = makeDisplayWithInput(0x11, format: 8)
    #expect(try controller(display).toggle() == .usbCWide)
    #expect(display.setRequests.map(\.[2]) == [0x60, 0x60])
}

@Test func toggleSwitchesUnmanagedInputToHDMIScene() throws {
    let display = makeDisplayWithInput(0x0F, format: 8)
    #expect(try controller(display).toggle() == .hdmiSixteenByNine)
    #expect(display.values[0x60] == 0x2111)
}

@Test func toggleStopsWhenFormatSwitchFails() {
    let display = makeDisplayWithInput(0x15, format: 8)
    display.ignoresSets = true
    #expect(throws: DDCError.self) { try controller(display).toggle() }
    #expect(display.setRequests.map(\.[2]) == [0x86, 0x86])
}
